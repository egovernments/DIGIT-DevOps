FROM ubuntu:18.04

LABEL author="devops@egovernments.org" 

ENV DATABASE=pg_database_name \
    USERNAME=pg_username      \
    PASSWORD=pg_password       \
    HOSTNAME=pg_hostname

RUN apt-get update && apt-get install -y \
    socat \
    postgresql-client-10 \
    && rm -rf /var/lib/apt/lists/*

# Install cron
RUN apt-get update && apt-get install -y cron

ADD run.sh /usr/bin/run.sh

# Add files
ADD CleanLocks.sh /usr/bin/CleanLocks.sh
ADD EntryPoint.sh /usr/bin/EntryPoint.sh

RUN chmod +x /usr/bin/run.sh
RUN chmod +x /usr/bin/CleanLocks.sh
RUN chmod +x /usr/bin/EntryPoint.sh

CMD ["/usr/bin/run.sh"]

ENTRYPOINT ["/usr/bin/entrypoint.sh $DATABASE $USERNAME $PASSWORD $HOSTNAME"]