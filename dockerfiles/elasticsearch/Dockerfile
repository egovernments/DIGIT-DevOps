FROM quay.io/pires/docker-elasticsearch:6.4.2

MAINTAINER Sivaprakash<sivaprakash.ramasamy@tarento.com>

# Override config, otherwise plug-in install will fail
ADD config /elasticsearch/config


# Set environment
ENV NAMESPACE default
ENV DISCOVERY_SERVICE elasticsearch-discovery
