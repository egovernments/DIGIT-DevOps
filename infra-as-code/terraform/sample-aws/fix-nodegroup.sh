#!/bin/bash

# Quick fix for degraded node group
# This script addresses the launch template version mismatch

set -e

CLUSTER_NAME="digit-sandbox"
REGION="ap-south-1"
NODEGROUP_NAME="digit-sandbox-ng-20240827085244645600000015"

echo "=== Node Group Health Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo

# Check current status
echo "Current node group status:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text

echo "Current health issues:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.health.issues' --output table

echo
echo "The issue is typically a launch template version mismatch."
echo "This can be fixed by applying the Terraform configuration."
echo

read -p "Do you want to fix the node group now? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Fix cancelled."
    exit 1
fi

# Apply targeted fix
echo "Applying Terraform fix for launch template..."
terraform apply -target=module.eks_managed_node_group.aws_launch_template.this[0] -auto-approve

echo "Waiting for node group to recover..."
while true; do
    STATUS=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text)
    echo "Node group status: $STATUS"
    if [ "$STATUS" = "ACTIVE" ]; then
        echo "✅ Node group is now ACTIVE!"
        break
    elif [ "$STATUS" = "DEGRADED" ]; then
        echo "Still degraded, continuing to wait..."
    else
        echo "Status: $STATUS, waiting..."
    fi
    sleep 30
done

echo
echo "=== Node Group Fix Complete ==="
echo "✅ Node group is healthy and ready for upgrade"
echo
echo "You can now proceed with the EKS upgrade using:"
echo "./upgrade-eks-comprehensive.sh"
