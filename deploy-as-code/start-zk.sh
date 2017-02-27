sed -i -r s|#(log4j.appender.ROLLINGFILE.MaxBackupIndex.*)|\1|g $ZK_HOME/conf/log4j.properties \nsed -i -r s|#autopurge|autopurge|g $ZK_HOME/conf/zoo.cfg\n\n$ZK_HOME/bin/zkServer.sh start-foreground
