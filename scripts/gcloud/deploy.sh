#!/bin/bash
# deploy.sh - clone the repo on every RUNNING VM and start the mux Monte Carlo
#
# Trials (pick one):
#   (none)              per-VM trials from the TRIALS_BY_CORES table in this file
#   -c 8=5000,16=10000  override table entries for this deploy
#   -t 100000           split 100000 trials across the VMs by core count
#   -p 25000            run 25000 trials on every VM
#
# Other options:
#   -k    keep VMs running after their sim finishes (default: each VM shuts itself down)
#   -a    keep the previous VM list (for adding VMs to a batch that's already running)
#   -h    show this help
set -euo pipefail

# ---- trials per VM, by core count (edit these) ----------------------------------
declare -A TRIALS_BY_CORES=(
  [8]=10000
  [16]=20000
  [48]=60000
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_LIST="$SCRIPT_DIR/deployed_vms.txt"
REPO=https://github.com/NeilPraj/F26_DSD_CSA_Midterm.git

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit "${1:-1}"; }

MODE=cores TOTAL= PER_VM= APPEND= KEEP=stop
while getopts "t:p:c:akh" opt; do
  case $opt in
    t) MODE=total; TOTAL=$OPTARG ;;
    p) MODE=per_vm; PER_VM=$OPTARG ;;
    c) IFS=, read -ra pairs <<< "$OPTARG"
       for p in "${pairs[@]}"; do TRIALS_BY_CORES[${p%%=*}]=${p#*=}; done ;;
    a) APPEND=1 ;;
    k) KEEP=keep ;;
    h) usage 0 ;;
    *) usage ;;
  esac
done

# A passphrase-protected key needs ssh-agent, or the parallel SSH prompts collide
KEY=~/.ssh/google_compute_engine
if [[ -f $KEY ]] && ! ssh-keygen -y -P "" -f "$KEY" > /dev/null 2>&1 && ! ssh-add -l > /dev/null 2>&1; then
  echo "Your SSH key has a passphrase. Load it first:"
  echo '  eval "$(ssh-agent -s)" && ssh-add ~/.ssh/google_compute_engine'
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/remote_setup.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
REPO=$1
TRIALS=$2
SEED=$3
KEEP=$4
WORKERS=$(nproc)
DIR="$HOME/F26_DSD_CSA_Midterm"
RUNS="$DIR/mux_mc/runs"

if systemctl is-active --quiet mc-sim; then
  echo "mc-sim is already running here, skipping"
  exit 0
fi

APT="sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -qq"
$APT update
$APT install -y git ngspice python3 time > /dev/null

if [[ -d $DIR/.git ]]; then
  git -C "$DIR" pull --ff-only -q
else
  git clone -q "$REPO" "$DIR"
fi

[[ -f $DIR/mux_mc/mux_mc.sp ]] || { echo "No mux_mc/mux_mc.sp in the repo"; exit 1; }

# Move any earlier runs aside so collect.sh only picks up this deploy's results
if [[ -d $RUNS && -n $(ls -A "$RUNS") ]]; then
  mkdir -p "$DIR/mux_mc/runs_archive"
  mv "$RUNS" "$DIR/mux_mc/runs_archive/$(date +%Y%m%d_%H%M%S)"
  echo "Moved previous runs to mux_mc/runs_archive/"
fi

EXTRA=()
[[ $KEEP == keep ]] && EXTRA=(--no-stop-vm)

sudo systemctl reset-failed mc-sim 2>/dev/null || true
sudo systemd-run --unit=mc-sim --uid="$USER" \
  --working-directory="$DIR/mux_mc" --setenv=PYTHONUNBUFFERED=1 \
  python3 "$DIR/mux_mc/launch_parallel.py" run "$TRIALS" -w "$WORKERS" --seed "$SEED" --plain "${EXTRA[@]}"

echo "Started: $TRIALS trials, $WORKERS workers (nproc), seed $SEED," \
     "$([[ $KEEP == keep ]] && echo "VM stays on when done" || echo "VM stops when done")"
EOF

mapfile -t VMS < <(gcloud compute instances list --filter="status=RUNNING" \
  --format="value(name,zone.basename(),machineType.basename())")
(( ${#VMS[@]} )) || { echo "No running VMs - start them with ./vms.sh start"; exit 1; }

total_cores=0
for vm in "${VMS[@]}"; do
  read -r name zone mt <<< "$vm"
  cores=${mt##*-}
  total_cores=$(( total_cores + cores ))
  if [[ $MODE == cores && -z ${TRIALS_BY_CORES[$cores]:-} ]]; then
    echo "$name has $cores cores, but TRIALS_BY_CORES has no entry for $cores - add one or use -c $cores=N"
    exit 1
  fi
done

# The VM list: start fresh, or with -a keep the entries for VMs not in this deploy
if [[ $APPEND && -f $VM_LIST ]]; then
  awk 'NR == FNR { here[$1]; next } !($1 in here)' \
    <(printf '%s\n' "${VMS[@]}") "$VM_LIST" > "$VM_LIST.tmp"
  mv "$VM_LIST.tmp" "$VM_LIST"
else
  : > "$VM_LIST"
fi

base_seed=$(( RANDOM * 32768 + RANDOM ))
assigned=0
i=0

for vm in "${VMS[@]}"; do
  read -r name zone mt <<< "$vm"
  cores=${mt##*-}
  case $MODE in
    cores)  trials=${TRIALS_BY_CORES[$cores]} ;;
    per_vm) trials=$PER_VM ;;
    total)  if (( i == ${#VMS[@]} - 1 )); then
              trials=$(( TOTAL - assigned ))
            else
              trials=$(( TOTAL * cores / total_cores ))
            fi ;;
  esac
  assigned=$(( assigned + trials ))
  seed=$(( base_seed + i * 1000000 ))
  echo "$name $zone $cores $trials $seed" >> "$VM_LIST"
  echo "$name ($zone, $cores cores -> $cores workers): $trials trials, seed $seed"

  gcloud compute ssh "$name" --zone="$zone" --quiet --strict-host-key-checking=no \
    --command="bash -s -- $REPO $trials $seed $KEEP" < "$tmp/remote_setup.sh" 2>&1 \
    | sed "s/^/[$name] /" &
  i=$(( i + 1 ))
done

wait
echo "Deployed $assigned trials. VM list saved to $VM_LIST"
