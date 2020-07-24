FROM jenkins/jenkins:2.242-alpine

ENV JENKINS_USER admin
ENV JENKINS_PASS admin

# Skip initial setup
ENV JAVA_OPTS "-Djenkins.install.runSetupWizard=false -Duser.timezone=Asia/Calcutta"


COPY plugins.txt /usr/share/jenkins/plugins.txt
RUN /usr/local/bin/install-plugins.sh < /usr/share/jenkins/plugins.txt