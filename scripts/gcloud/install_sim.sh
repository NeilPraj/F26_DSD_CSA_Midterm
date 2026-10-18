VMS="us-east4-a:mc-east16 us-east4-a:mc-east8 us-central1-a:mc-central16 us-central1-a:mc-central8"

for vm in $VMS; do
  zone=${vm%%:*}; name=${vm##*:}
  gcloud compute ssh $name --zone=$zone --command="
    sudo apt-get update &&
    sudo apt-get install -y htop tmux curl git ngspice time ncurses-term &&
    curl -fsSL -o /tmp/fastfetch.deb https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb &&
    sudo apt-get install -y /tmp/fastfetch.deb &&
    if [ -d ~/F26_DSD_CSA_Midterm/.git ]; then
      git -C ~/F26_DSD_CSA_Midterm pull
    else
      git clone https://github.com/NeilPraj/F26_DSD_CSA_Midterm.git
    fi
  " 2>&1 | sed "s/^/[$name] /" &
done
wait
