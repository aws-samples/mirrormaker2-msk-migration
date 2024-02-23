#!/bin/sh

# Strating prometheus

echo -e "Current file contents:\n $(cat /etc/prometheus/targets.json)"

echo -e "JMX Exporter DNS List: ${JMX_EXPORTER_BROKER_LIST}"
echo -e "Node Exporter DNS List: ${NODE_EXPORTER_BROKER_LIST}"

sed -i "s/JMX_EXPORTER_BROKER_LIST/${JMX_EXPORTER_BROKER_LIST}/g" /etc/prometheus/targets.json
sed -i "s/NODE_EXPORTER_BROKER_LIST/${NODE_EXPORTER_BROKER_LIST}/g" /etc/prometheus/targets.json

echo -e "Updated file contents:\n $(cat /etc/prometheus/targets.json)"
echo Starting Kafka connect

/bin/prometheus --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --web.console.libraries=/usr/share/prometheus/console_libraries \
    --web.console.templates=/usr/share/prometheus/consoles