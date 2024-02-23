FROM prom/prometheus

EXPOSE 9090
ADD prometheus.yaml /etc/prometheus/prometheus.yml
ADD start-prometheus.sh /etc/prometheus/start-prometheus.sh
ADD targets.json /etc/prometheus/targets.json

USER root

RUN chmod 777 /etc/prometheus/start-prometheus.sh
ENTRYPOINT /etc/prometheus/start-prometheus.sh
