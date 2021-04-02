#!/bin/bash

DATABASE=$2
USERNAME=$3
HOSTNAME=$5
export PGPASSWORD=$4

psql -h $HOSTNAME -U $USERNAME $DATABASE << EOF
SELECT
     pg_terminate_backend(pid)
FROM 
     pg_stat_activity
 WHERE
     datname = 'eg_playground_db' AND
     pid <> pg_backend_pid() AND 
     state in ('idle', 'idle in transaction', 'idle in transaction (aborted)', 'disabled')AND state_change < current_timestamp - INTERVAL '15' MINUTE;
EOF