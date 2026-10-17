#!/bin/bash
# Shows the seed, chunk progress, and last log lines from every sim VM, in parallel.
SIM_SUBDIR="mux_mc"   # must match SIM_SUBDIR in launch_all.sh
SIM_DIR=/opt/F26_DSD_CSA_Midterm/$SIM_SUBDIR

gcloud compute instances list --filter="labels.role=sim" \
  --format="value(name,zone,status)" | while read -r name zone status; do
  (
    if [ "$status" != "RUNNING" ]; then
      printf '===== %s (%s) =====\n\n' "$name" "$status"
      exit 0
    fi
    out=$(gcloud compute ssh "$name" --zone="$zone" --quiet --command="
      cd $SIM_DIR 2>/dev/null || { echo 'Not set up yet (startup script still running?)'; exit 0; }
      cat vm_run_info.txt 2>/dev/null | tail -n 1
      for d in runs/*/; do
        [ -f \$d/params ] || continue
        . \$d/params
        n=\$(( (TOTAL + CHUNK - 1) / CHUNK ))
        done_=\$(ls \$d/chunks 2>/dev/null | wc -l)
        state=running; ls \$d/*_merged.txt >/dev/null 2>&1 && state=FINISHED
        echo \"run \$(basename \$d): \$done_/\$n chunks [\$state]\"
      done
      tail -n 2 sim.log 2>/dev/null
    " 2>&1)
    printf '===== %s =====\n%s\n\n' "$name" "$out"
  ) &
done
wait
