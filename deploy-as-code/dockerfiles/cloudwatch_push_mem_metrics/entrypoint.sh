#!/bin/sh

INSTANCE-ID=$(`curl -XGET  http://169.254.169.254/latest/meta-data/instance-id`)

  aws cloudwatch put-metric-alarm --alarm-name "$NODE_ENV""-High-Disk-Utilization-""$INSTANCE-ID" \
  --metric-name DiskSpaceUtilization --namespace System/Linux \
  --statistic Average --period 300 --threshold 70 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$instance-id Name=Filesystem,Value=rootfs Name=MountPath,Value=/ \
  --evaluation-periods 1 --alarm-actions $ARN

  aws cloudwatch put-metric-alarm --alarm-name "$NODE_ENV""-High-CPU-Utilization-""$INSTANCE-ID" \
  --metric-name CPUUtilization --namespace System/Linux \
  --statistic Average --period 300 --threshold 70 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$instance-id   --evaluation-periods 1 --alarm-actions $ARN

  aws cloudwatch put-metric-alarm --alarm-name "$NODE_ENV""-High-Memory-Utilization-""$INSTANCE-ID" \
  --metric-name MemoryUtilization --namespace System/Linux \
  --statistic Average --period 300 --threshold 70 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$instance-id   --evaluation-periods 1 --alarm-actions $ARN

while true; do
  ./mon-put-instance-data.pl --mem-util  --mem-avail \
  --disk-space-util --disk-path=/rootfs \
  --swap-util --aggregated\
  --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY

  sleep 60
done

#while true; do
#  ./mon-put-instance-data.pl --mem-util  --mem-avail \
#  --disk-space-util --disk-path=/rootfs \
#  --swap-util --aggregated\
#  --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY
#  sleep 60
#done
