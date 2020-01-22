FROM jboss/base-jdk:11

# Set the WILDFLY_VERSION env variable
ENV WILDFLY_VERSION wildfly-latest
#ENV WILDFLY_SHA1 eaef7a87062837c215e54511c4ada8951f0bd8d5
ENV JBOSS_HOME /opt/jboss/wildfly

USER root

# Add the WildFly distribution to /opt, and make wildfly the owner of the extracted tar content
# Make sure the distribution is available from a well-known place
RUN cd $HOME \
    && curl -O https://devops.egovernments.org/Downloads/wildfly/$WILDFLY_VERSION.zip \
    && unzip $WILDFLY_VERSION.zip \
    && rm $WILDFLY_VERSION.zip \
    && mv $HOME/wildfly-* $JBOSS_HOME \
    && chown -R jboss:jboss ${JBOSS_HOME} \
    && chmod -R 775 ${JBOSS_HOME}
COPY org /opt/jboss/wildfly/modules/system/layers/base/org
COPY standalone.xml /opt/jboss/wildfly/standalone/configuration/
COPY standalone.conf /opt/jboss/wildfly/bin/
# Ensure signals are forwarded to the JVM process correctly for graceful shutdown
ENV LAUNCH_JBOSS_IN_BACKGROUND true

USER jboss

# Expose the ports we're interested in
EXPOSE 8080 9990

RUN /opt/jboss/wildfly/bin/add-user.sh admin Admin#70365 --silent

# Set the default command to run on boot
# This will boot WildFly in the standalone mode and bind to all interface
CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0", "-bmanagement", "0.0.0.0", "-Ddb.migration.enabled=false"]
