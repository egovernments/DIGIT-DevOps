# EKS Upgrade Checklist: 1.30 → 1.31

## Pre-Upgrade Checklist

### 1. Backup and Preparation ✅
- [x] Configuration backup created
- [ ] Application data backup completed
- [ ] Document current addon versions
- [ ] Verify kubectl version compatibility (should be ±1 minor version)

### 2. Application Compatibility
- [ ] Review application logs for deprecation warnings
- [ ] Test applications in a staging environment with K8s 1.31
- [ ] Check for any custom resources using deprecated APIs
- [ ] Verify Helm charts compatibility with K8s 1.31

### 3. Infrastructure Checks
- [ ] Ensure sufficient capacity for rolling updates
- [ ] Check AWS service quotas
- [ ] Verify IAM permissions for EKS operations
- [ ] Confirm network connectivity and security groups

### 4. Monitoring Setup
- [ ] Set up monitoring for the upgrade process
- [ ] Prepare alerting for any issues
- [ ] Have rollback plan ready

## Upgrade Process

### Phase 1: Control Plane Upgrade
1. Update Terraform configuration (✅ Done)
2. Run `terraform plan` to review changes
3. Apply changes with `terraform apply`
4. Wait for control plane to be ACTIVE

### Phase 2: Node Group Upgrade
1. Node groups will be updated automatically
2. Nodes will be replaced with new AMI
3. Wait for all nodes to be ready

### Phase 3: Addon Updates
1. Addons will be updated to compatible versions
2. Verify addon functionality

## Post-Upgrade Verification

### Cluster Health
- [ ] Cluster status is ACTIVE
- [ ] All nodes are Ready
- [ ] All system pods are Running
- [ ] Addons are functioning correctly

### Application Health
- [ ] All application pods are Running
- [ ] Services are accessible
- [ ] Ingress controllers working
- [ ] Persistent volumes mounted correctly

### Performance Checks
- [ ] Resource utilization normal
- [ ] Network connectivity working
- [ ] DNS resolution functioning
- [ ] Storage operations working

## Rollback Plan

If issues occur during upgrade:

1. **Immediate Actions:**
   ```bash
   # Check cluster status
   aws eks describe-cluster --name digit-sandbox --region ap-south-1
   
   # Check node status
   kubectl get nodes
   
   # Check pod status
   kubectl get pods --all-namespaces
   ```

2. **Rollback Options:**
   - Restore from backup configuration
   - Use previous Terraform state
   - Contact AWS support if control plane issues

3. **Emergency Contacts:**
   - AWS Support case
   - Team escalation procedures

## Important Notes

- **Downtime**: Minimal downtime expected (5-10 minutes)
- **Duration**: Total upgrade time: 30-45 minutes
- **Monitoring**: Monitor for 24 hours post-upgrade
- **Testing**: Perform thorough application testing

## Kubernetes 1.31 Changes

### New Features
- Enhanced security features
- Improved performance
- Better resource management

### Deprecated Features
- Check [Kubernetes 1.31 changelog](https://kubernetes.io/docs/setup/release/notes/) for details

### Breaking Changes
- Review API version changes
- Check for removed features

## Commands for Verification

```bash
# Check cluster version
kubectl version --short

# Check node versions
kubectl get nodes -o wide

# Check addon versions
aws eks list-addons --cluster-name digit-sandbox --region ap-south-1

# Check system pods
kubectl get pods -n kube-system

# Check application pods
kubectl get pods --all-namespaces

# Check events for any issues
kubectl get events --sort-by=.metadata.creationTimestamp
```
