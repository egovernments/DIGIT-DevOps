#!/bin/bash

# Create namespaces
kubectl create -f definitions/cluster/egov-namespaces.yml

# Create apps in all namespaces
kubectl create -f definitions/cluster/app/backbone
kubectl create -f definitions/cluster/app/web
kubectl create -f definitions/cluster/app/common
kubectl create -f definitions/cluster/app/pgr