#!/bin/bash

# Install Homebrew (if not installed)
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Update Homebrew
brew update

# Install curl
brew install curl

# Verify curl installation
curl --version

# Download and install kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.22.0/bin/darwin/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --short --client

# Install k9s
brew install k9s
k9s version

# Download and install aws-iam-authenticator
curl -Lo aws-iam-authenticator https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/latest/download/aws-iam-authenticator_`uname -s | tr '[:upper:]' '[:lower:]'`_`uname -m`
chmod +x ./aws-iam-authenticator
sudo mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator
aws-iam-authenticator help

# Download and install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install Terraform
brew install terraform
terraform version

# Install Git
brew install git
git --version

# Install Go
brew install go

# Add Helm GPG key
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/local/share/keyrings/helm.gpg > /dev/null

# Install Helm
echo "deb [arch=$(uname -m | sed 's/x86_64/amd64/')] https://baltocdn.com/helm/stable/homebrew/ all" | sudo tee /etc/apt/sources.list.d/helm-stable-homebrew.list > /dev/null
brew install helm
