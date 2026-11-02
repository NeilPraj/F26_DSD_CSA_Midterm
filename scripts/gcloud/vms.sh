#!/bin/bash
# Start, stop or list every mc-* VM.
#   ./vms.sh start            start them all
#   ./vms.sh stop             stop them all
#   ./vms.sh status           list them
#   ./vms.sh start east5      only VMs whose name contains "east5"
set -uo pipefail

ACTION=${1:-}
MATCH=${2:-}
case $ACTION in start|stop|status) ;; *) sed -n '3,6p' "$0"; exit 1 ;; esac

FILTER="name~^mc-"
[[ -n $MATCH ]] && FILTER="$FILTER AND name~$MATCH"

if [[ $ACTION == status ]]; then
  gcloud compute instances list --filter="$FILTER"
  exit
fi

mapfile -t VMS < <(gcloud compute instances list --filter="$FILTER" \
  --format="value(name,zone.basename())")
(( ${#VMS[@]} )) || { echo "No matching VMs"; exit 1; }

for vm in "${VMS[@]}"; do
  read -r name zone <<< "$vm"
  (
    if out=$(gcloud compute instances "$ACTION" "$name" --zone="$zone" --quiet 2>&1); then
      echo "${ACTION} ok"
    elif [[ $out == *ZONE_RESOURCE_POOL_EXHAUSTED* || $out == *stockout* ]]; then
      echo "out of stock in $zone, try again later"
    else
      echo "$out"
    fi
  ) | sed "s/^/[$name] /" &
done
wait

echo
gcloud compute instances list --filter="$FILTER"
