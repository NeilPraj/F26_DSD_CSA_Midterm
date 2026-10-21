#!/bin/bash
# launch_parallel_carry_select.sh - carry_select_16 Monte Carlo on parallel single-threaded ngspice
# copies, built to survive Spot VM preemption.
#
# Work is split into small chunks. A finished chunk is saved immediately (and uploaded, if SYNC_DEST
# is set), so a preemption only loses the chunks that were in flight, and the run can be resumed on
# the same VM or on a brand new one.
#
# ---------------------------------------------------------------------------------------- usage
#   ./launch_parallel_carry_select.sh <total_trials> [workers]     start a new run
#   RESUME=<run_id> ./launch_parallel_carry_select.sh [workers]    finish an interrupted run
#   RESUME=latest   ./launch_parallel_carry_select.sh [workers]    ...the newest unfinished local run
#   ./launch_parallel_carry_select.sh status [run_id]              progress of a run (default: newest)
#
#   e.g.  tmux new -s mc
#         SYNC_DEST=gs://my-bucket/mc ./launch_parallel_carry_select.sh 10000 384
#
# ALWAYS start it inside tmux (or with nohup ... &). A plain SSH session that drops kills the run.
# Check on it from any other shell with:   ./launch_parallel_carry_select.sh status
#
# ---------------------------------------------------------------------------------------- options
#   SYNC_DEST=gs://bucket/path   copy results off the VM as they finish. Strongly recommended on Spot:
#                                a preempted VM with termination action DELETE takes its disk with it.
#                                Accepts gs:// (gcloud or gsutil), s3:// (aws cli), or a local / mounted
#                                directory. Run dir lands at $SYNC_DEST/<run_id>/.
#   CHUNK=20                     trials per chunk. Default: ~4 chunks per worker, capped at 20
#                                (~10-15 min per chunk at ~36 s/trial). Fixed for the life of a run.
#   BASE_SEED=1234               reproduce a run. Chunk k uses seed BASE_SEED + k.
#   PROGRESS_EVERY=60            seconds between progress lines (0 = off).
#
# ---------------------------------------------------------------------------------------- Spot VMs
# What happens on preemption:
#   1. A watcher polls the cloud metadata server every 5 s (GCP: instance/preempted, AWS: spot
#      instance-action). On notice - or on the SIGTERM the OS sends at shutdown, whichever is first -
#      all workers are stopped and the session is logged as "preempted".
#   2. Finished chunks are already on disk and (with SYNC_DEST) already in the bucket. A final quick
#      sync pushes the logs. GCP gives ~30 s, AWS ~2 min; uploads are capped at 20 s.
#   3. Resume:
#        same VM (termination action STOP):  RESUME=latest ./launch_parallel_carry_select.sh 384
#        new VM:  copy this script, gen_mc.py and ../cell_lib.sp over, then
#                 SYNC_DEST=gs://my-bucket/mc RESUME=<run_id> ./launch_parallel_carry_select.sh 384
#                 (the run is downloaded from the bucket first; the run's own copy of the netlist is
#                 used, so it doesn't matter if gen_mc.py changed since).
#
# ---------------------------------------------------------------------------------------- layout
# runs/<run_id>/
#   params                       TOTAL, CHUNK, BASE_SEED (read back on resume)
#   netlist.sp                   the exact netlist this run uses (snapshot taken when the run started)
#   chunks/chunk_<k>.txt         one finished chunk; only appears once it fully succeeded
#   progress.txt                 latest progress line, refreshed every PROGRESS_EVERY seconds
#   work/                        per-chunk netlists and logs (scratch; never uploaded)
#   carry_select_mc_merged.txt   all chunks merged, written once every chunk is done
#   run_info.txt                 log of every session of this run
# runs/timing_log.csv            one row per session (host, CPU, trials, trials/s, status ...)
# timing_results.txt             one human-readable line per session

set -euo pipefail
cd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)
SELF=./$(basename "$0")

SRC=carry_select_mc.sp
GEN=gen_mc.py
OUT=carry_select_mc.txt          # file named in the netlist's wrdata line
LOG_CSV=runs/timing_log.csv
HOST=$(uname -n)
CPU=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)
CPU=${CPU:-unknown}
PROGRESS_EVERY=${PROGRESS_EVERY:-60}
SYNC_DEST=${SYNC_DEST:-}
SYNC_DEST=${SYNC_DEST%/}

# ================================================================ helpers

hms() { awk -v t="$1" 'BEGIN { t = int(t); printf "%dh %02dm %02ds", t/3600, (t%3600)/60, t%60 }'; }

# Newest run in runs/ (optionally: only unfinished ones).
newest_run() {
    local d
    for d in $(ls -1d runs/*/ 2>/dev/null | sort -r); do
        [[ -f $d/params ]] || continue
        [[ ${1:-} == unfinished && -f $d/carry_select_mc_merged.txt ]] && continue
        basename "$d"; return
    done
}

# Counts for a run: "<trials_done> <chunks_done>". Trials in in-flight chunks are counted from the
# MC_TRIAL_DONE markers ngspice prints after every trial, so progress moves between chunk completions.
count_progress() {
    local rd=$1 full partial=0 log k c nd
    nd=$(find "$rd/chunks" -name 'chunk_*.txt' 2>/dev/null | wc -l)
    full=$(find "$rd/chunks" -name 'chunk_*.txt' -exec awk 'FNR > 1 { n++ } END { print n + 0 }' {} + 2>/dev/null \
           | awk '{ s += $1 } END { print s + 0 }')
    for log in "$rd"/work/chunk_*.log; do
        [[ -e $log ]] || continue
        k=${log##*/chunk_}; k=${k%.log}
        [[ -f $rd/chunks/chunk_$k.txt ]] && continue
        c=$(grep -c MC_TRIAL_DONE "$log" 2>/dev/null || true)
        partial=$(( partial + ${c:-0} ))
    done
    echo "$(( full + partial )) $nd"
}

# ---------------------------------------------------------------- off-VM sync
sync_tool() {
    case $SYNC_DEST in
        gs://*) if command -v gcloud >/dev/null; then echo gcloud; elif command -v gsutil >/dev/null; then echo gsutil
                else echo none; fi ;;
        s3://*) command -v aws >/dev/null && echo aws || echo none ;;
        *)      echo local ;;
    esac
}

# Upload one file (path relative to runs/).
sync_file() {
    [[ -n $SYNC_DEST ]] || return 0
    local src=runs/$1 dst=$SYNC_DEST/$1
    case $(sync_tool) in
        gcloud) gcloud storage cp -q "$src" "$dst" >/dev/null 2>&1 ;;
        gsutil) gsutil -q cp "$src" "$dst" >/dev/null 2>&1 ;;
        aws)    aws s3 cp --only-show-errors "$src" "$dst" >/dev/null 2>&1 ;;
        local)  mkdir -p "$(dirname "$dst")" && cp "$src" "$dst" ;;
        *)      return 1 ;;
    esac
}

# Mirror a whole run dir (minus work/) up to or down from SYNC_DEST.
sync_run() {
    [[ -n $SYNC_DEST ]] || return 0
    local dir=$1 id=$2 a b
    if [[ $dir == up ]]; then a=runs/$id; b=$SYNC_DEST/$id; else a=$SYNC_DEST/$id; b=runs/$id; fi
    mkdir -p runs/"$id"
    case $(sync_tool) in
        gcloud) gcloud storage rsync -r -q --exclude='^work/' "$a" "$b" >/dev/null 2>&1 ;;
        gsutil) gsutil -q -m rsync -r -x '^work/' "$a" "$b" >/dev/null 2>&1 ;;
        aws)    aws s3 sync --only-show-errors --exclude 'work/*' "$a" "$b" >/dev/null 2>&1 ;;
        local)  [[ -d $a ]] || return 1
                mkdir -p "$b"
                local abs_b; abs_b=$(cd "$b" && pwd)
                (cd "$a" && find . -path ./work -prune -o -type f -print0 | xargs -0 -r cp --parents -t "$abs_b") ;;
        *)      return 1 ;;
    esac
}

# ================================================================ status command
if [[ ${1:-} == status ]]; then
    RUN_ID=${2:-$(newest_run)}
    [[ -n $RUN_ID && -f runs/$RUN_ID/params ]] || { echo "No run found${2:+ named $2}"; exit 1; }
    # shellcheck source=/dev/null
    source "runs/$RUN_ID/params"
    read -r t c < <(count_progress "runs/$RUN_ID")
    n=$(( (TOTAL + CHUNK - 1) / CHUNK ))
    printf 'Run %s: %d / %d trials (%s%%), %d / %d chunks done, %d ngspice running\n' \
        "$RUN_ID" "$t" "$TOTAL" "$(awk -v a="$t" -v b="$TOTAL" 'BEGIN { printf "%.1f", 100 * a / b }')" \
        "$c" "$n" "$(pgrep -c -x ngspice || true)"
    if [[ -f runs/$RUN_ID/progress.txt ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "runs/$RUN_ID/progress.txt") ))
        echo "Last progress line (${age}s ago): $(cat "runs/$RUN_ID/progress.txt")"
    fi
    [[ -f runs/$RUN_ID/carry_select_mc_merged.txt ]] && echo "Finished: runs/$RUN_ID/carry_select_mc_merged.txt"
    exit 0
fi

# ================================================================ new run or resume
if [[ -n ${RESUME:-} ]]; then
    if [[ $RESUME == latest ]]; then
        RESUME=$(newest_run unfinished)
        [[ -n $RESUME ]] || { echo "No unfinished run in runs/ to resume"; exit 1; }
    fi
    RUN_ID=$RESUME
    RUN_DIR=runs/$RUN_ID
    if [[ -n $SYNC_DEST ]]; then
        echo "Pulling $RUN_ID from $SYNC_DEST ..."
        sync_run down "$RUN_ID" || echo "Warning: download from $SYNC_DEST failed - using local files only"
    fi
    [[ -f $RUN_DIR/params ]] || { echo "No run to resume at $RUN_DIR (missing params file)"; exit 1; }
    # shellcheck source=/dev/null
    source "$RUN_DIR/params"          # sets TOTAL, CHUNK, BASE_SEED
    if [[ ! -f $RUN_DIR/netlist.sp ]]; then
        [[ -f $SRC ]] || { echo "Missing $RUN_DIR/netlist.sp and $SRC - can't resume"; exit 1; }
        cp "$SRC" "$RUN_DIR/netlist.sp"
    fi
    WORKERS=${1:-$(nproc)}
    MODE=resumed
else
    TOTAL=${1:?usage: $0 <total_trials> [workers]  |  RESUME=<run_id|latest> $0 [workers]  |  $0 status}
    WORKERS=${2:-$(nproc)}
    if [[ ! -f $SRC || $GEN -nt $SRC ]]; then
        echo "Generating $SRC from $GEN"
        python3 "$GEN"
    fi
    if [[ -z ${CHUNK:-} ]]; then
        CHUNK=$(( (TOTAL + WORKERS * 4 - 1) / (WORKERS * 4) ))
        (( CHUNK > 20 )) && CHUNK=20
        (( CHUNK < 1 )) && CHUNK=1
    fi
    if (( (TOTAL + CHUNK - 1) / CHUNK < WORKERS )); then
        echo "Warning: only $(( (TOTAL + CHUNK - 1) / CHUNK )) chunks for $WORKERS workers - some will sit idle. Lower CHUNK."
    fi
    BASE_SEED=${BASE_SEED:-$(( $(od -An -N4 -tu4 /dev/urandom) % 2000000000 ))}
    RUN_ID=$(date +%Y%m%d_%H%M%S)
    RUN_DIR=runs/$RUN_ID
    mkdir -p "$RUN_DIR"
    printf 'TOTAL=%d\nCHUNK=%d\nBASE_SEED=%d\n' "$TOTAL" "$CHUNK" "$BASE_SEED" > "$RUN_DIR/params"
    cp "$SRC" "$RUN_DIR/netlist.sp"
    MODE=new
fi

if [[ -n $SYNC_DEST ]]; then
    [[ $(sync_tool) != none ]] || { echo "SYNC_DEST=$SYNC_DEST but no gcloud/gsutil/aws CLI found"; exit 1; }
    echo "Syncing finished chunks to $SYNC_DEST/$RUN_ID/ (via $(sync_tool))"
else
    echo "Note: SYNC_DEST not set - results live only on this VM's disk. On Spot, set SYNC_DEST=gs://... ."
fi

NCHUNKS=$(( (TOTAL + CHUNK - 1) / CHUNK ))
CHUNK_DIR=$RUN_DIR/chunks
WORK_DIR=$RUN_DIR/work
mkdir -p "$CHUNK_DIR" "$WORK_DIR"
SESSION_FILE=$WORK_DIR/session_$$.done
: > "$SESSION_FILE"

# ---------------------------------------------------------------- netlist template
# Built from the run's own snapshot. Relative .include paths are made absolute (chunk netlists live
# in work/), and a marker is printed after each trial so progress can be tracked inside a chunk.
TEMPLATE=$WORK_DIR/template.sp
awk -v dir="$SCRIPT_DIR" '
    tolower($1) == ".include" && $2 !~ /^\// { $2 = dir "/" $2 }
    { print }
' "$RUN_DIR/netlist.sp" \
    | sed '/^[[:space:]]*let current_run = current_run + 1/a\  echo MC_TRIAL_DONE' > "$TEMPLATE"
grep -q MC_TRIAL_DONE "$TEMPLATE" || echo "Note: couldn't add per-trial markers - progress will update per chunk only"

if [[ -x /usr/bin/time ]]; then HAVE_TIME=1; else
    HAVE_TIME=0
    echo "Note: /usr/bin/time not found - skipping per-chunk stats (apt install time / pacman -S time)"
fi

if grep -q '^set num_threads' .spiceinit 2>/dev/null; then
    sed -i 's/^set num_threads.*/set num_threads=1/' .spiceinit
else
    echo 'set num_threads=1' >> .spiceinit
fi
export OMP_NUM_THREADS=1

# ---------------------------------------------------------------- one chunk
run_chunk() {
    local k=$1
    local n=$(( k < NCHUNKS - 1 ? CHUNK : TOTAL - CHUNK * (NCHUNKS - 1) ))
    local seed=$(( BASE_SEED + k ))
    local sp=$WORK_DIR/chunk_$k.sp
    local part=$WORK_DIR/chunk_$k.part
    local out=$CHUNK_DIR/chunk_$k.txt

    sed -e "s/^let mc_runs = .*/let mc_runs = $n/" \
        -e "s|wrdata $OUT|wrdata $part|" \
        -e "/^\.control/a set rndseed=$seed" \
        "$TEMPLATE" > "$sp"
    rm -f "$part"

    local rc=0
    if (( HAVE_TIME )); then
        /usr/bin/time -f '%e %U %S %M' -o "$WORK_DIR/chunk_$k.time" \
            ngspice "$sp" < /dev/null > "$WORK_DIR/chunk_$k.log" 2>&1 || rc=$?
    else
        ngspice "$sp" < /dev/null > "$WORK_DIR/chunk_$k.log" 2>&1 || rc=$?
    fi

    if (( rc == 0 )) && [[ -f $part ]] && (( $(wc -l < "$part") == n + 1 )); then
        mv "$part" "$out"
        echo "$n" >> "$SESSION_FILE"
        # Off the VM right away. A failed upload isn't fatal: the end-of-session sync retries it.
        sync_file "$RUN_ID/chunks/chunk_$k.txt" || echo "  (upload of chunk $k failed - will retry at the end)"
    else
        echo "  chunk $k FAILED (exit $rc) - see $WORK_DIR/chunk_$k.log"
        return 1
    fi
}
export -f run_chunk sync_file sync_tool
export NCHUNKS CHUNK TOTAL BASE_SEED WORK_DIR CHUNK_DIR TEMPLATE SESSION_FILE HAVE_TIME OUT RUN_ID SYNC_DEST

# ---------------------------------------------------------------- bookkeeping
count_done() { find "$CHUNK_DIR" -name 'chunk_*.txt' | wc -l; }

kill_tree() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
    kill -TERM "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------- run the pending chunks: setup
mapfile -t PENDING < <(for ((k = 0; k < NCHUNKS; k++)); do
    [[ -f $CHUNK_DIR/chunk_$k.txt ]] || echo "$k"
done)
# Logs of unfinished chunks are stale (from an interrupted session); clear them so the in-flight
# trial count starts from zero.
for k in "${PENDING[@]}"; do rm -f "$WORK_DIR/chunk_$k.log"; done

START_EPOCH=$(date +%s.%N)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
read -r START_TRIALS _ < <(count_progress "$RUN_DIR")   # trials already done when this session began

# One progress line: trials, %, chunks, and rate/ETA from this session's own throughput.
progress_line() {
    local t c elapsed rate eta pct
    read -r t c < <(count_progress "$RUN_DIR")
    elapsed=$(awk -v s="$START_EPOCH" -v e="$(date +%s.%N)" 'BEGIN { print e - s }')
    pct=$(awk -v a="$t" -v b="$TOTAL" 'BEGIN { printf "%.1f", 100 * a / b }')
    rate=$(awk -v d=$(( t - START_TRIALS )) -v e="$elapsed" 'BEGIN { printf "%.3f", (e > 0 ? d / e : 0) }')
    if awk -v r="$rate" 'BEGIN { exit !(r > 0) }'; then
        eta="ETA $(hms "$(awk -v r="$rate" -v left=$(( TOTAL - t )) 'BEGIN { print left / r }')")"
    else
        eta="ETA --"
    fi
    printf '[%s] %d/%d trials (%s%%) | %d/%d chunks | %d busy | %s trials/s | elapsed %s | %s\n' \
        "$(date '+%H:%M:%S')" "$t" "$TOTAL" "$pct" "$c" "$NCHUNKS" "$(pgrep -c -x ngspice || true)" \
        "$rate" "$(hms "$elapsed")" "$eta"
}

log_run() {
    local status=$1
    local end_human elapsed done_trials spt tps
    end_human=$(date '+%Y-%m-%d %H:%M:%S')
    elapsed=$(awk -v s="$START_EPOCH" -v e="$(date +%s.%N)" 'BEGIN { printf "%.1f", e - s }')
    done_trials=$(awk '{ s += $1 } END { print s + 0 }' "$SESSION_FILE")
    spt=$(awk -v t="$elapsed" -v n="$done_trials" 'BEGIN { printf "%.4f", (n > 0 ? t / n : 0) }')
    tps=$(awk -v t="$elapsed" -v n="$done_trials" 'BEGIN { printf "%.2f", (t > 0 ? n / t : 0) }')

    [[ -f $LOG_CSV ]] || echo "run_id,host,cpu,workers,trials,base_seed,start,end,elapsed_s,s_per_trial,trials_per_s,status" > "$LOG_CSV"
    echo "$RUN_ID,$HOST,\"$CPU\",$WORKERS,$done_trials,$BASE_SEED,$START_HUMAN,$end_human,$elapsed,$spt,$tps,$status" >> "$LOG_CSV"

    printf '%s on %s: %d trials finished this session, %d workers, %s elapsed (%s s/trial, %s trials/s) [%s]\n' \
        "$RUN_ID" "$HOST" "$done_trials" "$WORKERS" "$(hms "$elapsed")" "$spt" "$tps" "$status" \
        | tee -a timing_results.txt "$RUN_DIR/run_info.txt"
    echo "Progress: $(count_done) of $NCHUNKS chunks done. Finished: $end_human" | tee -a "$RUN_DIR/run_info.txt"
}

# ---------------------------------------------------------------- preemption watcher
# Detect the cloud once, then poll its preemption notice and SIGTERM ourselves when it appears.
PREEMPT_FLAG=$WORK_DIR/preempted_$$
detect_cloud() {
    if curl -sf -m 2 --noproxy '*' -H 'Metadata-Flavor: Google' \
         http://metadata.google.internal/computeMetadata/v1/instance/id >/dev/null 2>&1; then echo gcp
    elif curl -sf -m 2 --noproxy '*' -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
         http://169.254.169.254/latest/api/token >/dev/null 2>&1; then echo aws
    else echo none; fi
}
preempt_noticed() {
    case $CLOUD in
        gcp) [[ $(curl -s -m 2 --noproxy '*' -H 'Metadata-Flavor: Google' \
                 http://metadata.google.internal/computeMetadata/v1/instance/preempted 2>/dev/null) == TRUE ]] ;;
        aws) local tok
             tok=$(curl -sf -m 2 --noproxy '*' -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
                 http://169.254.169.254/latest/api/token 2>/dev/null) || return 1
             [[ $(curl -s -m 2 --noproxy '*' -o /dev/null -w '%{http_code}' -H "X-aws-ec2-metadata-token: $tok" \
                 http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null) == 200 ]] ;;
        *)   return 1 ;;
    esac
}
CLOUD=$(detect_cloud)
case $CLOUD in
    gcp) echo "GCP detected - watching for Spot preemption notices" ;;
    aws) echo "AWS detected - watching for Spot interruption notices" ;;
    *)   echo "No cloud metadata server found - preemption watcher off (SIGTERM is still handled)" ;;
esac

BG_PIDS=()
stop_bg() { local p; for p in "${BG_PIDS[@]}"; do kill_tree "$p"; done; BG_PIDS=(); }

# ---------------------------------------------------------------- Ctrl-C / SIGTERM / preemption
# Bash only runs a trap between commands; `wait` is the one place a signal interrupts immediately,
# which is why xargs runs in the background below.
XARGS_PID=
on_interrupt() {
    trap - INT TERM
    local status=interrupted
    [[ -f $PREEMPT_FLAG ]] && status=preempted
    echo "Stopping workers ($status)..."
    stop_bg
    [[ -n $XARGS_PID ]] && kill_tree "$XARGS_PID"
    progress_line > "$RUN_DIR/progress.txt" 2>/dev/null || true
    log_run "$status"
    if [[ -n $SYNC_DEST ]]; then
        timeout 20 bash -c "$(declare -f sync_run sync_tool); SYNC_DEST='$SYNC_DEST'; sync_run up '$RUN_ID'" \
            || echo "Final sync didn't finish (chunks were already uploaded as they completed)"
    fi
    echo "Resume with:  ${SYNC_DEST:+SYNC_DEST=$SYNC_DEST }RESUME=$RUN_ID $SELF $WORKERS"
    exit 1
}
trap on_interrupt INT TERM

{
    echo "== Session on $HOST ($CPU), $MODE, $START_HUMAN"
    echo "Run $RUN_ID: $TOTAL trials in $NCHUNKS chunks of $CHUNK, base seed $BASE_SEED"
    echo "$(( NCHUNKS - ${#PENDING[@]} )) chunks already done, ${#PENDING[@]} to go, $WORKERS workers"
} | tee -a "$RUN_DIR/run_info.txt"
sync_file "$RUN_ID/params" || true
sync_file "$RUN_ID/netlist.sp" || true
sync_file "$RUN_ID/run_info.txt" || true

if [[ $CLOUD != none ]]; then
    ( while sleep 5; do
          if preempt_noticed; then
              echo "*** Preemption notice received ***"
              : > "$PREEMPT_FLAG"
              kill -TERM $$
              exit 0
          fi
      done ) &
    BG_PIDS+=($!)
fi

if (( PROGRESS_EVERY > 0 )); then
    ( while sleep "$PROGRESS_EVERY"; do
          line=$(progress_line)
          echo "$line"
          echo "$line" > "$RUN_DIR/progress.txt"
          sync_file "$RUN_ID/progress.txt" || true
      done ) &
    BG_PIDS+=($!)
fi

fail=0
if (( ${#PENDING[@]} > 0 )); then
    xargs -P "$WORKERS" -I{} bash -c 'run_chunk "$1"' _ {} < <(printf '%s\n' "${PENDING[@]}") &
    XARGS_PID=$!
    wait "$XARGS_PID" || fail=1
    XARGS_PID=
fi
stop_bg

progress_line | tee "$RUN_DIR/progress.txt"

if (( HAVE_TIME )) && compgen -G "$WORK_DIR/chunk_*.time" > /dev/null; then
    tail -q -n 1 "$WORK_DIR"/chunk_*.time | awk '
        { n++; e += $1; u += $2; if ($4 > m) m = $4 }
        END { if (n) printf "Chunk timing: %d chunks, %.1f s mean elapsed, %.1f s mean user, %.0f MB max peak\n", n, e/n, u/n, m/1024 }
    ' | tee -a "$RUN_DIR/run_info.txt"
fi

DONE=$(count_done)
if (( DONE < NCHUNKS )); then fail=1; fi
if (( fail )); then log_run failed; else log_run ok; fi

# ---------------------------------------------------------------- merge once everything is in
# Column 1 is a duplicate of tplh_cout (wrdata's scale column). Ignore it in analysis.
if (( DONE == NCHUNKS )); then
    MERGED=$RUN_DIR/carry_select_mc_merged.txt
    head -n 1 "$CHUNK_DIR/chunk_0.txt" > "$MERGED"
    for ((k = 0; k < NCHUNKS; k++)); do
        tail -n +2 "$CHUNK_DIR/chunk_$k.txt" >> "$MERGED"
    done
    rows=$(( $(wc -l < "$MERGED") - 1 ))
    echo "Merged $rows of $TOTAL trials into $MERGED" | tee -a "$RUN_DIR/run_info.txt"
    [[ $rows -eq $TOTAL ]] || echo "WARNING: row count doesn't match - check the chunk logs"
else
    echo "Not merged yet: $(( NCHUNKS - DONE )) chunks missing."
    echo "Resume with:  ${SYNC_DEST:+SYNC_DEST=$SYNC_DEST }RESUME=$RUN_ID $SELF $WORKERS"
fi

# Push everything (any chunk whose upload failed, logs, merged file) off the VM.
if [[ -n $SYNC_DEST ]]; then
    if sync_run up "$RUN_ID"; then echo "Synced to $SYNC_DEST/$RUN_ID/"
    else echo "WARNING: final sync to $SYNC_DEST failed"; fi
fi

exit $fail
