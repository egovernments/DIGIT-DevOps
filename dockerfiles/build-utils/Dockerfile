FROM alpine:3.7
RUN apk --update add git openssh curl jq && \
    rm -rf /var/lib/apt/lists/* && \
    rm /var/cache/apk/*
COPY create_repo.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/create_repo.sh
ENTRYPOINT ["/bin/sh"]