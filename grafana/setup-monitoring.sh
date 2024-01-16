#setup env
LOC=$4
GRAFANA_LOC=$LOC/grafana
GRAFANA_DASHBOARDS_JSON_LOC=/var/lib/grafana/dashboards
GRAFANA_CONF_LOC=/etc/grafana
GRAFANA_DATASOURCES_LOC=$GRAFANA_CONF_LOC/provisioning/datasources
GRAFANA_DASHBOARDS_LOC=$GRAFANA_CONF_LOC/provisioning/dashboards
cd $LOC

#update awscli
pip3 install --upgrade awscli --user

#install boto3 if not present
pip3 list|grep boto3 && [ $? -eq 0 ] && echo "boto3 module is already installed." || (echo "boto3 module missing. Installing it.." && pip3 install boto3 --user)
aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/setup-mon-env.py $LOC
python3 setup-mon-env.py --stackName $1 --region $2

if [ $? -ne 0 ]
then
    echo "Error encountered. Exiting"
    exit 1
fi

. ./setup_env

# Modify instance security groups to allow acess to prometheus and grafana dashboards
aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/modify-security-group.py $LOC
pip3 list|grep requests && [ $? -eq 0 ] && echo "requests module is already installed." || (echo "requests module missing. Installing it.." && pip3 install requests --user)
python3 modify-security-group.py --ip $3 --region $2

if [ $? -ne 0 ]
then
    echo "Error encountered. Exiting"
    exit 1
fi

# Setup prometheus
cd $LOC
(cat /etc/os-release|grep 'VERSION="2"' &&  [ $? -eq 0 ]) && ((sudo systemctl status prometheus && [ $? -eq 0 ]) && (echo "prometheus is running. Stopping it.." && sudo systemctl stop prometheus) || echo "prometheus is already stopped.")
(cat /etc/os-release|grep 'VERSION="2018.03"' &&  [ $? -eq 0 ]) && ((sudo service prometheus status|grep running && [ $? -eq 0 ]) && (echo "prometheus is running. Stopping it.." && sudo service prometheus stop) || echo "prometheus is already stopped.")
#sudo service prometheus status|grep running && [ $? -eq 0 ] && echo "prometheus is running. Stopping it.." && sudo service prometheus stop || echo "prometheus is already stopped."
[ -d "${LOC}/prometheus" ] && rm -r $LOC/prometheus
mkdir prometheus && cd prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.18.1/prometheus-2.18.1.linux-amd64.tar.gz
tar -xzf prometheus-2.18.1.linux-amd64.tar.gz --strip 1
cp prometheus.yml prometheus.yml_bkup
[ -d "/var/log/prometheus" ] && sudo rm -r /var/log/prometheus
sudo mkdir /var/log/prometheus/
sudo chown -R ec2-user:ec2-user /var/log/prometheus

echo -n "
  - job_name: 'kafka-connect'
    static_configs:
      - targets:
        - '${KafkaClientEC2Instance1}:3600'
        - '${KafkaClientEC2Instance2}:3500'
  - job_name: 'kafka-producer-consumer-${KafkaClientEC2Instance1}'
    static_configs:
      - targets:
        - '${KafkaClientEC2Instance1}:3800'
        - '${KafkaClientEC2Instance1}:3900'" >> prometheus.yml


# Setup Grafana
cd $LOC
(cat /etc/os-release|grep 'VERSION="2"' &&  [ $? -eq 0 ]) && ((sudo systemctl status grafana-server && [ $? -eq 0 ]) && (echo "grafana is running. Stopping it.." && sudo systemctl stop grafana-server) || echo "grafana is already stopped.")
(cat /etc/os-release|grep 'VERSION="2018.03"' &&  [ $? -eq 0 ]) && ((sudo service grafana-server status|grep running && [ $? -eq 0 ]) && (echo "grafana is running. Stopping it.." && sudo service grafana-server stop) || echo "grafana is already stopped.")
sudo yum list grafana && [ $? -eq 0 ] && echo "grafana is installed. Cleaning up.." && sudo yum erase grafana -y || echo "grafana not installed."
[ -d "${LOC}/grafana" ] && rm -r $LOC/grafana
[ -d "/var/lib/grafana" ] && sudo rm -r /var/lib/grafana
[ -d "/var/log/grafana" ] && sudo rm -r /var/log/grafana
mkdir grafana && cd grafana
wget https://dl.grafana.com/oss/release/grafana-7.0.1-1.x86_64.rpm
sudo yum install grafana-7.0.1-1.x86_64.rpm -y
sudo usermod -a -G grafana ec2-user
sudo usermod -a -G ec2-user grafana

# Setup grafana datasource
sudo cat > prometheus.yml<<EOF
datasources:
-  access: 'proxy'  
   editable: true 
   is_default: true   
   name: 'prometheus1'
   org_id: 1  
   type: 'prometheus'
   url: 'http://localhost:9090'
   version: 1
EOF
sudo mv prometheus.yml $GRAFANA_DATASOURCES_LOC
sudo chown grafana:grafana $GRAFANA_DATASOURCES_LOC/prometheus.yml

# Setup grafana dashboards
sudo mkdir -p $GRAFANA_DASHBOARDS_JSON_LOC
aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/MM2-dashboard-1.json $GRAFANA_LOC
sudo mv $GRAFANA_LOC/MM2-dashboard-1.json $GRAFANA_DASHBOARDS_JSON_LOC
sudo chown -R grafana:grafana $GRAFANA_DASHBOARDS_JSON_LOC
sudo cat > prometheus.yml<<EOF
apiVersion: 1

providers:
- name: 'AWSMM2'
  orgId: 1
  folder: 'MirrorMaker2'
  folderUid: ''
  type: file
  options:
    path: ${GRAFANA_DASHBOARDS_JSON_LOC}
EOF

sudo mv prometheus.yml $GRAFANA_DASHBOARDS_LOC
sudo chown grafana:grafana $GRAFANA_DASHBOARDS_LOC/prometheus.yml

#Setup services
if [ `cat /etc/os-release|grep 'VERSION='` == 'VERSION="2"' ]
then
sudo systemctl daemon-reload
sudo systemctl start grafana-server.service
sudo systemctl status grafana-server.service
sudo systemctl enable grafana-server

# Setup unit in systemd for Prometheus
sudo echo -n "
[Unit]
Description=Prometheus
After=network.target
[Service]
Type=simple
User=root
ExecStart=/bin/sh -c ${LOC}/prometheus/prometheus --config.file=${LOC}/prometheus/prometheus.yml > /var/log/prometheus.log 2>&1'
Restart=on-abnorm
[Install]
WantedBy=multi-user.target" > prometheus.service

sudo mv prometheus.service /etc/systemd/system/prometheus.service && sudo systemctl daemon-reload && sudo systemctl start prometheus.service && sudo systemctl status prometheus.service && sudo systemctl enable prometheus.service

elif [ `cat /etc/os-release|grep 'VERSION='` == 'VERSION="2018.03"' ]
then
sudo service grafana-server start
sudo service grafana-server status
sudo /sbin/chkconfig --add grafana-server
touch /var/log/prometheus/prometheus.log
sudo cat > initprometheus<<EOF
#!/bin/bash
# description: prometheus
# Source function library.
. /etc/rc.d/init.d/functions
PROGNAME=prometheus
PROGDIR=${LOC}/prometheus
PROG=\$PROGDIR/\$PROGNAME
USER=ec2-user
LOGFILE=/var/log/prometheus/\$PROGNAME.log
LOCKFILE=/var/run/\$PROGNAME.pid
start() {
echo -n "Starting \$PROGNAME: "
cd \$PROGDIR
daemon --user \$USER --pidfile="\$LOCKFILE" "\$PROG &>\$LOGFILE &"
echo \$(pidofproc \$PROGNAME) >\$LOCKFILE
echo
}
stop() {
echo -n "Shutting down \$PROGNAME: "
killproc \$PROGNAME
rm -f \$LOCKFILE
echo
}
case "\$1" in
start)
start
;;
stop)
stop
;;
status)
status \$PROGNAME
;;
restart)
stop
start
;;
*)
echo "Usage: service \$PROGNAME {start|stop|status|restart}"
exit 1
;;
esac

EOF

sudo mv initprometheus /etc/init.d/prometheus
sudo chmod +x /etc/init.d/prometheus
sudo chown ec2-user:ec2-user /etc/init.d/prometheus
sudo service prometheus start
sudo service prometheus status
fi


