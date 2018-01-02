FROM quay.io/pires/docker-elasticsearch:6.1.1

MAINTAINER Sumanth<nsready@gmai.com>

# Override config, otherwise plug-in install will fail
ADD config /elasticsearch/config

# Set environment
ENV NAMESPACE default
ENV DISCOVERY_SERVICE elasticsearch-discovery
