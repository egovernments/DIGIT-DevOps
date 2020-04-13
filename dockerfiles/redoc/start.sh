#!/bin/sh

#includes lsb functions
. /lib/lsb/init-functions

# Start cron for needed regular logrotate
CRON=`which cron`
log_daemon_msg "Starting ${CRON}"
$CRON -f &

# Start NGINX
log_daemon_msg "Starting NGINX"
/usr/sbin/nginx -g "daemon off;"
