#!/bin/bash

DATABASE=$2
USERNAME=$3
PASSWORD=$4
HOSTNAME=$5

# Start the run once job.
echo "Docker container has been started"

declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /container.env

# Setup a cron schedule
echo "SHELL=/bin/bash
BASH_ENV=/container.env
* * * * * /CleanLocks.sh $DATABASE $USERNAME $PASSWORD $HOSTNAME>> /var/log/cron.log 2>&1
# This extra line makes it a valid cron" > scheduler.txt

crontab scheduler.txt
cron -f