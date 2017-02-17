#!/bin/bash

# Create namespaces
kubectl create -f definitions/cluster/egov-namespaces.yml

# Create services
kubectl create -f definitions/cluster/web/services
kubectl create -f definitions/cluster/backbone/services
kubectl create -f definitions/cluster/common/services
kubectl create -f definitions/cluster/pgr/services

# Create persistent-volumes and persisten-volume-claims
kubectl create -f definitions/cluster/common/volumes
kubectl create -f definitions/cluster/common/volume_claims

# Create deployments
kubectl create -f definitions/cluster/web/deployments
kubectl create -f definitions/cluster/backbone/deployments
kubectl create -f definitions/cluster/common/deployments
kubectl create -f definitions/cluster/pgr/deployments