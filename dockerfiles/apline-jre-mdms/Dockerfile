FROM openjdk:8u121-jre-alpine

RUN apk update && apk upgrade && \
apk add --no-cache bash git openssh

ENV datadir /opt/mdms

RUN mkdir -p ${datadir}

WORKDIR ${datadir}

RUN git init && git remote add -m -f origin https://github.com/egovernments/egov-mdms-data.git

RUN git config core.sparseCheckout true

RUN echo "/data" >> .git/info/sparse-checkout

RUN git pull origin master
