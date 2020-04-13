FROM maven:3.6.1-ibmjava-8-alpine
ARG token
RUN apk update && \
    apk add --update git
COPY settings.xml /usr/share/maven/conf/
COPY cache-warmer.sh urls.txt /tmp/maven-builder/
RUN  cp /usr/share/maven/conf/settings.xml /usr/share/maven/ref/settings.xml && cd /tmp/maven-builder && chmod +x cache-warmer.sh && sh cache-warmer.sh urls.txt $token && rm -rf /tmp/maven-builder