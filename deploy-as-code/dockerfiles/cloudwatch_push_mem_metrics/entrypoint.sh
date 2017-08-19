#!/bin/sh
while true; do
  ./mon-put-instance-data.pl --mem-util --mem-used --mem-avail \
  --disk-space-avail --disk-space-used --disk-space-util --disk-path=/rootfs \
  --swap-util --swap-used \
  --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY
  sleep 60
done
