#!/bin/bash
# Custom user data script for AL2023 nodes

# Set max pods to 40
echo "Setting maxPods to 40..."
/etc/eks/bootstrap.sh unified-dev --kubelet-extra-args "--max-pods=40"