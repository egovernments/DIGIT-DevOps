#!/bin/bash

kubectl delete svc,deployments,pvc,pv,configMaps,statefulset,ds,secret,rc --all --namespace=default