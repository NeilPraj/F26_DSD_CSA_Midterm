#!/bin/bash
# launch_parallel.sh - split a Monte Carlo run into small chunks and run them on parallel
# single-threaded ngspice copies. Finished chunks are saved immediately, so a crash, Ctrl-C or
# cloud Spot preemption only loses the chunks that were in flight, and the run can be resumed.
#
# Usage:
#   ./launch_parallel.sh <total_trials> [workers]        start a new run
#   RESUME=<run_id> ./launch_parallel.sh [workers]       finish an interrupted run
#
#   e.g.  ./launch_parallel.sh 1000000 384
#         RESUME=20261017_093012 ./launch_parallel.sh 384
#
# Options (environment variables):
#   CHUNK=500          trials per chunk. Default: whatever gives each worker ~4 chunks, capped at
#                      500. Smaller = less lost on interruption, slightly more ngspice start-up
#                      overhead. Fixed for the life of a run.
#   BASE_SEED=1234     reproduce a run. Chunk k uses seed BASE_SEED + k, so results don't depend
#                      on the worker count or which machine ran which chunk.
#
# Layout of runs/<run_id>/:
#   params                    TOTAL, CHUNK, BASE_SEED (read back on resume)
#   chunks/chunk_<k>.txt      one finished chunk; a chunk only appears here once it fully succeeded
#   work/                     per-chunk netlists, logs and timings (scratch; safe to delete)
#   full_adder_mc_merged.txt  all chunks merged, written once every chunk is done
#   run_info.txt              human-readable log of every session of this run
#
# Timing is recorded in three places:
#   runs/<run_id>/run_info.txt  - seeds, sessions, per-chunk time summary
#   runs/timing_log.csv         - one row per session (host, CPU, trials done, trials/s, ...)
#   timing_results.txt          - one human-readable summary line per session

set -euo pipefail
cd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)

SRC=full_adder_mc.sp
LOG_CSV=runs/timing_log.csv
HOST=$(uname -n)   # coreutils; `hostname` isn't installed by default on Arch
CPU=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)
CPU=${CPU:-unknown}

# ---------------------------------------------------------------- new run or resume
if [[ -n ${RESUME:-} ]]; then
    RUN_ID=$RESUME
    RUN_DIR=runs/$RUN_ID
    [[ -f $RUN_DIR/params ]] || { echo "No run to resume at $RUN_DIR (missing params file)"; exit 1; }
    # shellcheck source=/dev/null
    source "$RUN_DIR/params"          # sets TOTAL, CHUNK, BASE_SEED
    WORKERS=${1:-$(nproc)}
    MODE=resumed
else
    TOTAL=${1:?usage: $0 <total_trials> [workers]   or   RESUME=<run_id> $0 [workers]}
    WORKERS=${2:-$(nproc)}
    # Default chunk size: up to 500 trials, but small enough that every worker gets ~4 chunks.
    # Too few chunks leaves workers idle (2 chunks = only 2 workers busy, however many you ask for).
    if [[ -z ${CHUNK:-} ]]; then
        CHUNK=$(( (TOTAL + WORKERS * 4 - 1) / (WORKERS * 4) ))
        (( CHUNK > 500 )) && CHUNK=500
        (( CHUNK < 1 )) && CHUNK=1
    fi
    if (( (TOTAL + CHUNK - 1) / CHUNK < WORKERS )); then
        echo "Warning: only $(( (TOTAL + CHUNK - 1) / CHUNK )) chunks for $WORKERS workers - some will sit idle. Lower CHUNK."
    fi
    # Random base seed per run (fits in a signed 32-bit int with room for the chunk offsets).
    BASE_SEED=${BASE_SEED:-$(( $(od -An -N4 -tu4 /dev/urandom) % 2000000000 ))}
    RUN_ID=$(date +%Y%m%d_%H%M%S)
    RUN_DIR=runs/$RUN_ID
    mkdir -p "$RUN_DIR"
    printf 'TOTAL=%d\nCHUNK=%d\nBASE_SEED=%d\n' "$TOTAL" "$CHUNK" "$BASE_SEED" > "$RUN_DIR/params"
    MODE=new
fi

NCHUNKS=$(( (TOTAL + CHUNK - 1) / CHUNK ))
CHUNK_DIR=$RUN_DIR/chunks
WORK_DIR=$RUN_DIR/work
mkdir -p "$CHUNK_DIR" "$WORK_DIR"
SESSION_FILE=$WORK_DIR/session_$$.done      # trials finished in this session, one line per chunk
: > "$SESSION_FILE"

# ---------------------------------------------------------------- netlist template
# The per-chunk netlists live in work/, so make any relative .include absolute.
TEMPLATE=$WORK_DIR/template.sp
awk -v dir="$SCRIPT_DIR" '
    tolower($1) == ".include" && $2 !~ /^\// { $2 = dir "/" $2 }
    { print }
' "$SRC" > "$TEMPLATE"

# GNU time gives per-chunk elapsed/CPU/memory. If it's missing:
#   Ubuntu: sudo apt install time      Arch: sudo pacman -S time
if [[ -x /usr/bin/time ]]; then HAVE_TIME=1; else
    HAVE_TIME=0
    echo "Note: /usr/bin/time not found - skipping per-chunk stats (apt install time / pacman -S time)"
fi

# Single-threaded ngspice: each worker should use exactly one core.
if grep -q '^set num_threads' .spiceinit 2>/dev/null; then
    sed -i 's/^set num_threads.*/set num_threads=1/' .spiceinit
else
    echo 'set num_threads=1' >> .spiceinit
fi
export OMP_NUM_THREADS=1

# ---------------------------------------------------------------- one chunk
# Runs in an xargs child. Writes to a .part file and renames it only on success, so anything in
# chunks/ is guaranteed complete.
run_chunk() {
    local k=$1
    local n=$(( k < NCHUNKS - 1 ? CHUNK : TOTAL - CHUNK * (NCHUNKS - 1) ))
    local seed=$(( BASE_SEED + k ))
    local sp=$WORK_DIR/chunk_$k.sp
    local part=$WORK_DIR/chunk_$k.part
    local out=$CHUNK_DIR/chunk_$k.txt

    sed -e "s/^let mc_runs = .*/let mc_runs = $n/" \
        -e "s|wrdata full_adder_mc\.txt|wrdata $part|" \
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

    # Success = ngspice exited cleanly AND wrote a header plus n data rows.
    if (( rc == 0 )) && [[ -f $part ]] && (( $(wc -l < "$part") == n + 1 )); then
        mv "$part" "$out"
        echo "$n" >> "$SESSION_FILE"
        echo "  chunk $k done ($n trials) at $(date '+%H:%M:%S')"
    else
        echo "  chunk $k FAILED (exit $rc) - see $WORK_DIR/chunk_$k.log"
        return 1
    fi
}
export -f run_chunk
export NCHUNKS CHUNK TOTAL BASE_SEED WORK_DIR CHUNK_DIR TEMPLATE SESSION_FILE HAVE_TIME

# ---------------------------------------------------------------- bookkeeping
count_done() { find "$CHUNK_DIR" -name 'chunk_*.txt' | wc -l; }

START_EPOCH=$(date +%s.%N)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

# Append this session's timing to the CSV log and timing_results.txt.
# Rates use only the trials finished in this session, so resumed runs still give a true trials/s.
log_run() {
    local status=$1
    local end_human elapsed done_trials spt tps hms
    end_human=$(date '+%Y-%m-%d %H:%M:%S')
    elapsed=$(awk -v s="$START_EPOCH" -v e="$(date +%s.%N)" 'BEGIN { printf "%.1f", e - s }')
    done_trials=$(awk '{ s += $1 } END { print s + 0 }' "$SESSION_FILE")
    spt=$(awk -v t="$elapsed" -v n="$done_trials" 'BEGIN { printf "%.4f", (n > 0 ? t / n : 0) }')
    tps=$(awk -v t="$elapsed" -v n="$done_trials" 'BEGIN { printf "%.2f", (t > 0 ? n / t : 0) }')
    hms=$(awk -v t="$elapsed" 'BEGIN { t = int(t); printf "%dh %02dm %02ds", t/3600, (t%3600)/60, t%60 }')

    [[ -f $LOG_CSV ]] || echo "run_id,host,cpu,workers,trials,base_seed,start,end,elapsed_s,s_per_trial,trials_per_s,status" > "$LOG_CSV"
    echo "$RUN_ID,$HOST,\"$CPU\",$WORKERS,$done_trials,$BASE_SEED,$START_HUMAN,$end_human,$elapsed,$spt,$tps,$status" >> "$LOG_CSV"

    printf '%s on %s: %d trials this session, %d workers, %s elapsed (%s s/trial, %s trials/s) [%s]\n' \
        "$RUN_ID" "$HOST" "$done_trials" "$WORKERS" "$hms" "$spt" "$tps" "$status" \
        | tee -a timing_results.txt "$RUN_DIR/run_info.txt"
    echo "Progress: $(count_done) of $NCHUNKS chunks done. Finished: $end_human" | tee -a "$RUN_DIR/run_info.txt"
}

# Kill a process and everything below it (xargs -> bash -> time -> ngspice).
kill_tree() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
    kill -TERM "$1" 2>/dev/null || true
}

# Ctrl-C / SIGTERM (e.g. Spot preemption notice): stop all workers, then log what finished.
# Completed chunks are already safe in chunks/; resume with RESUME=$RUN_ID.
XARGS_PID=
on_interrupt() {
    trap - INT TERM
    echo "Stopping workers..."
    [[ -n $XARGS_PID ]] && kill_tree "$XARGS_PID"
    log_run interrupted
    echo "Resume with:  RESUME=$RUN_ID ./launch_parallel.sh $WORKERS"
    exit 1
}
trap on_interrupt INT TERM

# ---------------------------------------------------------------- run the pending chunks
mapfile -t PENDING < <(for ((k = 0; k < NCHUNKS; k++)); do
    [[ -f $CHUNK_DIR/chunk_$k.txt ]] || echo "$k"
done)

{
    echo "== Session on $HOST ($CPU), $MODE, $START_HUMAN"
    echo "Run $RUN_ID: $TOTAL trials in $NCHUNKS chunks of $CHUNK, base seed $BASE_SEED"
    echo "$(( NCHUNKS - ${#PENDING[@]} )) chunks already done, ${#PENDING[@]} to go, $WORKERS workers"
} | tee -a "$RUN_DIR/run_info.txt"

fail=0
if (( ${#PENDING[@]} > 0 )); then
    # xargs hands the next chunk to whichever worker frees up first, so fast and slow cores
    # (P/E cores, SMT siblings) all stay busy until the end.
    # Run in the background and `wait`: bash only runs a trap between commands, and `wait` is the
    # one place a signal interrupts immediately. A foreground xargs would delay Ctrl-C/SIGTERM
    # handling until every in-flight chunk finished.
    xargs -P "$WORKERS" -I{} bash -c 'run_chunk "$1"' _ {} < <(printf '%s\n' "${PENDING[@]}") &
    XARGS_PID=$!
    wait "$XARGS_PID" || fail=1
    XARGS_PID=
fi

# Per-chunk timing summary for this session.
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
# Header from chunk 0, data rows from every chunk in order.
# Note: column 1 is a duplicate of tplh_cout_delays (wrdata uses the first vector as the scale
# column because the plot has no scale vector). Ignore it in analysis.
if (( DONE == NCHUNKS )); then
    MERGED=$RUN_DIR/full_adder_mc_merged.txt
    head -n 1 "$CHUNK_DIR/chunk_0.txt" > "$MERGED"
    for ((k = 0; k < NCHUNKS; k++)); do
        tail -n +2 "$CHUNK_DIR/chunk_$k.txt" >> "$MERGED"
    done
    rows=$(( $(wc -l < "$MERGED") - 1 ))
    echo "Merged $rows of $TOTAL trials into $MERGED" | tee -a "$RUN_DIR/run_info.txt"
    [[ $rows -eq $TOTAL ]] || echo "WARNING: row count doesn't match - check the chunk logs"
else
    echo "Not merged yet: $(( NCHUNKS - DONE )) chunks missing."
    echo "Resume with:  RESUME=$RUN_ID ./launch_parallel.sh $WORKERS"
fi

exit $fail
