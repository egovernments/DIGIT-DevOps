#!/bin/sh

if [ -z "$ES_PORT" ]; then
    export ES_PORT=9200
fi

if [ -z "$ES_HOST" ]; then
    export ES_HOST=es-client.es-cluster
fi

if [ -z "$DAYS" ]; then
    export DAYS=3
fi


sed -i 's/%ES_HOST%/'"$ES_HOST"'/' /.curator/curator.yml
sed -i 's/%ES_PORT%/'"$ES_PORT"'/' /.curator/curator.yml
sed -i 's/%DAYS%/'"$DAYS"'/' /.curator/delete_old_logs.yml

curator --config /.curator/curator.yml /.curator/delete_old_logs.yml
