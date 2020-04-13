FROM ubuntu:18.04

LABEL author="devops@egovernments.org" 

RUN apt-get update && apt-get install -y \
    socat \
    postgresql-client-10 \
    && rm -rf /var/lib/apt/lists/*

ADD run.sh /usr/bin/run.sh

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]
