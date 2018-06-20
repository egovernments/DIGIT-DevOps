Pre-requisites
1. Before creating the cluster make sure you have the admin access to the AWS account we are going to use
2. Instances whose types are larger than or equal to t2.medium should be chosen for the cluster to work reliably
3. At least 3 etcd, 2 controller, 2 worker nodes are required to achieve high availability
4. Download the kube-aws version which matches your kubernetes version. Eg: kube-aws 0.9.8 installs Kubernetes: v1.7.8, Etcd: v3.2.9 which is required for the current setup

* Before creating the cluster on AWS, IAM account with admin privileges, ARN key, S3 Bucket and key pair has to be created
* [How to create IAM and ARN Key](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

Getting Started

1. Download the kube-aws from the github page. The kube-aws binary is available for Mac and Linux. 

https://github.com/kubernetes-incubator/kube-aws/releases

2. Extract the kube-aws-linux-amd64.tar.gz and copy it to /usr/bin
```sh
$ tar -xvzf kube-aws-linux-amd64.tar.gz 
$ sudo cp kube-aws /usr/bin/
```
3. Create a directory to generate cluster and certificates
```sh
$ mkdir dev-cluster
$ cd dev-cluster
$ kube-aws init --cluster-name=dev-cluster \
--s3-uri=s3://dev-cluster/dev \
--region=ap-south-1 \
--availability-zone=ap-south-1b \
--key-name=<key-pair-name> \
--kms-key-arn="arn:aws:kms:ap-south-1:xxxxxxxxxx:key/xxxxxxxxxxxxxxxxxxx"
```
4. A file name cluster.yaml has been generated with the details provided in the previous init command.
   Edit the cluster.yaml and make appropriate changes with the number of master, etcd and nodes required.
   Also the changes required on AWS configuration VPC, Region, Subnet, Availability Zone, etc..

5. Generate Assets
```sh
$ kube-aws render credentials --generate-ca
$ kube-aws render stack
```
6. Validate configuration
```sh
$ kube-aws validate
```
7. Launch the cluster
```sh
$ kube-aws up
```
8. Once the cluster is up we will receive a public domain name which needs to pointed in our DNS configuration.
   [Sample cluster.yaml](https://github.com/egovernments/eGov-infraOps/blob/master/docs/cluster_yaml.md)


9. Copy the certificates to your local .kube configuration folder and access the cluster
```sh   
$ kubectl get nodes (to list the installed nodes)
```


