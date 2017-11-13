#FROM ubuntu:16.04
FROM phusion/baseimage:0.9.22

MAINTAINER Senthil<senthil.kalimuthu@tarento.com>

RUN apt-get  clean && apt-get update && apt-get install -y --no-install-recommends libwww-perl libdatetime-perl ca-certificates wget unzip python-pip curl groff
RUN wget http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip && \
    unzip CloudWatchMonitoringScripts-1.2.1.zip && \
    rm CloudWatchMonitoringScripts-1.2.1.zip
    
WORKDIR aws-scripts-mon

RUN sed -i 's/-k -l -P/-kP/g' mon-put-instance-data.pl

RUN mkdir -p ~/.aws && \
	pip install awscli 

RUN rm -rf /var/lib/apt/lists/*

RUN apt-get purge -y  fonts-dejavu-core fontconfig-config x11-common libjpeg-turbo8 libice6 libpng12-0 imagemagick-6.q16 imagemagick-common imagemagick iproute2 isc-dhcp-client isc-dhcp-common python-pip-whl python-pkg-resources python-setuptools python-wheel  xml-core xz-utils rename sgml-base ucf hicolor-icon-theme python-dev

RUN apt-get autoremove -y
  
COPY ./aws_config  /root/.aws/credentials
COPY entrypoint.sh entrypoint.sh 
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]

#RUN apk add --no-cache perl-libwww perl-datetime perl-libwww perl-lwp-protocol-https
#RUN wget http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip && \
#    unzip CloudWatchMonitoringScripts-1.2.1.zip && \
#    rm CloudWatchMonitoringScripts-1.2.1.zip
#    
#WORKDIR aws-scripts-mon

#RUN sed -i 's/-k -l -P/-kP/g' mon-put-instance-data.pl

#COPY entrypoint.sh entrypoint.sh
#RUN chmod +x entrypoint.sh
#CMD ["./entrypoint.sh"]
