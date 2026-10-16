#!/bin/bash
# launch_parallel.sh - split a Monte Carlo run across several single-threaded ngspice copies.
#
# Usage:  ./launch_parallel.sh <total_trials> [workers]
#   e.g.  ./launch_parallel.sh 100000 8
#
# Each worker gets its own copy of the netlist with:
#   - its share of the trials   (let mc_runs = N)
#   - its own random seed       (set rndseed=S)
#   - its own output file       (full_adder_mc_w<i>.txt)
# When all workers finish, the outputs are merged and everything is moved into runs/<timestamp>/.
#
# Timing is recorded in three places:
#   runs/<timestamp>/run_info.txt  - seeds, start/end times, per-worker time and peak memory
#   runs/timing_log.csv            - one row per run (host, CPU, trials, s/trial, ...) for planning runs
#   timing_results.txt             - one human-readable summary line per run

set -euo pipefail
cd "$(dirname "$0")"

TOTAL=${1:?usage: $0 <total_trials> [workers]}
WORKERS=${2:-8}
# Random base seed per run (fits in a signed 32-bit int). Odds of two runs overlapping are ~1 in 100 million,
# so every machine can use this same script unmodified. Recorded in run_info.txt for reproducibility.
# Override to reproduce a run: BASE_SEED=1234 ./launch_parallel.sh ...
BASE_SEED=${BASE_SEED:-$(( $(od -An -N4 -tu4 /dev/urandom) % 2000000000 ))}
SRC=full_adder_mc.sp
RUN_ID=$(date +%Y%m%d_%H%M%S)
RUN_DIR=runs/$RUN_ID
LOG_CSV=runs/timing_log.csv
HOST=$(uname -n)   # coreutils; `hostname` isn't installed by default on Arch
CPU=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)
CPU=${CPU:-unknown}

# GNU time gives per-worker elapsed/CPU/memory. If it's missing:
#   Ubuntu: sudo apt install time      Arch: sudo pacman -S time
if [[ -x /usr/bin/time ]]; then
    HAVE_TIME=1
else
    HAVE_TIME=0
    echo "Note: /usr/bin/time not found - skipping per-worker stats (apt install time / pacman -S time)"
fi

# Single-threaded ngspice: each worker should use exactly one core.
if grep -q '^set num_threads' .spiceinit 2>/dev/null; then
    sed -i 's/^set num_threads.*/set num_threads=1/' .spiceinit
else
    echo 'set num_threads=1' >> .spiceinit
fi
export OMP_NUM_THREADS=1

mkdir -p "$RUN_DIR"
START_EPOCH=$(date +%s.%N)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

# Append this run's overall timing to the CSV log and timing_results.txt.
log_run() {
    local status=$1
    local end_human elapsed spt tps hms
    end_human=$(date '+%Y-%m-%d %H:%M:%S')
    elapsed=$(awk -v s="$START_EPOCH" -v e="$(date +%s.%N)" 'BEGIN { printf "%.1f", e - s }')
    spt=$(awk -v t="$elapsed" -v n="$TOTAL" 'BEGIN { printf "%.4f", t / n }')
    tps=$(awk -v t="$elapsed" -v n="$TOTAL" 'BEGIN { printf "%.2f", (t > 0 ? n / t : 0) }')
    hms=$(awk -v t="$elapsed" 'BEGIN { t = int(t); printf "%dh %02dm %02ds", t/3600, (t%3600)/60, t%60 }')

    [[ -f $LOG_CSV ]] || echo "run_id,host,cpu,workers,trials,base_seed,start,end,elapsed_s,s_per_trial,trials_per_s,status" > "$LOG_CSV"
    echo "$RUN_ID,$HOST,\"$CPU\",$WORKERS,$TOTAL,$BASE_SEED,$START_HUMAN,$end_human,$elapsed,$spt,$tps,$status" >> "$LOG_CSV"

    printf '%s on %s: %d trials, %d workers, %s elapsed (%s s/trial, %s trials/s) [%s]\n' \
        "$RUN_ID" "$HOST" "$TOTAL" "$WORKERS" "$hms" "$spt" "$tps" "$status" \
        | tee -a timing_results.txt "$RUN_DIR/run_info.txt"
    echo "Finished: $end_human" >> "$RUN_DIR/run_info.txt"
}

# If this script is interrupted (Ctrl-C), take the workers down with it and log the partial run.
trap 'echo "Stopping workers..."; kill $(jobs -p) 2>/dev/null; log_run interrupted; exit 1' INT TERM

{
    echo "Run $RUN_ID on $HOST ($CPU)"
    echo "$TOTAL trials across $WORKERS workers, base seed $BASE_SEED"
    echo "Started: $START_HUMAN"
} | tee "$RUN_DIR/run_info.txt"

pids=()
for ((i = 0; i < WORKERS; i++)); do
    # Spread the remainder over the first few workers so the counts add up to TOTAL exactly.
    n=$(( TOTAL / WORKERS + (i < TOTAL % WORKERS ? 1 : 0) ))
    seed=$(( BASE_SEED + i ))
    sp=full_adder_mc_w$i.sp   # must live next to full_adder_mc.sp so ../cell_lib.sp still resolves

    sed -e "s/^let mc_runs = .*/let mc_runs = $n/" \
        -e "s/wrdata full_adder_mc\.txt/wrdata full_adder_mc_w$i.txt/" \
        -e "/^\.control/a set rndseed=$seed" \
        "$SRC" > "$sp"

    echo "  worker $i: $n trials, seed $seed" | tee -a "$RUN_DIR/run_info.txt"

    # Same invocation as launch.sh. stdin from /dev/null so a background ngspice never waits on the terminal.
    # GNU time format: elapsed s, user s, system s, peak memory KB
    if (( HAVE_TIME )); then
        /usr/bin/time -f '%e %U %S %M' -o "worker_$i.time" \
            ngspice "$sp" < /dev/null > "worker_$i.log" 2>&1 &
    else
        ngspice "$sp" < /dev/null > "worker_$i.log" 2>&1 &
    fi
    pids+=($!)
done

echo "All $WORKERS workers started at $START_HUMAN. Waiting..."

fail=0
for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
        echo "  worker $i finished at $(date '+%H:%M:%S')"
    else
        echo "  worker $i FAILED - see $RUN_DIR/worker_$i.log"
        fail=1
    fi
done

# Per-worker timing. tail -n 1 skips the "Command exited with..." line GNU time adds on failure.
if (( HAVE_TIME )); then
    echo "Per-worker timing:" | tee -a "$RUN_DIR/run_info.txt"
    for ((i = 0; i < WORKERS; i++)); do
        [[ -f worker_$i.time ]] || continue
        tail -n 1 "worker_$i.time" | awk -v i="$i" \
            '{ printf "  worker %d: %8.1f s elapsed, %8.1f s user, %7.1f s sys, %6.0f MB peak\n", i, $1, $2, $3, $4 / 1024 }' \
            | tee -a "$RUN_DIR/run_info.txt"
    done
fi

if (( fail )); then log_run failed; else log_run ok; fi

# Merge: header row from the first file, data rows from all of them.
# Note: column 1 is a duplicate of tplh_cout_delays (wrdata uses the first vector as the scale
# column because the plot has no scale vector). Ignore it in analysis.
MERGED=$RUN_DIR/full_adder_mc_merged.txt
if [[ -f full_adder_mc_w0.txt ]]; then
    head -n 1 full_adder_mc_w0.txt > "$MERGED"
    for ((i = 0; i < WORKERS; i++)); do
        [[ -f full_adder_mc_w$i.txt ]] && tail -n +2 "full_adder_mc_w$i.txt" >> "$MERGED"
    done
    rows=$(( $(wc -l < "$MERGED") - 1 ))
    echo "Merged $rows of $TOTAL trials into $MERGED"
    [[ $rows -eq $TOTAL ]] || echo "WARNING: row count doesn't match - check the worker logs"
fi

# Tidy up: move this run's generated netlists, outputs, logs and timings out of the working directory.
mv full_adder_mc_w*.sp full_adder_mc_w*.txt worker_*.log worker_*.time "$RUN_DIR"/ 2>/dev/null || true

exit $fail
