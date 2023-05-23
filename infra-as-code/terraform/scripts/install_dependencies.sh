#!/bin/bash

# Update and upgrade system packages
sudo apt update && sudo apt upgrade

# Install curl
sudo apt install curl

# Verify curl installation
curl --version

# Download and install kubectl
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.22.17/2023-03-17/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl
export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
kubectl version --short --client

# Install k9s
snap install k9s
k9s version

# Download and install aws-iam-authenticator
curl -Lo aws-iam-authenticator https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.5.9/aws-iam-authenticator_0.5.9_linux_amd64
chmod +x ./aws-iam-authenticator
mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator
export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
aws-iam-authenticator help

# Download and install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install Terraform
sudo snap install terraform --classic
terraform version

# Update system packages
sudo apt update

# Install Git
sudo apt install git
git --version

# Install Go
sudo snap install go

# Add Helm GPG key
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

# Install apt-transport-https
sudo apt-get install apt-transport-https --yes

# Add Helm repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Update and install Helm
sudo apt-get update
sudo apt-get install helm

# Make script executable
chmod +x "$0"