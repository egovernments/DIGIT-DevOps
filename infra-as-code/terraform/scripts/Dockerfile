FROM ubuntu:latest

# Update and upgrade system packages
RUN apt update && apt upgrade -y

# Install curl, unzip, and other prerequisites
RUN apt install -y curl unzip gnupg

# Download and install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.22.0/bin/linux/amd64/kubectl
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl

# Install dependencies
RUN apt-get update && apt-get install -y curl unzip libc6

# Based on underlying architectire change the url for awscli and AWS IAM Authenticator
# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install

# Install AWS IAM Authenticator
RUN curl -Lo aws-iam-authenticator https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.5.9/aws-iam-authenticator_0.5.9_linux_arm64 \
    && chmod +x ./aws-iam-authenticator \
    && mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator

# Cleanup
RUN rm -rf awscliv2.zip ./aws

# Install Git
RUN apt install -y git

# Install Go
RUN apt install -y golang-go

# Add Helm GPG key
RUN curl https://baltocdn.com/helm/signing.asc | gpg --dearmor > /usr/share/keyrings/helm-keyring.gpg

# Install apt-transport-https
RUN apt-get install -y apt-transport-https

# Add Helm repository
RUN echo "deb [signed-by=/usr/share/keyrings/helm-keyring.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list

# Update and install Helm
RUN apt-get update
RUN apt-get install -y helm

# Download and install Terraform
RUN curl -LO https://releases.hashicorp.com/terraform/1.0.0/terraform_1.0.0_linux_amd64.zip
RUN unzip terraform_1.0.0_linux_amd64.zip
RUN mv terraform /usr/local/bin/
RUN terraform version

# Set the working directory
WORKDIR /app

# Start a bash shell as the default command
CMD tail -f /dev/null
