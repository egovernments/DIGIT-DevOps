#!/bin/bash

for n in egov;
do
    kubectl delete svc,deployments,pvc,pv,configMaps,statefulset,ds,secret,rc --all --namespace=$n
done