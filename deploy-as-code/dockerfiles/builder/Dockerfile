FROM alpine
ARG OQ_VERSION=1.1.1

RUN apk --update --no-cache --virtual temp add wget && wget https://github.com/Blacksmoke16/oq/releases/download/v${OQ_VERSION}/oq-v${OQ_VERSION}-linux-x86_64 -O /usr/local/bin/oq && chmod +x /usr/local/bin/oq && apk del temp
RUN apk --udpate --no-cache add jq git

COPY *.sh /scripts/
ENV PATH=$PATH:/scripts