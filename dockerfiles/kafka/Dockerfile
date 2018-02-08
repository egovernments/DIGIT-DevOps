FROM wurstmeister/kafka:1.0.0


COPY start-kafka.sh /usr/bin/start-kafka.sh
RUN chmod +x /usr/bin/start-kafka.sh

ADD prom-jmx-agent-config.yml /usr/app/prom-jmx-agent-config.yml
ADD http://central.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.10/jmx_prometheus_javaagent-0.10.jar /usr/app/jmx_prometheus_javaagent.jar


CMD ["start-kafka.sh"]
