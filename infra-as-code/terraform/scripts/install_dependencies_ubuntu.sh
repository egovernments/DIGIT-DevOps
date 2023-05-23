#!/bin/bash

# Update and upgrade system packages
sudo apt update && sudo apt upgrade -y

# Install curl
sudo apt install -y curl

# Verify curl installation
curl --version

# Download and install kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.22.0/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --short --client

# Install k9s
sudo apt install -y k9s
k9s version

# Download and install aws-iam-authenticator
curl -Lo aws-iam-authenticator https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/latest/download/aws-iam-authenticator_`uname -s`_`uname -m`
chmod +x ./aws-iam-authenticator
sudo mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator
aws-iam-authenticator help

# Download and install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install Terraform
sudo apt install -y terraform
terraform version

# Update system packages
sudo apt update

# Install Git
sudo apt install -y git
git --version

# Install Go
sudo apt install -y golang-go

# Add Helm GPG key
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

# Install apt-transport-https
sudo apt-get install -y apt-transport-https

# Add Helm repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Update and install Helm
sudo apt-get update
sudo apt-get install -y helm
