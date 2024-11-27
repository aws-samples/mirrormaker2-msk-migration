#!/bin/sh

# Strating Kafka connect

echo -e "Current file contents:\n $(cat /etc/hosts)"
echo "$DETECTED_IP $DETECTED_HOSTNAME" >> /etc/hosts
echo -e "\n\n\nUpdated file contents:\n $(cat /etc/hosts)"

# Load custom config if provided
if [ ! -z "${KAFKA_CONNECT_PROPERTIES_S3_URI}" ]; then
    echo "Loading custom config from ${KAFKA_CONNECT_PROPERTIES_S3_URI}"
    aws s3 cp "${KAFKA_CONNECT_PROPERTIES_S3_URI}" /opt/connect-distributed.properties
fi

# Override common configurations
echo $BROKERS $GROUP
sed -i "s/BROKERS/${BROKERS}/g" /opt/connect-distributed.properties
sed -i "s/GROUP/${GROUP}/g" /opt/connect-distributed.properties

# For SASL/SCRAM auth
sed -i "s/USERNAME/${USERNAME}/g" /opt/connect-distributed.properties
sed -i "s/PASSWORD/${PASSWORD}/g" /opt/connect-distributed.properties
# For mTLS
# Load truststore/keystore if provided
if [ ! -z "${KAFKA_CONNECT_TRUSTSTORE_S3_URI}" ]; then
    echo "Loading truststore from ${KAFKA_CONNECT_TRUSTSTORE_S3_URI}"
    aws s3 cp "${KAFKA_CONNECT_TRUSTSTORE_S3_URI}" /tmp/kafka.client.truststore.jks
fi
if [ ! -z "${KAFKA_CONNECT_KEYSTORE_S3_URI}" ]; then
    echo "Loading keystore from ${KAFKA_CONNECT_KEYSTORE_S3_URI}"
    aws s3 cp "${KAFKA_CONNECT_KEYSTORE_S3_URI}" /tmp/kafka.client.keystore.jks
fi
sed -i "s/TRUSTSTORE_PASSWORD/${TRUSTSTORE_PASSWORD}/g" /opt/connect-distributed.properties
sed -i "s/KEYSTORE_PASSWORD/${KEYSTORE_PASSWORD}/g" /opt/connect-distributed.properties
sed -i "s/KEY_PASSWORD/${KEY_PASSWORD}/g" /opt/connect-distributed.properties

echo Starting Kafka connect

cd "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}/bin"
export KAFKA_OPTS="-javaagent:/opt/jmx_prometheus_javaagent-${JMX_AGENT_VERSION}.jar=3600:/opt/kafka-connect.yml"
./connect-distributed.sh /opt/connect-distributed.properties