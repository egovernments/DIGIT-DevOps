# Infrastructure Update - Kubernetes 1.31 Deployment

## 🚀 What’s New

We have made the following updates to our Terraform codebase:

Kubernetes Version: Upgraded to v1.31

S3 Filestore Bucket: Filestore S3 bucket will be created automatically and filestore Secrets are now automatically created during infra creation.
By default, secrets are created in the egov namespace.

To change the namespace, update the namespace variable in variables.tf.
```
variable "filestore_namespace" {
  description = "Provide the namespace to create filestore secret"
  default = "egov" #REPLACE  
}
```

## ⚙️ Configuration Details
Instance Type: Default instance type is set to m5.xlarge

Max Pods per Node: Set to 50

To Modify Configurations:
Update variables.tf to change instance type or to provide multiple instance types
```
variable "instance_types" {
  description = "Arry of instance types for SPOT instances"
  default = ["m5a.xlarge", "r5ad.xlarge", "m6a.xlarge"] 
}
```
Update user-data.yaml to modify the maxPods value
```
sed -i 's/"maxPods": [0-9]\+/"maxPods": 50/' $CONFIG_FILE
```

## 📌 Note on Max Pods

To find the recommended maxPods value for your instance type, run the following command in your terminal:

```
curl -O https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/templates/al2/runtime/max-pods-calculator.sh

chmod +x max-pods-calculator.sh

./max-pods-calculator.sh --instance-type m5.large --cni-version 1.9.0-eksbuild.1
```

Or refer to this site [here](https://www.middlewareinventory.com/blog/kubernetes-max-pods-per-node/)
## 📚 Documentation

Refer to our [Core Infrastructure Documentation](https://core.digit.org/guides/installation-guide/infrastructure-setup/aws/3.-provision-infrastructure) to deploy the infrastructure end-to-end.
