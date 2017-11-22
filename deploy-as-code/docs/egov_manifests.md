# Cluster deploy manifests

Jinja 2 templates are created for all kubernetes manifests. Jenkins jobs are used to deploy to different environments using these templates.  

### Environment Configuration

Environment configuration is used to configure the services which shall be deployed on an environment. It serves

1. List of services and their properties
2. Global configuration parameters, ex: db settings
3. Kafka topics and their partition/replication count
4. Endpoints that needs to be whitelisted
5. Encrypted Secrets    # Kubernetes Secrets are used to store and serve secrets to various services

An example configuration can be found at [InfraOps repo](https://github.com/egovernments/eGov-infraOps/blob/master/cluster/conf/dev.yml)

### Secrets

Secrets are provided to various services through Kubernetes Secrets. These secrets are AES encrypted using a salt and configured on environment configuration manifests.

To encrypt
```sh
$ python encrypt.py <secret text>

NOTE: Salt needs to be available as environment variable called "EGOV_SECRET_PASSCODE" which is also added in Jenkins Credentials to decrypt while deploying a service.

```

A separate secrets.yml is maintained to push the required secrets to environments.

### Volumes

Some services needs persistent storage to store the data. Volumes are configured through volumes.yml and applied whenever required on the environments.

Kubernetes supports many persistent storage volumes and can be configured in volumes.yml.


## Namespaces
eGov cluster consists of 4 major kubernetes namespaces.
* backbone
* egov
* es-cluster
* logging

### backbone

Backbone namespace consists of
1. kafka: Kafka is used extensively throughout eGov services platform. Kafka manifest consists of a Service definition and Statefulset definition. These manifests also support data volumes which are needed to persist data. Replicas of kafka nodes can be controlled by the environment manifests.
2. zookeeper: Zookeeper manifest contains a service spec and Statefulset spec. Number of zookeeper replicas can be controlled through environment manifests.
3. Redis: Redis is used to store app session data. Redis manifests contains a service definition and Statefulset definition.
4. kafka-create-topic: By default, kafka creates topic (with 1 replication/ 1 partition) if does not exist when the first message is pushed to a topic by a producer. However, it does not create the topic with increased number of replication and partition based on the cluster setup. Hence, kafka-create-topic is used to create kafka topics. Topic names and their respective replication/partitions are provided through environment manifests. Kafka-create-topic is a Kubernetes Job definition which should be run by **kubectl apply** command.

### egov

eGov services mainly follow the following pattern.

1. Kubernetes Service definition
2. Kubernetes Deployment definition
3. Init containers for environment specific db migration if required
3. Init containers for flyway db migration if required
4. Service configuration parameters in the form of environment variables
5. System resource limits

Note: DB migrations may not be needed for web projects.

### es-cluster

eGov uses Elasticsearch for storing some of persistent data. It is also used to aggregate all pods logs. es-cluster consists of

1. es-client: Client ES service which all eGov services connects to
2. es-data: Data node which stores all data. Number of replicas can be controlled through environment manifests.
3. es-master: Master node to manage the es-cluster
4. Kibana: Kibana visualization for both business data and logs


### logging
eGov uses fluentd to aggregate all logs and push to elasticsearch. Fluentd runs as Daemonset on all minions which collects logs from all pods.

A Kubernetes cronjob called delete-old-logs-in-es is created to cleanup all pods logs from elasticsearch cluster regularly. Number of days to keep the logs can be controlled through environment manifests.

Addition to cronjob, logrotate cron job will be running on all minions which can rotate the logs including system logs. Frequency and number of days to rotate the logs can be controlled through environment manifests.

## Misc

There are two more namespaces which can be deployed based on the need.

1. Playground namespace consists of a playground pod which can be used to execute commands on an environment.
2. Monitoring namespace used to configure monitoring solution for the cluster environment. Currently it is in alpha stage.
