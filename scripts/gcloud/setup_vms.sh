#!/usr/bin/env bash
# setup-vms.sh - install packages on Google Cloud VMs over SSH.
#
# Usage:
#   ./setup-vms.sh                  # every RUNNING VM in the project
#   ./setup-vms.sh mc-cloud8        # just the VMs you name
#   ZONE=us-east4-b ./setup-vms.sh mc-cloud8   # named VMs in another zone

set -euo pipefail   # stop on errors, unset variables, and failed pipes

# Commands to run on each VM. -y answers apt's prompts, since nobody is there to.
REPO_URL="https://github.com/NeilPraj/F26_DSD_CSA_Midterm.git"
REPO_DIR="F26_DSD_CSA_Midterm"

SETUP_CMDS="
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch &&
sudo apt-get update &&
sudo apt-get install -y zsh fastfetch ngspice time git &&
export GIT_TERMINAL_PROMPT=0 &&
if [ -d ~/$REPO_DIR/.git ]; then
    git -C ~/$REPO_DIR pull --ff-only
else
    git clone $REPO_URL ~/$REPO_DIR
fi
"

# Build a list of "name zone" entries.
vms=()
if (( $# > 0 )); then
    for vm in "$@"; do
        vms+=("$vm ${ZONE:-us-east4-a}")
    done
else
    mapfile -t vms < <(gcloud compute instances list \
        --filter="status=RUNNING" \
        --format="value(name,zone.basename())")
fi

if (( ${#vms[@]} == 0 )); then
    echo "No running VMs found." >&2
    exit 1
fi

failed=()
for entry in "${vms[@]}"; do
    read -r vm zone <<< "$entry"
    echo "==> $vm ($zone)"
    # If one VM fails, note it and move on instead of aborting the whole script.
    if ! gcloud compute ssh "$vm" --zone="$zone" --command="$SETUP_CMDS"; then
        failed+=("$vm")
    fi
done

if (( ${#failed[@]} > 0 )); then
    echo "Failed on: ${failed[*]}" >&2
    exit 1
fi
echo "All done."
