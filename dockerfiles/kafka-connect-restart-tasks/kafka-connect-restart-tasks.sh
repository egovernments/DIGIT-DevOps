#!/bin/sh
HOSTS=${KAFKA_CONNECT_HOSTS:-localhost:8083}

for host in $(echo $HOSTS | sed "s/,/ /g")
do
  # List current connectors and status
  curl -s "http://$host/connectors"| jq '.[]'| sed 's/"//g' | xargs -I{connector_name} curl -s "http://$host/connectors/"{connector_name}"/status"| jq -c -M '[.name,.connector.state,.tasks[].state]|join(":|:")'| column -s : -t| sed 's/\"//g'| sort

  # Restart any connector tasks that are FAILED
  curl -s "http://$host/connectors" | \
    jq '.[]' | \
    sed 's/"//g' | \
    xargs -I{connector_name} curl -s "http://$host/connectors/"{connector_name}"/status" | \
    jq -c -M '[select(.tasks[].state=="FAILED") | .name,"§±§",.tasks[].id]' | \
    grep -v "\[\]"| \
    sed -e 's/^\[\"//g'| sed -e 's/\",\"§±§\",/\/tasks\//g'|sed -e 's/\]$//g'| \
    xargs -I{connector_and_task} curl -v -X POST "http://$host/connectors/"{connector_and_task}"/restart"
done
