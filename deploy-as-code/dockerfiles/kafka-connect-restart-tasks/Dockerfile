FROM alpine:3.11
RUN apk add --update curl jq util-linux && \
    rm -rf /var/cache/apk/*
COPY kafka-connect-restart-tasks.sh /tmp
RUN  chmod +x /tmp/kafka-connect-restart-tasks.sh

CMD ["/tmp/kafka-connect-restart-tasks.sh"]