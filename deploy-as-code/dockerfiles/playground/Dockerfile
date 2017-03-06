FROM ubuntu:trusty

MAINTAINER Sumanth<nsready@gmail.com>

RUN apt-get update -y && apt-get install python -y && apt-get install curl -y \
&& apt-get install postgresql-client -y

ADD run.sh /usr/bin/run.sh

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]