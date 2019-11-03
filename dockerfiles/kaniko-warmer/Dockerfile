FROM gcr.io/kaniko-project/warmer:latest

FROM alpine:3.7
COPY --from=0 /kaniko/warmer /kaniko/warmer 
ENV HOME /root
ENV USER /root
ENV PATH "$PATH:/kaniko"
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/
WORKDIR /workspace