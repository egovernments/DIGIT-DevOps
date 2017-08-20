#!/bin/sh
while true; do
  ./mon-put-instance-data.pl --mem-util  --mem-avail \
  --disk-space-util --disk-path=/rootfs \
  --swap-util --aggregated\
  --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY
  sleep 60
done
