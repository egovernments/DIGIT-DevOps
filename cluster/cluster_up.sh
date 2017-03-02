#!/bin/bash

env_arr=(dev qa)
env=$1
usage(){
    echo "./cluster_up.sh <env>"
    echo "Ex: ./cluster_up.sh dev|qa|prod"
}

is_valid_env(){
    local env=$1
    local result=1;
    for e in ${env_arr[@]};
    do
        if [[ $e == $env ]];then
            result=0
            break
        fi
    done
    return $result
}

if [[ -z "$env" ]];then
    echo "ERROR: Environment is a must"
    usage
    exit 1
fi

is_valid_env "$env" && echo "" || ( echo "Invalid environment $env" && exit 1)

echo "Switching context to $env"
kubectl config use-context $env

if [[ $? != "0" ]];then
    echo "No context called $env exists in your kubectl config."
    echo "Please set the required context before proceeding further."
    exit 1
fi

echo "Configuring namespaces"
kubectl apply -f egov-namespaces.yml

if [[ $env != "dev"]];then
    echo "Configuring logging infrastucture"
    kubectl apply -f addons/fluentd-elasticsearch-logging
fi

echo "Creating $env specific configurations."
kubectl apply -f $env

echo "Configuring all modules apps"
kubectl apply -R -f app