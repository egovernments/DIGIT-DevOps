# Manual EKS Upgrade Guide: 1.30 → 1.31

## Current Situation Analysis

### Issues Identified
1. **Node Group Status**: DEGRADED due to launch template version mismatch
2. **Root Cause**: Launch template version conflict between EKS and Auto Scaling Group
3. **Impact**: Must be resolved before upgrade can proceed

### Pre-Upgrade Requirements
- ✅ Backup created
- ✅ Terraform configuration updated
- ⚠️ Node group health issue needs resolution

## Step-by-Step Manual Upgrade Process

### Phase 1: Fix Degraded Node Group

#### 1.1 Check Current Status
```bash
# Check cluster status
aws eks describe-cluster --name digit-sandbox --region ap-south-1 --query 'cluster.status'

# Check node group status
aws eks describe-nodegroup --cluster-name digit-sandbox --nodegroup-name digit-sandbox-ng-20240827085244645600000015 --region ap-south-1 --query 'nodegroup.status'

# Check health issues
aws eks describe-nodegroup --cluster-name digit-sandbox --nodegroup-name digit-sandbox-ng-20240827085244645600000015 --region ap-south-1 --query 'nodegroup.health.issues'
```

#### 1.2 Fix Launch Template Issue
```bash
# Apply targeted fix for launch template
terraform apply -target=module.eks_managed_node_group.aws_launch_template.this[0]

# Wait for node group to recover
# Monitor status until it becomes ACTIVE
```

### Phase 2: Control Plane Upgrade

#### 2.1 Upgrade EKS Control Plane
```bash
# Apply control plane upgrade
terraform apply -target=module.eks.aws_eks_cluster.this[0]

# Monitor upgrade progress
aws eks describe-cluster --name digit-sandbox --region ap-south-1 --query 'cluster.{Version:version,Status:status}'
```

#### 2.2 Wait for Control Plane
```bash
# Wait until status is ACTIVE
while true; do
  STATUS=$(aws eks describe-cluster --name digit-sandbox --region ap-south-1 --query 'cluster.status' --output text)
  echo "Control plane status: $STATUS"
  if [ "$STATUS" = "ACTIVE" ]; then
    break
  fi
  sleep 30
done
```

### Phase 3: Addon Updates

#### 3.1 Update Core Addons
```bash
# Update kube-proxy
terraform apply -target=aws_eks_addon.kube_proxy

# Update CoreDNS
terraform apply -target=aws_eks_addon.core_dns

# Update EBS CSI Driver
terraform apply -target=aws_eks_addon.aws_ebs_csi_driver
```

#### 3.2 Verify Addon Updates
```bash
# Check addon versions
aws eks list-addons --cluster-name digit-sandbox --region ap-south-1

# Get detailed addon info
aws eks describe-addon --cluster-name digit-sandbox --addon-name kube-proxy --region ap-south-1
aws eks describe-addon --cluster-name digit-sandbox --addon-name coredns --region ap-south-1
aws eks describe-addon --cluster-name digit-sandbox --addon-name aws-ebs-csi-driver --region ap-south-1
```

### Phase 4: Node Group Upgrade

#### 4.1 Update Node Group
```bash
# Apply node group upgrade
terraform apply -target=module.eks_managed_node_group.aws_eks_node_group.this[0]
```

#### 4.2 Monitor Node Group Upgrade
```bash
# Monitor node group status
while true; do
  STATUS=$(aws eks describe-nodegroup --cluster-name digit-sandbox --nodegroup-name digit-sandbox-ng-20240827085244645600000015 --region ap-south-1 --query 'nodegroup.status' --output text)
  echo "Node group status: $STATUS"
  if [ "$STATUS" = "ACTIVE" ]; then
    break
  fi
  sleep 60
done
```

### Phase 5: Final Configuration

#### 5.1 Apply Remaining Changes
```bash
# Apply all remaining changes
terraform apply
```

#### 5.2 Update kubeconfig
```bash
# Update kubeconfig
aws eks update-kubeconfig --region ap-south-1 --name digit-sandbox
```

### Phase 6: Verification

#### 6.1 Cluster Verification
```bash
# Check cluster version
kubectl version --short

# Check nodes
kubectl get nodes -o wide

# Check node versions
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}'
```

#### 6.2 System Components
```bash
# Check system pods
kubectl get pods -n kube-system

# Check addon pods specifically
kubectl get pods -n kube-system | grep -E "(coredns|kube-proxy|ebs-csi)"

# Check storage classes
kubectl get storageclass
```

#### 6.3 Application Health
```bash
# Check all pods
kubectl get pods --all-namespaces

# Check services
kubectl get services --all-namespaces

# Check events for any issues
kubectl get events --sort-by=.metadata.creationTimestamp | tail -20
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Node Group Stuck in UPDATING
**Solution:**
```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names eks-digit-sandbox-ng-*

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=digit-sandbox"
```

#### Issue 2: Pods Not Starting
**Solution:**
```bash
# Check pod logs
kubectl logs -n kube-system <pod-name>

# Check node conditions
kubectl describe nodes

# Check resource availability
kubectl top nodes
```

#### Issue 3: Addon Update Failures
**Solution:**
```bash
# Check addon status
aws eks describe-addon --cluster-name digit-sandbox --addon-name <addon-name> --region ap-south-1

# Force addon update if needed
aws eks update-addon --cluster-name digit-sandbox --addon-name <addon-name> --resolve-conflicts OVERWRITE --region ap-south-1
```

## Rollback Procedure

### If Upgrade Fails

#### 1. Immediate Assessment
```bash
# Check what's broken
kubectl get nodes
kubectl get pods --all-namespaces
aws eks describe-cluster --name digit-sandbox --region ap-south-1
```

#### 2. Rollback Options

**Option A: Terraform State Rollback**
```bash
# Restore from backup
cp -r backup-eks-upgrade-* current-backup/
# Restore previous terraform.tfstate if needed
```

**Option B: Manual Rollback**
```bash
# Note: Control plane cannot be downgraded
# Focus on fixing issues rather than rollback
# Contact AWS Support if control plane issues persist
```

## Post-Upgrade Tasks

### 1. Application Testing
- [ ] Test all critical applications
- [ ] Verify database connections
- [ ] Check API endpoints
- [ ] Validate ingress controllers

### 2. Performance Monitoring
- [ ] Monitor resource usage
- [ ] Check application response times
- [ ] Verify autoscaling behavior
- [ ] Monitor costs

### 3. Security Validation
- [ ] Verify RBAC permissions
- [ ] Check network policies
- [ ] Validate service accounts
- [ ] Review security groups

### 4. Documentation Updates
- [ ] Update runbooks
- [ ] Document any issues encountered
- [ ] Update monitoring dashboards
- [ ] Inform team of changes

## Important Notes

### Kubernetes 1.31 Changes
- Enhanced security features
- Improved resource management
- Better observability
- Check [official changelog](https://kubernetes.io/docs/setup/release/notes/) for details

### Best Practices
- Always test in staging first
- Monitor for 24-48 hours post-upgrade
- Keep backup of working configuration
- Document any custom configurations

### Support Contacts
- AWS Support: Create case if needed
- Internal escalation: Follow team procedures
- Emergency contacts: Have them ready

## Estimated Timeline
- **Preparation**: 30 minutes
- **Node Group Fix**: 15-30 minutes
- **Control Plane Upgrade**: 10-15 minutes
- **Addon Updates**: 5-10 minutes
- **Node Group Upgrade**: 20-30 minutes
- **Verification**: 15-20 minutes
- **Total**: 1.5-2 hours
