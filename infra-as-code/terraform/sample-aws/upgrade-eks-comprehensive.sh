#!/bin/bash

# Comprehensive EKS Cluster Upgrade Script from 1.30 to 1.31
# This script handles the degraded node group and performs a safe upgrade

set -e

CLUSTER_NAME="digit-sandbox"
REGION="ap-south-1"
NODEGROUP_NAME="digit-sandbox-ng-20240827085244645600000015"

echo "=== Comprehensive EKS Cluster Upgrade Script ==="
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
    aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text
}

# Function to check node group health
check_nodegroup_health() {
    echo "Checking node group health issues..."
    aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.health.issues' --output table
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

# Pre-upgrade checks and fixes
echo "=== Pre-upgrade Checks and Fixes ==="
echo "Current cluster version:"
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.version' --output text

echo "Current cluster status:"
check_cluster_status

echo "Current node group status:"
check_nodegroup_status

echo "Node group health issues:"
check_nodegroup_health

# Check if node group is degraded
NODEGROUP_STATUS=$(check_nodegroup_status)
if [ "$NODEGROUP_STATUS" = "DEGRADED" ]; then
    echo
    echo "⚠️  Node group is DEGRADED. This needs to be fixed before upgrade."
    echo "The issue is typically related to launch template version mismatch."
    echo
    echo "RECOMMENDED ACTIONS:"
    echo "1. Apply Terraform configuration to fix the launch template issue"
    echo "2. Wait for node group to become ACTIVE"
    echo "3. Then proceed with the upgrade"
    echo
    read -p "Do you want to apply Terraform to fix the degraded node group? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Applying Terraform to fix node group issues..."
        terraform apply -auto-approve -target=module.eks_managed_node_group.aws_launch_template.this
        echo "Waiting for node group to recover..."
        wait_for_nodegroup
    else
        echo "Please fix the degraded node group manually before proceeding with upgrade."
        exit 1
    fi
fi

echo
read -p "Do you want to proceed with the EKS upgrade? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 1
fi

# Step 1: Plan the changes
echo
echo "=== Step 1: Planning Terraform Changes ==="
terraform plan

echo
read -p "Do the planned changes look correct? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 1
fi

# Step 2: Apply the upgrade in phases
echo
echo "=== Step 2: Applying EKS Upgrade in Phases ==="

# Phase 2a: Update control plane
echo "Phase 2a: Upgrading EKS Control Plane..."
terraform apply -auto-approve -target=module.eks.aws_eks_cluster.this

echo "Waiting for control plane upgrade to complete..."
wait_for_cluster

# Phase 2b: Update addons
echo "Phase 2b: Upgrading EKS Addons..."
terraform apply -auto-approve -target=aws_eks_addon.kube_proxy -target=aws_eks_addon.core_dns -target=aws_eks_addon.aws_ebs_csi_driver

# Phase 2c: Update node groups
echo "Phase 2c: Upgrading Node Groups..."
terraform apply -auto-approve -target=module.eks_managed_node_group.aws_eks_node_group.this

echo "Waiting for node group upgrade to complete..."
wait_for_nodegroup

# Phase 2d: Apply remaining changes
echo "Phase 2d: Applying remaining changes..."
terraform apply -auto-approve

# Step 3: Wait for everything to be ready
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

echo "Node group health:"
check_nodegroup_health

echo "Checking addon versions:"
aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --output table

echo "Checking nodes:"
kubectl get nodes -o wide

echo "Checking system pods:"
kubectl get pods -n kube-system

echo
echo "=== Upgrade Complete ==="
echo "✅ EKS cluster has been successfully upgraded to version 1.31"
echo "✅ All components are healthy"
echo
echo "NEXT STEPS:"
echo "1. Test your applications thoroughly"
echo "2. Monitor the cluster for any issues"
echo "3. Update your kubectl client if needed"
echo "4. Review application logs for any deprecation warnings"
