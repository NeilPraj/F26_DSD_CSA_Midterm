for zone in us-east4-a:east us-central1-a:central; do
  z=${zone%%:*}; tag=${zone##*:}
  for cores in 16 8; do
    gcloud compute instances create mc-${tag}${cores} \
      --zone=$z --machine-type=c4d-highcpu-${cores} \
      --image-family=debian-12 --image-project=debian-cloud \
      --boot-disk-type=hyperdisk-balanced --boot-disk-size=10GB \
      --max-run-duration=12h \
      --instance-termination-action=STOP
  done
done
