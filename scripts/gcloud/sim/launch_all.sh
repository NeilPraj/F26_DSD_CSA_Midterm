#!/bin/bash
# Creates all sim VMs in parallel on C4D-highcpu (AMD Turin). Each one runs
# sim-startup.sh on boot, so there is nothing to SSH into to start the runs.
#
# Usage: ./launch_all.sh <trials_per_vm>
#   e.g. ./launch_all.sh 200000
set -euo pipefail

NUM_TRIALS="${1:?usage: ./launch_all.sh <trials_per_vm>}"
REPO_URL="https://github.com/NeilPraj/F26_DSD_CSA_Midterm.git"
SIM_SUBDIR="mux_mc"   # folder in the repo with launch_parallel.sh (was full_adder_mc)

# One 16 + one 8 vCPU VM per zone = 24 per region, 48 total.
# C4D isn't in every zone - the check below stops early if a zone lacks it.
ZONES=(us-central1-a us-east4-a)
SIZES=(16 8)

# Spot VMs, auto-stopped after 12 hours of running time.
# Both preemption and hitting the 12h limit STOP the VM: billing for vCPUs
# ends, but the disk and finished chunks are kept so you can still collect.
# Run ./restart_stopped.sh to bring a VM back; the startup script resumes
# the run, so you only lose the chunks that were in flight.
MAX_RUN=12h
SPOT_FLAGS=(--provisioning-model=SPOT --instance-termination-action=STOP
            --max-run-duration="$MAX_RUN")

# Preflight: make sure every zone offers every machine type we need.
for zone in "${ZONES[@]}"; do
  for size in "${SIZES[@]}"; do
    type="c4d-highcpu-${size}"
    if ! gcloud compute machine-types describe "$type" --zone="$zone" >/dev/null 2>&1; then
      echo "ERROR: $type is not available in $zone."
      echo "Find zones that have it with:"
      echo "  gcloud compute machine-types list --filter=\"name=$type\" --format=\"value(zone)\""
      exit 1
    fi
  done
done

idx=0
for zone in "${ZONES[@]}"; do
  for size in "${SIZES[@]}"; do
    name="sim-${zone}-${size}"
    echo "Creating $name (vm-index $idx)"
    gcloud compute instances create "$name" \
      --zone="$zone" \
      --machine-type="c4d-highcpu-${size}" \
      --boot-disk-type=hyperdisk-balanced \
      --boot-disk-size=20GB \
      --image-family=debian-12 --image-project=debian-cloud \
      --metadata="repo-url=${REPO_URL},num-trials=${NUM_TRIALS},vm-index=${idx},sim-dir=${SIM_SUBDIR}" \
      --metadata-from-file=startup-script=sim-startup.sh \
      --labels=role=sim \
      "${SPOT_FLAGS[@]}" &
    idx=$((idx + 1))
  done
done
wait
echo "All VMs created. Sims start a minute or two after boot."
echo "Check on them with ./status_all.sh"
