FROM verdaccio/verdaccio:latest

MAINTAINER Senthil Kalimuthu<senthil.kalimuthu@tarento.com>

ADD ./config.yaml  /verdaccio/conf/config.yaml

RUN ln -s /verdaccio/storage/egov-user/htpasswd /verdaccio/conf/htpasswd

USER root
