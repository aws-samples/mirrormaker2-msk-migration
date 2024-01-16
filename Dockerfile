FROM centos:latest

RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

RUN yum install -y wget tar openssh-server openssh-clients sysstat sudo which openssl hostname
RUN yum install -y java-1.8.0-openjdk-devel
RUN yum install -y epel-release &&\
    yum install -y jq &&\
    yum install -y python38 &&\
    yum install -y nmap-ncat git

ARG MAVEN_VERSION=3.5.4
ARG AUTH=iam

# Maven
RUN curl -fsSL https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar xzf - -C /usr/share \
  && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV M2_HOME /usr/share/maven
ENV maven.home $M2_HOME
ENV M2 $M2_HOME/bin
ENV PATH $M2:$PATH


RUN wget https://bootstrap.pypa.io/get-pip.py
RUN python3 get-pip.py
RUN pip3 install awscli

ENV SCALA_VERSION 2.13
ENV KAFKA_VERSION 2.7.0

RUN yum -y update && yum -y install tar gzip wget
RUN curl https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz | tar -zx -C /opt

RUN wget https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.6/aws-msk-iam-auth-1.1.6-all.jar
RUN mv aws-msk-iam-auth-1.1.6-all.jar /opt/kafka_2.13-2.7.0/libs

# Prometheus Java agent
RUN wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.13.0/jmx_prometheus_javaagent-0.13.0.jar
RUN mv jmx_prometheus_javaagent-0.13.0.jar /opt
ADD kafka-connect.yml /opt/kafka-connect.yml

RUN git clone https://github.com/aws-samples/mirrormaker2-msk-migration.git
WORKDIR mirrormaker2-msk-migration/CustomMM2ReplicationPolicy
RUN mvn clean install

# # Initialize the Kafka cert trust store
RUN find /usr/lib/jvm/ -name "cacerts" -exec cp {} /tmp/kafka.client.truststore.jks \;


ADD Configuration/workers/${AUTH}/connect-distributed.properties /opt/connect-distributed.properties


RUN mv target/CustomMM2ReplicationPolicy-1.0-SNAPSHOT.jar /opt/kafka_2.13-2.7.0/libs

# include all start scripts
ADD start-kafka-connect.sh /opt/start-kafka-connect.sh
RUN mkdir -p /opt/logs
RUN chmod 777 /opt/start-kafka-connect.sh

# cleanup
RUN yum clean all;

EXPOSE 8083
USER root
ENTRYPOINT /opt/start-kafka-connect.sh