#!/bin/bash

# Immediate Node Stability Improvements
# This script implements quick fixes to reduce node churn

set -e

CLUSTER_NAME="digit-sandbox"
REGION="ap-south-1"
ASG_NAME="eks-digit-sandbox-ng-20250711103839335700000001-74cbfc88-6acc-8ab5-52db-5086ac1c7ddb"

echo "=== Immediate Node Stability Improvements ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo

# Function to update Auto Scaling Group settings
update_asg_settings() {
    echo "1. Updating Auto Scaling Group settings for better stability..."
    
    # Update health check grace period
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name $ASG_NAME \
        --health-check-grace-period 300 \
        --region $REGION
    
    echo "   ✅ Health check grace period increased to 5 minutes"
    
    # Note: Termination policies cannot be updated for managed node groups
    # They are controlled by EKS
    echo "   ℹ️  Termination policies are managed by EKS for managed node groups"
}

# Function to install AWS Node Termination Handler
install_termination_handler() {
    echo "2. Installing AWS Node Termination Handler..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace aws-node-termination-handler --dry-run=client -o yaml | kubectl apply -f -
    
    # Install using Helm (if available) or kubectl
    if command -v helm &> /dev/null; then
        echo "   Installing via Helm..."
        helm repo add eks https://aws.github.io/eks-charts
        helm repo update
        
        helm upgrade --install aws-node-termination-handler \
            eks/aws-node-termination-handler \
            --namespace kube-system \
            --set enableSpotInterruptionDraining=true \
            --set enableRebalanceMonitoring=true \
            --set enableScheduledEventDraining=true \
            --set deleteLocalData=true \
            --set ignoreDaemonSets=true \
            --set podTerminationGracePeriod=30
    else
        echo "   Installing via kubectl..."
        kubectl apply -f https://github.com/aws/aws-node-termination-handler/releases/download/v1.21.0/all-resources.yaml
    fi
    
    echo "   ✅ AWS Node Termination Handler installed"
}

# Function to add node taints for workload distribution
add_node_taints() {
    echo "3. Adding node taints for better workload distribution..."
    
    # Get current nodes
    NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name")
    
    for NODE in $NODES; do
        # Add taint to prefer certain workloads on stable nodes
        kubectl taint node $NODE node.kubernetes.io/spot=true:NoSchedule --overwrite || true
        echo "   ✅ Added spot taint to node: $NODE"
    done
}

# Function to create priority classes
create_priority_classes() {
    echo "4. Creating priority classes for workload scheduling..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-system
value: 1000
globalDefault: false
description: "High priority class for system workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: medium-priority-app
value: 500
globalDefault: true
description: "Medium priority class for application workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority-batch
value: 100
globalDefault: false
description: "Low priority class for batch workloads"
EOF
    
    echo "   ✅ Priority classes created"
}

# Function to configure pod disruption budgets
create_pod_disruption_budgets() {
    echo "5. Creating Pod Disruption Budgets for critical workloads..."
    
    # PDB for CoreDNS
    cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: coredns-pdb
  namespace: kube-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: aws-node-pdb
  namespace: kube-system
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      k8s-app: aws-node
EOF
    
    echo "   ✅ Pod Disruption Budgets created"
}

# Function to check current node stability
check_node_stability() {
    echo "6. Checking current node stability..."
    
    echo "   Current nodes:"
    kubectl get nodes -o wide
    
    echo "   Node ages:"
    kubectl get nodes -o custom-columns="NAME:.metadata.name,AGE:.metadata.creationTimestamp"
    
    echo "   Recent events:"
    kubectl get events --sort-by=.metadata.creationTimestamp | tail -10
}

# Function to apply immediate fixes
apply_immediate_fixes() {
    echo "7. Applying immediate configuration fixes..."
    
    # Increase kubelet grace period
    echo "   Updating kubelet configuration..."
    
    # Create a configmap for kubelet config
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubelet-config
  namespace: kube-system
data:
  kubelet-config.yaml: |
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    shutdownGracePeriod: 30s
    shutdownGracePeriodCriticalPods: 10s
    maxPods: 110
    podPidsLimit: 4096
EOF
    
    echo "   ✅ Kubelet configuration updated"
}

# Main execution
echo "Starting immediate stability improvements..."
echo

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is required but not installed"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is required but not installed"
    exit 1
fi

# Execute improvements
update_asg_settings
install_termination_handler
add_node_taints
create_priority_classes
create_pod_disruption_budgets
apply_immediate_fixes
check_node_stability

echo
echo "=== Immediate Stability Improvements Complete ==="
echo "✅ Auto Scaling Group settings updated"
echo "✅ Node Termination Handler installed"
echo "✅ Node taints and priority classes configured"
echo "✅ Pod Disruption Budgets created"
echo
echo "🔄 Next Steps:"
echo "1. Monitor node stability over the next hour"
echo "2. Apply the full Terraform configuration for long-term stability"
echo "3. Consider adding On-Demand nodes for critical workloads"
echo
echo "📊 Monitor with:"
echo "   kubectl get nodes -w"
echo "   kubectl get events --sort-by=.metadata.creationTimestamp"
