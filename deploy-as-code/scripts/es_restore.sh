#!/bin/bash

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#
#    This scrit will restore backup of elasticsearch data and mapping taken using es-backup.sh
#    This script should be run inside playground pod.
#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


cluster_url="http://es-client.es-cluster:9200"

backup_dir="/opt/eGov/es-data"

env="dev"

command -v elasticdump >/dev/null 2>&1 ||  npm install elasticdump -g

cmd=$(which elasticdump)

if [[ ! -d $backup_dir ]]; then echo "Backup directory not found. Please try again." && exit 1; fi
if [[ ! -f $backup_dir/indices_list.txt ]]; then echo "Indexes list file not found. Please try again." && exit 1; fi

while read -r line
do
    echo "curl -XDELETE $cluster_url/$line"
    echo "curl -XPUT $cluster_url/$line"
    echo "$cmd --input=$backup_dir/$line-mapping.json --output=$cluster_url/$line --type=mapping"
    $cmd --input=$backup_dir/$line-mapping.json --output=$cluster_url/$line --type=mapping
    echo "$cmd --input=$backup_dir/$line-data.json --output=$cluster_url/$line --type=data"
    $cmd --input=$backup_dir/$line-data.json --output=$cluster_url/$line --type=data
done < $backup_dir/indices_list.txt
