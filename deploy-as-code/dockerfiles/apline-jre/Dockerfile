FROM openjdk:8-jre-alpine

RUN apk add tini --no-cache --update && \
    rm -rf /var/cache/apk/*
# Tini is now available at /sbin/tini
ENTRYPOINT ["/sbin/tini", "-e", "143", "--"]