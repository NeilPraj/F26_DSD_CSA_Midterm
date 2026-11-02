#!/bin/bash
# Pull every deployed VM's runs into <repo>/CSA_runs/gc_<region>_<cores>/
# Starts stopped VMs to copy from them, stops them again, and reports which
# VMs have finished, are still running, or stopped before finishing.
#   ./collect.sh              write to <repo>/CSA_runs
#   ./collect.sh some/folder  write somewhere else

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_LIST="$SCRIPT_DIR/deployed_vms.txt"
OUT=${1:-$REPO_ROOT/CSA_runs}

# A passphrase-protected key needs ssh-agent, or the parallel SSH prompts collide
KEY=~/.ssh/google_compute_engine
if [[ -f $KEY ]] && ! ssh-keygen -y -P "" -f "$KEY" > /dev/null 2>&1 && ! ssh-add -l > /dev/null 2>&1; then
  echo "Your SSH key has a passphrase. Load it first:"
  echo '  eval "$(ssh-agent -s)" && ssh-add ~/.ssh/google_compute_engine'
  exit 1
fi

[[ -f $VM_LIST ]] || { echo "No $VM_LIST - run deploy.sh first"; exit 1; }
mkdir -p "$OUT"
status_dir=$(mktemp -d)
trap 'rm -rf "$status_dir"' EXIT

# Folder names: us-east1-b + 16 cores -> gc_east1_16 (a suffix is added if two would clash)
declare -A seen
jobs_list=()
while read -r name zone cores _; do
  region=${zone%-*}
  dir="gc_${region#us-}_${cores}"
  seen[$dir]=$(( ${seen[$dir]:-0} + 1 ))
  (( ${seen[$dir]} > 1 )) && dir="${dir}_${seen[$dir]}"
  jobs_list+=("$name $zone $dir")
done < "$VM_LIST"

for job in "${jobs_list[@]}"; do
  read -r name zone dir <<< "$job"
  (
    set -o pipefail
    SSH=(gcloud compute ssh "$name" --zone="$zone" --quiet --strict-host-key-checking=no)

    started= was_running=1
    if [[ $(gcloud compute instances describe "$name" --zone="$zone" --format="value(status)") != RUNNING ]]; then
      echo "starting VM to copy results"
      if ! gcloud compute instances start "$name" --zone="$zone" --quiet; then
        echo "$name|$dir|COULDN'T START VM (stockout?) - nothing copied" > "$status_dir/$dir"
        exit 1
      fi
      started=1
      was_running=
    fi

    ok=
    for try in {1..10}; do
      rm -rf "$OUT/$dir" && mkdir -p "$OUT/$dir"
      # Stream runs/ as a tar archive, skipping the per-chunk scratch folders (work/)
      if "${SSH[@]}" --command="tar -C ~/F26_DSD_CSA_Midterm/CSA_testing/runs --exclude=work -czf - ." < /dev/null \
         | tar -C "$OUT/$dir" -xzf -; then
        ok=1
        break
      fi
      sleep 10
    done

    # Work out how far this VM got
    if [[ ! $ok ]]; then
      status="FAILED to copy"
    else
      run=$(ls -d "$OUT/$dir"/*/ 2>/dev/null | sort | tail -n 1)
      if [[ -z $run ]]; then
        status="no run found on this VM"
      elif [[ -f $run/carry_select_mc_merged.txt ]]; then
        status="finished"
      else
        total=$(sed -n 's/^TOTAL=//p' "$run/params")
        chunk=$(sed -n 's/^CHUNK=//p' "$run/params")
        n_chunks=$(( (total + chunk - 1) / chunk ))
        n_done=$(ls "$run/chunks" 2>/dev/null | grep -c '^chunk_.*\.txt$')
        if [[ $was_running ]] && "${SSH[@]}" --command="systemctl is-active --quiet mc-sim" < /dev/null; then
          status="still running ($n_done/$n_chunks chunks)"
        else
          status="STOPPED BEFORE FINISHING ($n_done/$n_chunks chunks) - needs a resume"
        fi
      fi
    fi

    [[ $started ]] && gcloud compute instances stop "$name" --zone="$zone" --quiet --async
    echo "$status"
    echo "$name|$dir|$status" > "$status_dir/$dir"
  ) 2>&1 | sed "s/^/[$name] /" &
done
wait

# ---- summary ---------------------------------------------------------------------
echo
echo "Summary:"
n_all=0 n_fin=0
for f in "$status_dir"/*; do
  IFS='|' read -r name dir status < "$f"
  printf '  %-14s %-14s %s\n' "$name" "$dir" "$status"
  n_all=$(( n_all + 1 ))
  [[ $status == finished ]] && n_fin=$(( n_fin + 1 ))
done
echo

merged=("$OUT"/*/*/carry_select_mc_merged.txt)
if [[ -f ${merged[0]} ]]; then
  awk 'FNR > 1 || NR == 1' "${merged[@]}" > "$OUT/total_carry_select_mc_merged.txt"
  echo "Combined ${#merged[@]} runs into $OUT/total_carry_select_mc_merged.txt" \
       "($(( $(wc -l < "$OUT/total_carry_select_mc_merged.txt") - 1 )) trials)"
else
  echo "No finished runs to combine yet"
fi
(( n_fin < n_all )) && echo "WARNING: only $n_fin of $n_all VMs are finished - the total is incomplete. Run collect again later."
