#!/bin/sh
set -e

echo "setting hadoop/hbase configuration for this host"
sed -i "s/{{HOST}}/`hostname`/g" $HADOOP_HOME/etc/hadoop/core-site.xml
sed -i "s/{{HOST}}/`hostname`/g" $HBASE_HOME/conf/hbase-site.xml

echo "deploying a public ssh key from localhost"
cat /mnt/ssh/id_rsa.pub >> /root/.ssh/authorized_keys

echo "starting services"
service ssh start
hdfs namenode -format
start-dfs.sh
start-yarn.sh
start-hbase.sh

echo "populating Phoenix with test data"
psql.py -t SRC_SCHEMA.SRC_TABLE /phoenix.sql /phoenix.csv

tail -f /dev/null