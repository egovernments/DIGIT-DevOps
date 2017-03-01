#!/bin/bash

echo "Configuring Zookeeper"
kubectl apply -f app/zookeeper.yml

echo "Configuring Redis"
kubectl apply -f app/redis.yml

echo "Configuring Postgres"
kubectl apply -f app/postgres.yml

echo "Waiting dumbly for 10 secs, to let zookeeper come up. This is should be an intelligent wait in future"
sleep 10
echo "Configuring Kafka"
kubectl apply -f app/kafka.yml

echo "Check your CPU and RAM usage. If its spiking, wait for it to come down."
read -p "Press enter to continue"

for i in core-eis-filestore-localization core-location-user-workflow pgr-crn-employee-location pgr-rest-persist-search
do
    echo "Configuring $i"
    kubectl apply -f app/$i.yml
    echo "Check your CPU and RAM usage. Don't panic. Continue when its down"
    read -p "Press enter to continue"
done

echo "Dev box configured. Wait for a while for CPU to cool down and then start using it"
