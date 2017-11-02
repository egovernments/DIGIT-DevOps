#!/bin/bash

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#
#    This scrit will take backup of elasticsearch data and mapping from es-cluster
#    This script should be run inside playground pod.
#    Backup data needs to be copied from playground pod since pods are immortal
#           and data may get deleted in case if pod gets restarted.
#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


cluster_url="http://es-client.es-cluster:9200"

backup_dir="/opt/eGov/es-data"

env="dev"

command -v elasticdump >/dev/null 2>&1 ||  npm install elasticdump -g

cmd=$(which elasticdump)

if [[ ! -d $backup_dir ]]; then mkdir -p $backup_dir; fi
if [[ -f $backup_dir/indices_list.txt ]]; then cat /dev/null >$backup_dir/indices_list.txt; fi

indices=$(curl -XGET $cluster_url/_cat/indices 2>/dev/null | awk '{print $3}')

for i in ${indices[@]}
do
  # if [[ $i != *logstash* ]]; then echo "$cmd --input=$cluster_url/$i --output=$backup_dir/$i-mapping.json --type=mapping" && echo "$cmd --input=$cluster_url/$i --output=$backup_dir/$i-data.json --type=data"; fi
  echo $i >> $backup_dir/indices_list.txt
  echo "$cmd --input=$cluster_url/$i --output=$backup_dir/$i-mapping.json --type=mapping"
  $cmd --input=$cluster_url/$i --output=$backup_dir/$i-mapping.json --type=mapping
  echo "$cmd --input=$cluster_url/$i --output=$backup_dir/$i-data.json --type=data"
  $cmd --input=$cluster_url/$i --output=$backup_dir/$i-data.json --type=data
done
