#!/bin/sh

# Strating Kafka connect

echo -e "Current file contents:\n $(cat /etc/hosts)"
echo "$DETECTED_IP $DETECTED_HOSTNAME" >> /etc/hosts
echo -e "\n\n\nUpdated file contents:\n $(cat /etc/hosts)"

echo $BROKERS $GROUP
sed -i "s/BROKERS/${BROKERS}/g" /opt/connect-distributed.properties
sed -i "s/GROUP/${GROUP}/g" /opt/connect-distributed.properties

# use IAM authentication instead
# sed -i "s/USERNAME/${USERNAME}/g" /opt/connect-distributed.properties
# sed -i "s/PASSWORD/${PASSWORD}/g" /opt/connect-distributed.properties

echo Starting Kafka connect

cd "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}/bin"
export KAFKA_OPTS="-javaagent:/opt/jmx_prometheus_javaagent-${JMX_AGENT_VERSION}.jar=3600:/opt/kafka-connect.yml"
./connect-distributed.sh /opt/connect-distributed.properties