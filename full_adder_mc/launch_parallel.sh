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

# Single-threaded ngspice: each worker should use exactly one core.
if grep -q '^set num_threads' .spiceinit 2>/dev/null; then
    sed -i 's/^set num_threads.*/set num_threads=1/' .spiceinit
else
    echo 'set num_threads=1' >> .spiceinit
fi
export OMP_NUM_THREADS=1

# If this script is interrupted (Ctrl-C), take the workers down with it.
trap 'echo "Stopping workers..."; kill $(jobs -p) 2>/dev/null; exit 1' INT TERM

mkdir -p "$RUN_DIR"
echo "Run $RUN_ID: $TOTAL trials across $WORKERS workers, base seed $BASE_SEED" | tee "$RUN_DIR/run_info.txt"

pids=()
start=$(date +%s)

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
    ngspice "$sp" < /dev/null > "worker_$i.log" 2>&1 &
    pids+=($!)
done

echo "All $WORKERS workers started. Waiting..."

fail=0
for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
        echo "  worker $i finished"
    else
        echo "  worker $i FAILED - see $RUN_DIR/worker_$i.log"
        fail=1
    fi
done

elapsed=$(( $(date +%s) - start ))
printf 'parallel run %s: %d trials, %d workers, %dh %02dm %02ds elapsed\n' \
    "$RUN_ID" "$TOTAL" "$WORKERS" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)) \
    | tee -a timing_results.txt "$RUN_DIR/run_info.txt"

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

# Tidy up: move this run's generated netlists, outputs and logs out of the working directory.
mv full_adder_mc_w*.sp full_adder_mc_w*.txt worker_*.log "$RUN_DIR"/ 2>/dev/null || true

exit $fail
