FROM anapsix/alpine-java

ARG kafka_version=0.10.1.1
ARG scala_version=2.11

MAINTAINER Sumanth<nsready@gmail.com>

RUN apk add --update unzip wget curl docker jq coreutils

ENV KAFKA_VERSION=$kafka_version SCALA_VERSION=$scala_version
ADD download-kafka.sh /tmp/download-kafka.sh
RUN chmod a+x /tmp/download-kafka.sh && sync && /tmp/download-kafka.sh && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz && ln -s /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} /opt/kafka

ENV KAFKA_HOME /opt/kafka
ENV PATH ${PATH}:${KAFKA_HOME}/bin
ADD create-topics.sh /usr/bin/create-topics.sh

# The scripts need to have executable permission
RUN chmod a+x /usr/bin/create-topics.sh