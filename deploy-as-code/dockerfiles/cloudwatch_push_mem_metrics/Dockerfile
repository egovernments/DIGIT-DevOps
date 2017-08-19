FROM alpine:3.5

MAINTAINER Senthil<senthil.kalimuthu@tarento.com>

#Credits to https://rsmitty.github.io/CoreOS-CloudWatch-Metrics/

RUN apk add --no-cache perl-libwww perl-datetime perl-libwww perl-lwp-protocol-https
RUN wget http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip && \
    unzip CloudWatchMonitoringScripts-1.2.1.zip && \
    rm CloudWatchMonitoringScripts-1.2.1.zip
    
WORKDIR aws-scripts-mon

RUN sed -i 's/-k -l -P/-kP/g' mon-put-instance-data.pl

COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
