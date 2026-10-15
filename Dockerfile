FROM public.ecr.aws/amazonlinux/amazonlinux:2

RUN yum install -y wget tar openssh-server openssh-clients sysstat sudo which openssl hostname
RUN yum install -y java-17-amazon-corretto java-17-amazon-corretto-devel
RUN yum install -y jq &&\
    yum install -y nmap-ncat git
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH=$JAVA_HOME/bin:$PATH

# Verify Java installation
RUN java -version && javac -version

# First install required dependencies
RUN yum groupinstall -y "Development Tools" && \
    yum install -y gcc openssl-devel bzip2-devel libffi-devel zlib-devel make

# Maven
RUN yum install -y maven

ENV SCALA_VERSION 2.13
ENV KAFKA_VERSION 3.7.0
ENV MSK_IAM_AUTH_VERSION 2.3.0
ENV JMX_AGENT_VERSION 1.0.1

RUN yum -y update && yum -y install tar gzip wget

# SHA-512 of kafka_2.13-3.7.0.tgz from https://archive.apache.org/dist/kafka/3.7.0/kafka_2.13-3.7.0.tgz.sha512
ARG KAFKA_SHA512=b8679283a2d8dab86e7c636b2c688fe9d9e64ac437241f65ef7a1733f4d26a2bd415eefa04f09f1911373bcd2a5dbc3838c76347f68656425c09202cd290ce91
RUN curl -fsSL -o /tmp/kafka.tgz "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" && \
    echo "${KAFKA_SHA512}  /tmp/kafka.tgz" | sha512sum -c - && \
    tar -zx -C /opt -f /tmp/kafka.tgz && \
    rm /tmp/kafka.tgz

RUN wget "https://github.com/aws/aws-msk-iam-auth/releases/download/v${MSK_IAM_AUTH_VERSION}/aws-msk-iam-auth-${MSK_IAM_AUTH_VERSION}-all.jar"
RUN mv "aws-msk-iam-auth-${MSK_IAM_AUTH_VERSION}-all.jar" "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}/libs/"

# Prometheus Java agent
RUN wget "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_AGENT_VERSION}/jmx_prometheus_javaagent-${JMX_AGENT_VERSION}.jar"
RUN mv "jmx_prometheus_javaagent-${JMX_AGENT_VERSION}.jar" /opt
ADD kafka-connect.yml /opt/kafka-connect.yml

RUN mkdir mirrormaker2-msk-migration
WORKDIR mirrormaker2-msk-migration
ADD CustomMM2ReplicationPolicy/ ./CustomMM2ReplicationPolicy/
WORKDIR ./CustomMM2ReplicationPolicy
RUN mvn clean install

# # Initialize the Kafka cert trust store
RUN find -L /usr/lib/jvm/ -name "cacerts" -exec cp {} /tmp/kafka.client.truststore.jks \;

# # Add worker config file
ARG AUTH=iam
ADD "Configuration/workers/${AUTH}/connect-distributed.properties" /opt/connect-distributed.properties

RUN mv target/CustomMM2ReplicationPolicy-1.0-SNAPSHOT.jar "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}/libs"

# include all start scripts
ADD start-kafka-connect.sh /opt/start-kafka-connect.sh
RUN mkdir -p /opt/logs
RUN chmod 777 /opt/start-kafka-connect.sh

# cleanup
RUN yum clean all;

EXPOSE 8083
USER root
ENTRYPOINT /opt/start-kafka-connect.sh