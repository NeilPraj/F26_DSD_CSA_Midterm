#!/bin/bash
# Copies the merged results and timing logs from every sim VM into ./results/<vm>/.
SIM_SUBDIR="mux_mc"   # must match SIM_SUBDIR in launch_all.sh
SIM_DIR=/opt/F26_DSD_CSA_Midterm/$SIM_SUBDIR
mkdir -p results

gcloud compute instances list --filter="labels.role=sim AND status=RUNNING" \
  --format="value(name,zone)" | while read -r name zone; do
  (
    mkdir -p "results/$name"
    # Bundle just the useful files (skips the scratch work/ dirs).
    gcloud compute ssh "$name" --zone="$zone" --quiet --command="
      cd $SIM_DIR && tar czf /tmp/results.tgz \
        runs/*/*_merged.txt runs/*/params runs/*/run_info.txt \
        runs/timing_log.csv timing_results.txt vm_run_info.txt 2>/dev/null; true" \
    && gcloud compute scp --zone="$zone" --quiet "$name:/tmp/results.tgz" "results/$name/" \
    && tar xzf "results/$name/results.tgz" -C "results/$name" \
    && rm "results/$name/results.tgz" \
    && echo "Collected $name" || echo "Failed to collect $name"
  ) &
done
wait
echo "Done. Results are in ./results/"
