#!/bin/bash

for n in ( core, pgr, lams, logging, es-cluster, default );do
kubectl delete svc,deployments,pvc,pv,configMaps,statefulset,ds,secret,rc --all --namespace=$n
done