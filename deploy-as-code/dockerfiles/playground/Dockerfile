FROM ubuntu:trusty

MAINTAINER Sumanth<nsready@gmail.com>

RUN apt-get update -y && apt-get install python wget software-properties-common -y && apt-get install curl -y

RUN sudo add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main"

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

RUN apt-get update && apt-get install -y postgresql-client-9.6

ADD run.sh /usr/bin/run.sh

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]
