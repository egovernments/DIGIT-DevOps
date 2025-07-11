#!/bin/bash

# Fix Spot Capacity Issue for EKS Node Group
# This script addresses the UnfulfillableCapacity error

set -e

CLUSTER_NAME="digit-sandbox"
REGION="ap-south-1"
NODEGROUP_NAME="digit-sandbox-ng-20240827085244645600000015"

echo "=== Fixing Spot Capacity Issue ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo

# Check current status
echo "Current node group status:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text

echo "Current health issues:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.health.issues' --output table

echo "Current instance types:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.instanceTypes' --output table

echo "Current capacity type:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.capacityType' --output text

echo
echo "ISSUE ANALYSIS:"
echo "- The node group is failing due to Spot instance capacity issues"
echo "- Current configuration uses only r5ad.xlarge instances"
echo "- AWS cannot fulfill this specific Spot request"
echo
echo "SOLUTION:"
echo "- Updated configuration to use multiple instance types"
echo "- Added mixed instances policy with On-Demand fallback"
echo "- Using multiple availability zones for better capacity"
echo

read -p "Do you want to apply the fix now? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Fix cancelled."
    exit 1
fi

# Apply the fix
echo "Applying Terraform configuration to fix Spot capacity issue..."
echo "This will:"
echo "1. Update instance types to multiple options"
echo "2. Add mixed instances policy"
echo "3. Use multiple availability zones"
echo "4. Add On-Demand fallback"
echo

# Apply with password
echo "YwSbtF3v" | terraform apply -auto-approve

echo
echo "Waiting for node group to recover..."
sleep 30

# Check status
for i in {1..20}; do
    STATUS=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text)
    echo "Node group status: $STATUS (check $i/20)"
    
    if [ "$STATUS" = "ACTIVE" ]; then
        echo "✅ Node group is now ACTIVE!"
        break
    elif [ "$STATUS" = "CREATE_FAILED" ] || [ "$STATUS" = "DELETE_FAILED" ]; then
        echo "❌ Node group failed. Status: $STATUS"
        echo "Checking health issues:"
        aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.health.issues' --output table
        break
    else
        echo "Status: $STATUS, waiting..."
        sleep 60
    fi
done

echo
echo "=== Final Status Check ==="
echo "Node group status:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text

echo "Health issues (if any):"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.health.issues' --output table

echo "Instance types now in use:"
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.instanceTypes' --output table

echo
echo "If the node group is now ACTIVE, you can proceed with the EKS upgrade!"
echo "Run: ./upgrade-eks-comprehensive.sh"
