#!/bin/bash
# GCP startup script: runs as root automatically every time the VM boots.
#
# First boot:  installs deps, clones the repo, picks a seed, starts a new run.
# Later boots: if the run didn't finish (reboot, host maintenance, Spot
#              preemption), resumes it with RESUME=<run_id> instead of
#              starting over. If it already finished, does nothing.
#
# The sim runs in a detached tmux session "sim", in the repo folder named by
# the "sim-dir" metadata (e.g. /opt/F26_DSD_CSA_Midterm/mux_mc).
# Attach with:  sudo tmux attach -t sim
set -euo pipefail

meta() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}
REPO_URL="$(meta repo-url)"
NUM_TRIALS="$(meta num-trials)"
VM_INDEX="$(meta vm-index)"
SIM_SUBDIR="$(meta sim-dir)"   # e.g. mux_mc

REPO_DIR=/opt/F26_DSD_CSA_Midterm
SIM_DIR="$REPO_DIR/$SIM_SUBDIR"
NUM_WORKERS="$(nproc)"

# 1. Dependencies (skipped quickly on later boots)
if ! command -v ngspice >/dev/null || ! command -v tmux >/dev/null || [ ! -x /usr/bin/time ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ngspice tmux git time
fi

# 2. Code. Cloned once and never pulled again, so a resumed run uses the
#    same netlist it started with.
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone "$REPO_URL" "$REPO_DIR"
fi
if [ ! -f "$SIM_DIR/launch_parallel.sh" ]; then
  echo "ERROR: $SIM_DIR/launch_parallel.sh not found. Is it committed and pushed to GitHub?"
  exit 1
fi
cd "$SIM_DIR"
chmod +x launch_parallel.sh

# Already running (e.g. the script was re-run by hand)? Leave it alone.
if tmux has-session -t sim 2>/dev/null; then
  echo "tmux session 'sim' already exists; nothing to do."
  exit 0
fi

# 3. Unfinished run from an earlier boot? Resume it.
UNFINISHED=""
for params in runs/*/params; do
  [ -f "$params" ] || continue
  run_dir="$(dirname "$params")"
  compgen -G "$run_dir/*_merged.txt" >/dev/null || UNFINISHED="$(basename "$run_dir")"
done

if [ -n "$UNFINISHED" ]; then
  echo "Resuming run $UNFINISHED with $NUM_WORKERS workers"
  CMD="RESUME=$UNFINISHED ./launch_parallel.sh $NUM_WORKERS"
elif compgen -G "runs/*/*_merged.txt" >/dev/null; then
  echo "Run already finished on this VM; not starting another."
  exit 0
else
  # 4. New run. Each VM gets its own 10M-wide seed block so no two VMs can
  #    ever reuse a seed (chunk k uses BASE_SEED + k), with a random offset
  #    inside the block.
  BASE_SEED=$(( VM_INDEX * 10000000 + $(shuf -i 1-5000000 -n 1) ))
  echo "host=$(uname -n) vm_index=$VM_INDEX base_seed=$BASE_SEED trials=$NUM_TRIALS workers=$NUM_WORKERS" \
    | tee -a "$SIM_DIR/vm_run_info.txt"
  CMD="BASE_SEED=$BASE_SEED ./launch_parallel.sh $NUM_TRIALS $NUM_WORKERS"
fi

# 5. Start it in tmux, opened in the sim folder. The shell stays open after
#    the sim exits so you can still read the output when you attach.
tmux new-session -d -s sim -c "$SIM_DIR" \
  "$CMD 2>&1 | tee -a sim.log; echo; echo '[sim finished - shell left open]'; exec bash"
