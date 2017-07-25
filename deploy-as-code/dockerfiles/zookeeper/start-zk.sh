sed -i -r 's|#(log4j.appender.ROLLINGFILE.MaxBackupIndex.*)|\1|g' $ZK_HOME/conf/log4j.properties
sed -i -r 's|#autopurge|autopurge|g' $ZK_HOME/conf/zoo.cfg

# Put the pod's ordinal id + 1 to myid file in datadir (kubernetes ordinal starts from 0.
# Zookeeper quorum member id should be between 1 and 255)
IFS='- ' read -r -a array <<< "$HOSTNAME"
ORDINAL=${array[1]}
expr $ORDINAL + 1 > /opt/zookeeper/data/myid

# copy config mounted externally
cp /opt/zookeeper-conf/zoo.cfg /opt/zookeeper/conf/zoo.cfg

if [ $(hostname -s) = 'zookeeper-0' ]; then
  sed -i -r 's|server.1=zookeeper-0.zookeeper:2888:3888|server.1=0.0.0.0:2888:3888|g' /opt/zookeeper/conf/zoo.cfg
elif [ $(hostname -s) = 'zookeeper-1' ]; then
  sed -i -r 's|server.2=zookeeper-1.zookeeper:2888:3888|server.2=0.0.0.0:2888:3888|g' /opt/zookeeper/conf/zoo.cfg
elif [ $(hostname -s) = 'zookeeper-2' ]; then
  sed -i -r 's|server.3=zookeeper-2.zookeeper:2888:3888|server.3=0.0.0.0:2888:3888|g' /opt/zookeeper/conf/zoo.cfg
fi

/opt/zookeeper/bin/zkServer.sh start-foreground
