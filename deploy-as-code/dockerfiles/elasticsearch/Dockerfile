FROM docker.elastic.co/elasticsearch/elasticsearch:6.6.2

MAINTAINER gajendran.c@egovernments.org

# Override config, otherwise plug-in install will fail
ADD config /elasticsearch/config


# Set environment
ENV NAMESPACE es-cluster
ENV DISCOVERY_SERVICE elasticsearch-discovery
