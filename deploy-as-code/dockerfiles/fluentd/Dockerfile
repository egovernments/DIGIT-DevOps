FROM gcr.io/google_containers/ubuntu-slim:0.6

# Ensure there are enough file descriptors for running Fluentd.
RUN ulimit -n 65536

# Disable prompts from apt.
ENV DEBIAN_FRONTEND noninteractive


COPY build.sh /tmp/build.sh

RUN chmod +x /tmp/build.sh

RUN /tmp/build.sh

# Copy the Fluentd configuration file.
COPY td-agent.conf /etc/td-agent/td-agent.conf

ENV LD_PRELOAD /opt/td-agent/embedded/lib/libjemalloc.so

COPY start.sh /usr/bin/start.sh

RUN chmod +x /usr/bin/start.sh

CMD ["/usr/bin/start.sh"]