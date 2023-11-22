This repository accompanies the [Amazon MSK migration lab](https://amazonmsk-labs.workshop.aws/en/migration.html). 
It includes resources used in the lab including AWS CloudFormation templates, configuration files and Java code.

## Overview

### Kafka Connect workers

Kafka Connect workers operate as a cluster to facilitate scalable and fault-tolerant data integration in Apache Kafka. In this setup, multiple Kafka Connect worker instances collaborate to distribute and parallelize the processing of connectors and tasks. Each worker in the cluster is responsible for executing a subset of connectors and their associated tasks, which are units of work responsible for moving data between Kafka and external systems. The workers share configuration information and coordinate through the Kafka broker to ensure a cohesive and balanced distribution of tasks across the cluster. This distributed architecture enables horizontal scaling, allowing the Kafka Connect cluster to handle increased workloads and provides resilience by redistributing tasks in the event of worker failures, thereby ensuring continuous and reliable data integration across connected systems.

### Kafka connect worker configuration file

The Kafka Connect worker configuration file is a crucial component in defining the behavior and settings of a Kafka Connect worker. This configuration file typically includes details such as the **Kafka bootstrap servers**, **group ID**, key and value **converters**, and specific connector configurations, allowing users to tailor the worker's behavior to their specific data integration requirements.

This code example provides different configuration files based on each authentication scheme. Refer to [Configuration/workers](Configuration/workers) to view these files. 

### Mirror Maker source connector configuration

This file typically includes details such as connection properties, topic configurations, and any additional settings required for extracting data from the source topics and publishing it to the target Kafka cluster. Users leverage this configuration file to tailor the source connector's behavior, ensuring seamless integration and effective data ingestion from the source to Kafka. Submitting the contents of this file via a POST or PUT REST Api for the first time, starts the source connector. Further calls will update the connector configuration and restart its tasks. MM2 source connector scale horizontally by increasing the value for `task.max` configuration.

This example provides distinct configuration files for each connector per each authentication scheme. Refer to [Configuration/connectors](Configuration/connectors) for more information.

## Build

### Clone the repository and install the jar file.  

    mvn clean install -f pom.xml
      
Two java jar files will be created:

#### CustomMM2ReplicationPolicy

This jar file is related to the use of [Kafka MirrorMaker2](https://cwiki.apache.org/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0) in the lab to migrate a self-managed Apache Kafka cluster 
to [Amazon MSK](https://aws.amazon.com/msk/). 

MirrorMaker v2 (MM2), which ships as part of Apache Kafka in version 2.4.0 and above, detects and 
replicates topics, topic partitions, topic configurations and topic ACLs to the destination cluster that matches a regex topic pattern. 
Further, it checks for new topics that matches the topic pattern or changes to configurations and ACLs at regular configurable intervals. 
The topic pattern can also be dynamically changed by changing the configuration of the MirrorSourceConnector. 
Therefore MM2 can be used to migrate topics and topic data to the destination cluster and keep them in sync.
                   
In order to differentiate topics between the source and destination, MM2 utilizes a **ReplicationPolicy**. 
The **DefaultReplicationPolicy** implementation uses a **\<source-cluster-alias\>.\<topic\>** naming convention as described 
in [KIP-382](https://cwiki.apachorg/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0#KIP-382:MirrorMaker2.0-RemoteTopics,Partitions).The consumer, 
when it starts up will subscribe to the replicated topic based on the topic pattern specified which should account for 
both the source topic and the replicated topic names. This behavior is designed to account for use cases which need to run multiple 
Apache Kafka clusters and keep them in sync for High Availability/Disaster Recovery and prevent circular replication of topics.

In migration scenarios, it might be useful to have the same topic names in the destination as the source as there is no 
failback requirement and the replication is only way from the self-managed Apache Kafka cluster to Amazon MSK. 
In order to enable that, the DefaultReplicationPolicy needs to be replaced with a CustomReplicationPolicy which would 
maintain the same topic name at the destination. This jar file needs to be copied into the **libs** directory of the 
Apache Kafka installation running MM2.

#### MM2GroupOffsetSync

When replicating messages in topics between clusters, the offsets in topic partitions could be different 
due to producer retries or more likely due to the fact that the retention period in the source topic could've passed 
and messages in the source topic already deleted when replication starts. Even if the the __consumer_offsets topic is replicated, 
the consumers, on failover, might not find the offsets at the destination.

MM2 provides a facility that keeps source and destination offsets in sync. The MM2 MirrorCheckpointConnector periodically 
emits checkpoints in the destination cluster, containing offsets for each consumer group in the source cluster. 
The connector periodically queries the source cluster for all committed offsets from all consumer groups, filters for 
topics being replicated, and emits a message to a topic like \<source-cluster-alias\>.checkpoints.internal in the destination cluster. 
These offsets can then be queried and retrieved by using provided classes **RemoteClusterUtils** or **MirrorClient**. However, 
in order for consumers to fail over seamlessly and start consuming from where they left off with no code changes, 
the mapped offsets at the destination need to be synced with the __consumer_offsets topic at the destination. The 
MM2GroupOffsetSync application performs this syncing periodically and checks to make sure that the consumer group is empty or dead 
before doing the sync to make sure that the offsets are not overwritten if the consumer had failed over.

The jar file accepts the following parameters:  

* **-h (or --help): help to get list of parameters**
* **-cgi (or --consumerGroupID) (Default mm2TestConsumer1)**: The Consumer Group ID of the consumer to sync offsets for.
* **-src (or --sourceCluster) (Default msksource)**: The alias of the source cluster specified in the MM2 configuration.
* **-pfp (or --propertiesFilePath) (Default /tmp/kafka/consumer.properties)**: Location of the producer properties file which contains information about the Apache Kafka bootstrap brokers and the location of the Confluent Schema Registry.
* **-mtls (or --mTLSEnable)(Default false)**: Enable TLS communication between this application and Amazon MSK Apache Kafka brokers for in-transit encryption and TLS mutual authentication. If this parameter is specified, TLS is also enabled. This reads the specified properties file for SSL_TRUSTSTORE_LOCATION_CONFIG, SSL_KEYSTORE_LOCATION_CONFIG, SSL_KEYSTORE_PASSWORD_CONFIG and SSL_KEY_PASSWORD_CONFIG. Those properties need to be specified in the properties file.
* **-ssl (or --sslEnable)(Default /tmp/kafka.client.keystore.jks)**: Enable TLS communication between this application and Amazon MSK Apache Kafka brokers for in-transit encryption.
* **-rpc (or --replicationPolicyClass)(Default DefaultReplicationPolicy)**: The class name of the replication policy to use. Works with the custom replication policy mentioned above.
* **-rps (or --replicationPolicySeparator)(Default ".")**: The separator to use with the DefaultReplicationPolicy between the source cluster alias and the topic name.
* **-int (or --interval)(Default 20)**: The interval in seconds between syncs.
* **-rf (or --runFor) (Optional)**: Number of seconds to run the producer for.
     
## Usage Examples

### To get the list of parameters

```
java -jar MM2GroupOffsetSync-1.0-SNAPSHOT.jar -h
```

### Using a custom ReplicationPolicy

```
java -jar MM2GroupOffsetSync-1.0-SNAPSHOT.jar -cgi mm2TestConsumer1 -src msksource -pfp /tmp/kafka/consumer.properties_sync_dest -mtls -rpc com.amazonaws.kafka.samples.CustomMM2ReplicationPolicy
```

### Using the DefaultReplicationPolicy

```
java -jar MM2GroupOffsetSync-1.0-SNAPSHOT.jar -cgi mm2TestConsumer1 -src msksource -pfp /tmp/kafka/consumer.properties_sync_dest -mtls
```

### Using Docker

```
docker build . -t kafka-connect-270:latest

docker run --rm -p 3600:3600 -e BROKERS=localhost:9092 -e GROUP=my-kafka-connect kafka-connect-270:latest
```

## Deploy


### Prerequisites

In this section, you learn how to deploy necessary docker images to your docker image repository. This code example as the following requirements:

* You are familiar with setting up Proxy to view websites hosted on the private networks. We suggest using FoxyProxy for this code example: [https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-connect-master-node-proxy.html](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-connect-master-node-proxy.html)

* An identity principle attached with a policy document for Amazon EC2, Amazon VPC, and Amazon ECS full access

* Amazon ECR as your container image repository

* Existing Amazon VPC with public and private subnets

* A source and target Amazon MSK in a same or different Amazon VPC. For Amazon MSK clusters in different Amazon VPCs, enable multi-VPC connectivity for the cluster and create a connectivity to Amazon MSK from the remote VPC

* An [Amazon ECS task execution IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html). This code example uses the following policies: (**It's a best practice to always use minimum required permissions for your environment**)

    - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    - arn:aws:iam::aws:policy/AmazonEC2FullAccess
    - arn:aws:iam::aws:policy/AmazonECS_FullAccess
    - arn:aws:iam::aws:policy/AmazonMSKFullAccess

* If you are using IAM authentication for connecting to Amazon MSK, find an example [Fargate/msk-iam-auth-inline-policy.json](Fargate/msk-iam-auth-inline-policy.json) inline policy

* If you want to use IAM authentication for Amazon MSK, attach the [required permissions](https://docs.aws.amazon.com/msk/latest/developerguide/security_iam_id-based-policy-examples.html) as a separate IAM policy document to your ECS task execution role

* Amazon EC2 bastion host with SSM or SSH connectivity from your local machine

### Push Kafka connect docker image to Amazon ECR

**Important**

1. Create a private Amazon ECR repository. [Creating a private repository](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-create.html)

2. Make sure docker engine is running on your development machine. 

3. Push `Kafka-Connect` docker image to your private repository:

    ```
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com

    # chose a value from these options: {iam, sasl, mtls, no-auth}
    docker build --build-arg="AUTH={Your preferred auth}" -t kafka-connect-distributed . 

    docker tag kafka-connect-distributed:latest {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest 

    docker push {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest
    ```

### Push Prometheus docker image to Amazon ECR

1. Create another ECR repository for Prometheus

2. Push `prometheus` docker image to your private repository:

    ```
    cd prometheus

    docker build -t prometheus .

    docker tag prometheus:latest {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest 

    docker push {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest
    ```

## Create an Amazon ECS cluster

The applications we are about to deploy need connectivity from your local machine. Depending on how you connect to your internal AWS resources the setup may vary. This code example assumes you're connection from the internet. For simplicity we use SSH tunnel via a local proxy. For more information about creating an SSH tunnel, see [Option 2, part 1: Set up an SSH tunnel to the primary node using dynamic port forwarding](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ssh-tunnel.html). 

Alternatively you can setup an internet facing load lancer and assign it with a custom domain name.

### Step 1: Create the Service Discovery resources in AWS Cloud Map

Follow these steps to create your service discovery namespace and service discovery service:

1. Create a private Cloud Map service discovery namespace. This example creates two namespace that's called `migration`. Replace vpc-abcd1234 with the ID of one of your existing VPC.

```
aws servicediscovery create-private-dns-namespace \
      --name migration \
      --vpc vpc-abcd1234
```

2. Using the OperationId from the output of the previous step, verify that the private namespace was created successfully. Make note of the namespace ID because you use it in subsequent commands.

```
aws servicediscovery get-operation \
      --operation-id h2qe3s6dxftvvt7riu6lfy2f6c3jlhf4-je6chs2e
```

The output is as follows.

```
{
    "Operation": {
        "Id": "h2qe3s6dxftvvt7riu6lfy2f6c3jlhf4-je6chs2e",
        "Type": "CREATE_NAMESPACE",
        "Status": "SUCCESS",
        "CreateDate": 1519777852.502,
        "UpdateDate": 1519777856.086,
        "Targets": {
           "NAMESPACE": "ns-uejictsjen2i4eeg"
        }
    }
}

```

3. Using the `NAMESPACE ID` from the output of the previous step, create a service discovery service. This example creates a service named `grafana`, `prometheus`, `kafkaconnect`. Make note of each service ID and ARN because you use them in subsequent commands:

```
aws servicediscovery create-service \
      --name myapplication \
      --dns-config "NamespaceId="ns-uejictsjen2i4eeg",DnsRecords=[{Type="A",TTL="300"}]" \
      --health-check-custom-config FailureThreshold=1
```

### Step 2: Create the Amazon ECS resources

Follow these steps to create your Amazon ECS cluster, task definition, and service:

1. Create an Amazon ECS cluster. This example creates a cluster that's named migration.

```
aws ecs create-cluster \
      --cluster-name migration
```

2. Register a task definition that's compatible with `Fargate` and uses the `awsvpc` network mode. Follow these steps:

* Replace tokens with values for runtime parameters: 

```
    export KAFKA_CONNECT_IMAGE_URL= # provide the Amazon ECR url for Kafka Connect image
    export PROMETHEUS_IMAGE_URL= # provide the Amazon ECR url for Kafka Connect image
    export BROKER_ADDRESSES= # provide you Apache Kafka or Amazon MSK *TARGET* broker addresses
    export AWS_REGION= # provide AWS region where you run Amazon ECS cluster
    export TASK_ROLE_ARN= # provide ARN of your task execution role
    export EXECUTION_ROLE_ARN=$TASK_ROLE_ARN
    export AUTH=IAM # accepted values: [SASL/IAM/TLS]

    docker run -i --rm -v ./Fargate:/fargate -e KAFKA_CONNECT_IMAGE_URL=$KAFKA_CONNECT_IMAGE_URL -e BROKER_ADDRESSES=$BROKER_ADDRESSES -e AWS_REGION=$AWS_REGION -e TASK_ROLE_ARN=$TASK_ROLE_ARN -e EXECUTION_ROLE_ARN=$EXECUTION_ROLE_ARN -e AUTH=$AUTH centos bash

    cp ./Fargate/kafka-connect.json ./Fargate/kafka-connect.json.back

    sed -i "s@IMAGE_URL@${KAFKA_CONNECT_IMAGE_URL}@g" ./fargate/kafka-connect.json
    sed -i "s/BROKER_ADDRESSES/${BROKER_ADDRESSES}/g" ./fargate/kafka-connect.json
    sed -i "s/AWS_REGION/${AWS_REGION}/g" ./fargate/kafka-connect.json
    sed -i "s@TASK_ROLE_ARN@${TASK_ROLE_ARN}@g" ./fargate/kafka-connect.json
    sed -i "s@AUTH@${AUTH}@g" ./fargate/kafka-connect.json
    sed -i "s@EXECUTION_ROLE_ARN@${EXECUTION_ROLE_ARN}@g" ./fargate/kafka-connect.json

    sed -i "s@IMAGE_URL@${PROMETHEUS_IMAGE_URL}@g" ./fargate/prometheus.json
    sed -i "s/AWS_REGION/${AWS_REGION}/g" ./fargate/prometheus.json
    sed -i "s@TASK_ROLE_ARN@${TASK_ROLE_ARN}@g" ./fargate/prometheus.json
    sed -i "s@AUTH@${AUTH}@g" ./fargate/prometheus.json
    sed -i "s@EXECUTION_ROLE_ARN@${EXECUTION_ROLE_ARN}@g" ./fargate/prometheus.json

    sed -i "s/AWS_REGION/${AWS_REGION}/g" ./fargate/grafana.json
    sed -i "s@TASK_ROLE_ARN@${TASK_ROLE_ARN}@g" ./fargate/grafana.json
    sed -i "s@EXECUTION_ROLE_ARN@${EXECUTION_ROLE_ARN}@g" ./fargate/grafana.json
    exit
```

3. Register the task definitions using the json files:

```
    aws ecs register-task-definition \
      --cli-input-json file://./Fargate/kafka-connect.json

    aws ecs register-task-definition \
      --cli-input-json file://./Fargate/prometheus.json

    aws ecs register-task-definition \
      --cli-input-json file://./Fargate/grafana.json
```

Exit after each command by typing `q` and press enter.

4. You have all building blocks for running Kafka connect, Prometheus, and Grafana in Amazon ECS. You need to create three `Services` in Amazon ECS. We use Fargate as a capacity provider for all three services and setup auto-scaling for `msk-connect` service. To learn more about these concepts refer to [https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tutorial-cluster-auto-scaling-console.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tutorial-cluster-auto-scaling-console.html).

    Using AWS console is the easiest way to setup these three services:

    1. Navigate to [Amazon ECS console](https://aws.amazon.com/ecs)

    2. Click on `migration` cluster

    3. From `Services` tab, click on `Create` button

    4. Choose `Kafka-connect` from the `Family` dropdown

    5. Type `kafka-connect` as **Service Name**

    6. Enable **Service Discovery**

    7. Select `migration` as existing **Namespace** and `kafkaconnect` as existing **Discovery service**

    8. From the **Networking** choose the VPC where your MSK cluster is created in. Choose the private subnets in your VPC to protect the tasks from being exposed to internet. Choose the security group that allows outbound traffic to the security group attached to Amazon MSK. Turn off the public IP address

    9. Enable **Service autoscaling**. Enter desired minimum and maximum number of tasks. Type `cputracking` as **policy name**. Select `ECSServiceAverageCPUUtilization` from the dropdown. Chose other values based on your devops preferences

    10. Click **Create**. The console will deploy a CloudFormation stack to create this service

    11. Repeat the same steps for `grafana` and `prometheus`. Keep the auto-scaling disabled as these applications are setup in a standalone mode


5. Once confirmed all services are in `Running` state, you can begin setting up your monitoring:

    1. Make a ssh tunnel to your Amazon EC2 bastion and specify the port your proxy is using:

    ```
    ssh -i pemfile.pem ec2-user@ec2-xx-xxx-xxx-xxx.compute-1.amazonaws.com -ND 8157
    ```

    2. Navigate to [http://prometheus.monitoring:9090]([http://prometheus.monitoring:9090) and verify you can view main page

    3. Navigate to [http://graphana.monitoring:3000](http://graphana.monitoring:3000) and verify you can view dashboard

    4. The default username and password is `admin`

    5. Add a new source: 1- Select Prometheus as type 2- Enter: `http://prometheus.monitoring:9090` as URL 3-Click **Test and Save** button

    5. Import the [Grafana/MM2-dashboard-1.json](Grafana/MM2-dashboard-1.json) monitoring dashboard

