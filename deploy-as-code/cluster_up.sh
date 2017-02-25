#!/bin/bash

# Create namespaces
kubectl apply -f definitions/cluster/egov-namespaces.yml

# Create add-ons
kubectl apply -f definitions/cluster/addons/fluentd-elasticsearch-logging

# Create persistent volumes
kubectl apply -f definitions/cluster/volume

# Create apps in all namespaces
kubectl apply -f definitions/cluster/app/backbone
kubectl apply -f definitions/cluster/app/core
kubectl apply -f definitions/cluster/app/pgr
kubectl apply -f definitions/cluster/app/lams
kubectl apply -f definitions/cluster/app/elasticsearch