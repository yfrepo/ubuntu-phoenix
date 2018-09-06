# Docker image for Standalone HBase/Phoenix
# based on Ubuntu
FROM ubuntu
 
# Tools' versions
ARG HADOOP_VERSION=2.9.1
ARG HBASE_VERSION=1.2.6
ARG PHOENIX_VERSION=4.13.1-HBase-1.2

# Repository links
ARG REPOSITORY=http://archive.apache.org/dist
ARG HADOOP_DOWNLOAD_LINK=$REPOSITORY/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz
ARG HBASE_DOWNLOAD_LINK=$REPOSITORY/hbase/$HBASE_VERSION/hbase-$HBASE_VERSION-bin.tar.gz
ARG PHOENIX_DOWNLOAD_LINK=$REPOSITORY/phoenix/apache-phoenix-$PHOENIX_VERSION/bin/apache-phoenix-$PHOENIX_VERSION-bin.tar.gz

# Tools' home dirs
ARG HADOOP_DIR=/hadoop
ARG HBASE_DIR=/hbase
ARG PHOENIX_DIR=/apache-phoenix

#------------------------
# initial steps
RUN apt-get update \
    && apt-get install sudo curl ssh rsync python openjdk-8-jdk -y
 
#-------------------------
# ssh configuration
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa \
    && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys \
    && chmod 0600 ~/.ssh/authorized_keys \
	&& echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config 
 
#------------------------
# java configuration
RUN { \
        echo '#!/bin/sh'; \
        echo 'set -e'; \
        echo; \
        echo 'export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))'; \
    } > /etc/profile.d/java.sh \
    && chmod +x /etc/profile.d/java.sh
     
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV PATH $PATH:$JAVA_HOME/bin

#------------------------
# hadoop steps
ENV HADOOP_HOME $HADOOP_DIR
ENV PATH $PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

RUN set -x \
    && mkdir $HADOOP_HOME \
    && curl "$HADOOP_DOWNLOAD_LINK" | tar -xz -C $HADOOP_HOME --strip-components 1

RUN { \
        echo '#!/bin/sh'; \
        echo 'set -e'; \
        echo; \
        echo 'export HADOOP_HOME='$HADOOP_HOME; \
		echo 'export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin'; \
    } > /etc/profile.d/hadoop.sh \
    && chmod +x /etc/profile.d/hadoop.sh \
    # remove redundant docs from hadoop
    && rm -rf $HADOOP_HOME/share/doc

COPY conf/hadoop-env.sh $HADOOP_HOME/etc/hadoop/hadoop-env.sh
COPY conf/core-site.xml $HADOOP_HOME/etc/hadoop/core-site.xml
COPY conf/hdfs-site.xml $HADOOP_HOME/etc/hadoop/hdfs-site.xml	
COPY conf/mapred-site.xml $HADOOP_HOME/etc/hadoop/mapred-site.xml
COPY conf/yarn-site.xml $HADOOP_HOME/etc/hadoop/yarn-site.xml

#------------------------
# hbase steps
ENV HBASE_HOME $HBASE_DIR
ENV PATH $PATH:$HBASE_HOME/bin
 
RUN set -x \
    && mkdir $HBASE_HOME \
    && curl "$HBASE_DOWNLOAD_LINK" | tar -xz -C $HBASE_HOME --strip-components 1 \
    # remove redundant docs from hbase dir
    && rm -rf $HBASE_HOME/docs

RUN { \
        echo '#!/bin/sh'; \
        echo 'set -e'; \
        echo; \
        echo 'export HBASE_HOME='$HBASE_HOME; \
		echo 'export PATH=$PATH:$HBASE_HOME/bin'; \
    } > /etc/profile.d/hbase.sh \
    && chmod +x /etc/profile.d/hbase.sh	
     
COPY conf/hbase-env.sh $HBASE_HOME/conf/hbase-env.sh	 
COPY conf/hbase-site.xml $HBASE_HOME/conf/hbase-site.xml

#-----------------------
# phoenix steps
ENV PHOENIX_HOME $PHOENIX_DIR
ENV PATH $PATH:$PHOENIX_HOME/bin

RUN set -x \
    && mkdir $PHOENIX_HOME \
    && curl "$PHOENIX_DOWNLOAD_LINK" | tar -xz -C $PHOENIX_HOME --strip-components 1 \
    && cp \
         $PHOENIX_HOME/phoenix-$PHOENIX_VERSION-server.jar \
         $PHOENIX_HOME/phoenix-core-$PHOENIX_VERSION.jar \
       # to
       $HBASE_HOME/lib/ \
    && ln -s $PHOENIX_HOME/bin/sqlline.py /bin/phoenix-sqlline
    # remove redundant jars from $PHOENIX_HOME/ such as hive, pig, kafka; remove $PHOENIX_HOME/examples/
	# rm -rf PHOENIX_HOME/...

RUN { \
        echo '#!/bin/sh'; \
        echo 'set -e'; \
        echo; \
        echo 'export PHOENIX_HOME='$PHOENIX_HOME; \
		echo 'export PATH=$PATH:$PHOENIX_HOME/bin'; \
    } > /etc/profile.d/phoenix.sh \
    && chmod +x /etc/profile.d/phoenix.sh
	   
COPY conf/hbase-site-sqlline.xml $PHOENIX_HOME/bin/hbase-site.xml
COPY data/phoenix.sql /phoenix.sql
COPY data/phoenix.csv /phoenix.csv

#----------------------
# add users
RUN useradd -m hbase && adduser hbase sudo
RUN echo "hbase ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN useradd -m hdfs && adduser hdfs sudo
RUN echo "hdfs ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
 
#----------------------
EXPOSE 22 2181 2888 3888 8020 8080 8085 8088 9090 9095 16010 34110 50070 60000 60010 60020 60030

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
# throws the error: standard_init_linux.go:190: exec user process caused "no such file or directory"
#ENTRYPOINT ["/docker-entrypoint.sh"]
ENTRYPOINT sed -i "s/{{HOST}}/`hostname`/g" $HADOOP_HOME/etc/hadoop/core-site.xml \
           && sed -i "s/{{HOST}}/`hostname`/g" $HBASE_HOME/conf/hbase-site.xml \
           # deploy public ssh key
           && cat /mnt/ssh/id_rsa.pub >> /root/.ssh/authorized_keys \
           # start services
           && service ssh start \
           && hdfs namenode -format \
           && start-dfs.sh \
           && start-yarn.sh \
           && start-hbase.sh \
           # populate phoenix table
           && psql.py -t SRC_SCHEMA.SRC_TABLE /phoenix.sql /phoenix.csv \
           && tail -f /dev/null
