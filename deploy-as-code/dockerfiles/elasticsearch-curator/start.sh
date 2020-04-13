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

if [ -z "$TARGET_ENV" ]; then
    export TARGET_ENV=default
fi


sed -i 's/%ES_HOST%/'"$ES_HOST"'/' /.curator/curator.yml
sed -i 's/%ES_PORT%/'"$ES_PORT"'/' /.curator/curator.yml
sed -i 's/%DAYS%/'"$DAYS"'/' /.curator/delete_old_logs.yml
sed -i 's/%TARGET_ENV%/'"$TARGET_ENV"'/' /.curator/delete_old_logs.yml

echo "/.curator/delete_old_logs.yml"
echo "****************************"
cat /.curator/delete_old_logs.yml
echo "****************************"

echo "/.curator/curator.yml"
echo "****************************"
cat /.curator/curator.yml
echo "****************************"

curator --config /.curator/curator.yml /.curator/delete_old_logs.yml
