#!/bin/bash

# EKS Cluster Upgrade Script from 1.30 to 1.31
# This script performs a safe upgrade with proper checks

set -e

CLUSTER_NAME="digit-sandbox"
REGION="ap-south-1"

echo "=== EKS Cluster Upgrade Script ==="
echo "Upgrading cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Target version: 1.31"
echo

# Function to check cluster status
check_cluster_status() {
    echo "Checking cluster status..."
    aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status' --output text
}

# Function to check node group status
check_nodegroup_status() {
    echo "Checking node group status..."
    aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name "${CLUSTER_NAME}-ng" --region $REGION --query 'nodegroup.status' --output text
}

# Function to wait for cluster to be active
wait_for_cluster() {
    echo "Waiting for cluster to be ACTIVE..."
    while true; do
        STATUS=$(check_cluster_status)
        if [ "$STATUS" = "ACTIVE" ]; then
            echo "Cluster is ACTIVE"
            break
        else
            echo "Cluster status: $STATUS. Waiting..."
            sleep 30
        fi
    done
}

# Function to wait for node group to be active
wait_for_nodegroup() {
    echo "Waiting for node group to be ACTIVE..."
    while true; do
        STATUS=$(check_nodegroup_status)
        if [ "$STATUS" = "ACTIVE" ]; then
            echo "Node group is ACTIVE"
            break
        else
            echo "Node group status: $STATUS. Waiting..."
            sleep 30
        fi
    done
}

# Pre-upgrade checks
echo "=== Pre-upgrade Checks ==="
echo "Current cluster version:"
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.version' --output text

echo "Current cluster status:"
check_cluster_status

echo "Current node group status:"
check_nodegroup_status

echo
read -p "Do you want to proceed with the upgrade? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 1
fi

# Step 1: Plan the changes
echo
echo "=== Step 1: Planning Terraform Changes ==="
terraform plan -var-file=terraform.tfvars 2>/dev/null || terraform plan

echo
read -p "Do the planned changes look correct? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 1
fi

# Step 2: Apply the upgrade
echo
echo "=== Step 2: Applying EKS Upgrade ==="
echo "This will upgrade the control plane first, then node groups..."

terraform apply -auto-approve -var-file=terraform.tfvars 2>/dev/null || terraform apply -auto-approve

# Step 3: Wait for cluster to be ready
echo
echo "=== Step 3: Waiting for Upgrade to Complete ==="
wait_for_cluster
wait_for_nodegroup

# Step 4: Verify the upgrade
echo
echo "=== Step 4: Post-upgrade Verification ==="
echo "New cluster version:"
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.version' --output text

echo "Cluster status:"
check_cluster_status

echo "Node group status:"
check_nodegroup_status

echo "Checking addon versions:"
aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --output table

echo
echo "=== Upgrade Complete ==="
echo "Please test your applications to ensure they work correctly with Kubernetes 1.31"
echo "Monitor the cluster for any issues over the next few hours."
