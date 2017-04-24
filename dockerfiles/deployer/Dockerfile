FROM ubuntu:trusty

MAINTAINER Sumanth<nsready@gmail.com>

RUN apt-get update -y && apt-get install python -y && apt-get install curl -y && apt-get install python-pip -y \
&& apt-get install python-yaml -y && apt-get install jq -y

#Install python dependencies
RUN pip install Jinja2 && pip install pycrypto

RUN mkdir -p /.kube

ADD kubeconfig /.kube/config

RUN mkdir -p /kube

RUN chmod 777 /kube

RUN chmod -R 777 /.kube

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

RUN chmod +x ./kubectl

RUN sudo mv ./kubectl /usr/local/bin/kubectl