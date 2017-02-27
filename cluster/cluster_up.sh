#!/bin/bash

# Create namespaces
kubectl apply -f egov-namespaces.yml

# Create add-ons
kubectl apply -f addons/fluentd-elasticsearch-logging

# Create configs
kubectl apply -f configMaps/qa

# Create persistent volumes
kubectl apply -f volume/qa

# Create apps in all namespaces
kubectl apply -f app/backbone
kubectl apply -f app/core
kubectl apply -f app/pgr
kubectl apply -f app/lams
kubectl apply -f app/elasticsearch