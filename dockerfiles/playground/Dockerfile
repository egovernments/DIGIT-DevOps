FROM ubuntu:xenial

MAINTAINER Sumanth<nsready@gmail.com>

RUN apt-get clean && apt-get update

RUN apt-get install -y python wget software-properties-common curl

RUN add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

RUN curl -sL https://deb.nodesource.com/setup_8.x | bash -

RUN apt-get update && apt-get install -y nodejs postgresql-client-9.6

RUN npm install elasticdump -g

ADD run.sh /usr/bin/run.sh

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]
