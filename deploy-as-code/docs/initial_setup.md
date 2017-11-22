# Initial Setup

Necessary volumes and secrets needs to be created before deploying any services which needs any of them. Below are the order to deploy backbone services.

In general, Jenkins job is used to deploy all services unless it is mentioned separately. The latest docker tag can be taken from Docker hub. Please note, all services does not have "latest" as tag.


1. Fluentd: Even though fluentd can be deployed through Jenkins, I recommend deploying through command line which will help in creating necessary volumes.

	Run the below command from InfraOps repository directory.
```sh
$ python scripts/apply.py -e dev -m fluentd -i egovio/fluentd:v0.1.9 -conf -secret -vol

where
	* -e : environment name and cluster/conf/dev.yml should exist
	* -m : service name to be deployed
	* -i : docker image with tag    #v0.1.9 is the latest tag
	* -conf: Create ConfigMap
	* -secret: Create Secrets
	* -vol: Create Volumes
```

2.  delete-old-logs-in-es
3.  logrotate
4.  redis
5.  zookeeper
6.  kafka
7.  kafka-create-topic
8.  es-master
9.  es-data
10.  es-client
11.  kibana
12.  nginx
13.  zuul


Once the backbone is up and running, all other services can be deployed in any order.
