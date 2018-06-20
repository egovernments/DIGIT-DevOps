# Setup kubernetes cluster

Kubernetes cluster can be installed in many ways and it supports multiple OS platform.
In eGov, we currently use Redhat EL 7, CentOS or CoreOS on AWS.

eGov cluster has the following kubernetes [components](https://kubernetes.io/docs/concepts/overview/components/).

* etcd					
* kube-apiserver
* kube-controller-manager
* kube-scheduler
* flanneld
* docker
* kube-proxy
* kubelet
* kubedns  # Runs as pod inside the cluster

### For CoreOS on AWS

kube-aws is a command line tool provided by CoreOS to create/update/destroy Kubernetes cluster on Amazon AWS.

* [kube-aws](https://kubernetes-incubator.github.io/kube-aws/getting-started/) - Getting started

### For creating kubernetes cluster on AWS using kube-aws

* [click here for the steps to create kubernetes cluster](https://github.com/egovernments/eGov-infraOps/blob/master/docs/kube_aws_cluster_setup.md)

### For RHEL 7/CentOS

eGov uses ansible scripts to setup kubernetes cluster on RHEL 7 and CentOS. Scripts are available in InfraOps repository under [/ansible](https://github.com/egovernments/eGov-infraOps/tree/master/ansible)


#### Hosts Inventory

Hosts inventory consists of etcd, master and minion groups and their respective

* IP Addresses
* ansible_user : Ansible User name with sudo privileges
* ansible_ssh_private_key_file: SSH key for the user
* unique_nic: NIC which flannel and docker will be running
* master_ip: IP address of the master (can be useful if master is running other than ssh network interface. Then "groups['master'][0]" needs to be replaced with "master_ip" in ansible scripts)

#### SSL Certificates

Ansible scripts include sample CA which can be used to setup developer environment and not recommended for production environments. CA has to be created and copied to \<REPO_DIR\>/ansible/roles/common/files before setting up the cluster.

####  Setup Cluster

To setup the cluster:

```sh
ansible-playbook -i hosts cluster.yml
```

This will setup all components required to run kubernetes cluster. It will also copy all certificates and keys into /tmp/keys.zip file on local system.

#### Install kubectl

Install kubectl on the workstation which is required to interact with kubernetes cluster.

* [How to Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)


#### Accessing kubernetes cluster

* Extract and copy the certificates and keys into ~/.kube/dev/credentials        # dev is the environment name
* Create cluster context by creating/editing **~/.kube/config** similar to below. Adjust the path according to your settings.

```conf
apiVersion: v1
clusters:
- cluster:
    certificate-authority: dev/credentials/ca.pem
    server: https://<cluster_url/IP>
  name: dev
contexts:
- context:
    cluster: dev
    user: dev
  name: dev
current-context: dev
kind: Config
preferences: {}
users:
- name: dev
  user:
    client-certificate: dev/credentials/admin.pem
    client-key: dev/credentials/admin-key.pem
```

* To see all nodes running on the cluster
```sh
kubectl get nodes
```
