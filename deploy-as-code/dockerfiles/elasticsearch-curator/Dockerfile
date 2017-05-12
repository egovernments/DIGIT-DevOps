FROM ubuntu:trusty

MAINTAINER Sumanth<nsready@gmail.com>

RUN apt-get update -y && apt-get install python -y && apt-get install python-dev -y && apt-get install python-pip -y

#Install python dependencies
RUN pip install elasticsearch-curator

RUN mkdir -p /.curator

ADD curator.yml /.curator/curator.yml

ADD delete_old_logs.yml /.curator/delete_old_logs.yml

COPY start.sh /usr/bin/start.sh

RUN chmod +x /usr/bin/start.sh