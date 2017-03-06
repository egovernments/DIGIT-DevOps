#!/bin/bash


if [[ -z "$START_TIMEOUT" ]]; then
    START_TIMEOUT=600
fi

start_timeout_exceeded=false
count=0
step=10

IFS=', ' read -r -a brokers <<< "${KAFKA_BROKERS}"
for broker in ${brokers[@]};
do
    host=${broker%:*}
    port=${broker#*:}
    exit_cmd=1
    until nc -zv $host $port; do
        if [ $count -gt $START_TIMEOUT ]; then
            start_timeout_exceeded=true
            break
        fi
    done
done


if $start_timeout_exceeded; then
    echo "Not able to auto-create topic (waited for $START_TIMEOUT sec)"
    exit 1
fi

if [[ -n $KAFKA_CREATE_TOPICS ]]; then
    IFS=','; for topicToCreate in $KAFKA_CREATE_TOPICS; do
        echo "creating topics: $topicToCreate"
        IFS=':' read -a topicConfig <<< "$topicToCreate"
        existing_topics=`$KAFKA_HOME/bin/kafka-topics.sh --zookeeper $KAFKA_ZOOKEEPER_CONNECT --list`
        topic_to_be_created=${topicConfig[0]}
        if [[ ${existing_topics} == *${topic_to_be_created}* ]];then
            echo "Topid ${topicConfig[0]} already exists"
        else
            if [ ${topicConfig[3]} ]; then
                JMX_PORT='' $KAFKA_HOME/bin/kafka-topics.sh --create --zookeeper $KAFKA_ZOOKEEPER_CONNECT --replication-factor ${topicConfig[2]} --partition ${topicConfig[1]} --topic "${topicConfig[0]}" --config cleanup.policy="${topicConfig[3]}"
            else
                JMX_PORT='' $KAFKA_HOME/bin/kafka-topics.sh --create --zookeeper $KAFKA_ZOOKEEPER_CONNECT --replication-factor ${topicConfig[2]} --partition ${topicConfig[1]} --topic "${topicConfig[0]}"
            fi
        fi
    done
fi