FROM ubuntu:18.04

LABEL author="devops@egovernments.org" 

ENV DATABASE=pg_database_name \
    USERNAME=pg_username      \
    PASSWORD=pg_password       \
    HOSTNAME=pg_hostname

RUN apt-get update && apt-get install -y \
    socat \
    postgresql-client-10 \
    cron \
    kafkacat \
    && rm -rf /var/lib/apt/lists/*

ADD run.sh CleanLocks.sh EntryPoint.sh /usr/bin/

RUN chmod +x /usr/bin/run.sh /usr/bin/CleanLocks.sh /usr/bin/EntryPoint.sh

CMD ["/usr/bin/run.sh"]

# ENTRYPOINT ["/usr/bin/entrypoint.sh $DATABASE $USERNAME $PASSWORD $HOSTNAME"]