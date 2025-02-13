# MSK Migration Resources

This repository accompanies the [Amazon MSK migration lab](https://catalog.workshops.aws/msk-migration-lab/en-US).
It includes resources used in the lab including AWS CloudFormation templates, configuration files and Java code. This repository differs from the lab in deploying MirrorMaker on ECS Fargate for improved resilience, scalability, and maintainability.  

## Overview

For more background on Kafka Connect, please see [kafka-connect](./kafka_connect.md).

![](./static/kafka-migration-architecture.png)

1. The MirrorMaker task running in Kafka Connect reads from configured source cluster,
replicating topics, consumer group offsets, and ACLs 1-1 to the target cluster

2. ECS services are deployed privately in a multi-AZ configuration,
with autoscaling based on task CPU to automatically scale to
meet Kafka cluster load and ensure fault tolerance when tasks fail 

3. Prometheus is used to scrape metrics from Kafka Connect
tasks to monitor replication latency and task status over time

4. Grafana is used to visualize Prometheus metrics

5. Consumers can be migrated to the target cluster
over time as topics and consumer groups are kept in sync 
by Kafka Connect. Once consumers are migrated to the target 
cluster, producers can migrate as well.

6. Bastion host or virtual desktop are used to access private resources,
such as configuring Kafka Connect tasks and monitoring replica lag
in Grafana

## Containerization for Kafka Connect

This project relies on Docker images running in ECS Fargate to deploy Kafka Connect, Prometheus, and Grafana. 

The [`build_images.sh`](./build_images.sh) script will build and deploy the Kafka Connect and Prometheus images to ECR repositories. It requires that the ECR repositories have already been created, and are named `kafka-connect` and `prometheus`. The Terraform resources will create the ECR repositories on your behalf - please see [automated build instructions](#option-1-automated-infrastructure-build) for more information.

Usage:

`./build_images.sh ACCOUNT_ID REGION`

`./build_images.sh 012345678910 us-east-1`

The build script includes environment variabls to build AMD x86 images, even when running on
ARM hosts. If you choose to build and deploy your images manually without the build script, please
ensure you build AMD x86 images:

`DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build .`

### Kafka Connect Image
The root folder contains the definitions for [CustomMM2ReplicationPolicy](./CustomMM2ReplicationPolicy/) and Centos-based Java dependencies necessary for running Kafka Connect in the [Dockerfile](./Dockerfile), as outlined below. It also  contains the [Kafka Connect configuration examples](./Configuration/connectors/) for MirrorMaker tasks in a variety of scenarios (such as IAM authentication, mTLS authentication, etc.).

### Prometheus Image 
The [prometheus folder](./prometheus/) contains a custom Prometheus image that includes the necessary scrape
targets and intervals to gather Prometheus metrics from the Kafka brokers.

## Deployment

### Infrastructure
First, we need to build the backend infrastructure (ECS tasks, Kafka clusters, etc) for the migration tasks. We can do this either with the automated build scripts, or manually.

#### Option 1: Automated Infrastructure Build
The majority of the required infrastructure for this example can be built and deployed using the Terraform source located in [terraform/](./terraform/README.md). The only thing not provisioned in the Terraform example are the VPC to deploy in, and the build/push of the Docker images. After the Terraform has been deployed, the images can be automatically built using the provided [build script](./build_images.sh) to build and push to ECR.

```
cd terraform/
terraform init
terraform apply -var-file main.tfvars

cd ..
./build_images.sh 012345678910 us-east-1
```

Finally, you will need to deploy the Kafka Connect tasks ([see below](#application-and-monitoring)). 

#### Option 2: Manual Infrastructure Build

Please see [the manual build instructions](./manual_build.md) for steps on deploying infrastructure manually via the AWS CLI.

### Application and Monitoring
Once the infrastructure is deployed and our ECS tasks reach the RUNNING state, we can set up the monitoring and MirrorMaker tasks. To access the ECS tasks, ensure you have an SSH tunnel/proxy running to set up the connectivity, or use a bastion host / Amazon WorkSpaces virtual desktop.

To make a ssh tunnel to your Amazon EC2 bastion and specify the port your proxy is using:

```
ssh -i privatekey.pem ec2-user@ec2-xx-xxx-xxx-xxx.compute-1.amazonaws.com -ND 8157
```

#### Grafana/Prometheus

1. Navigate to [http://prometheus.monitoring:9090](http://prometheus.monitoring:9090) and verify you can view main page. Note that this URL may differ if you used the automated build - the URLs for these services can be found in the terraform outputs.

2. Navigate to [http://graphana.monitoring:3000](http://graphana.monitoring:3000) and verify you can view dashboard

        * The default username and password is `admin`

3. Add a new source: 
    
    1. Select Prometheus as type 
    2. Enter: `http://prometheus.monitoring:9090` as URL 3-Click **Test and Save** button

4. Import the [grafana/MM2-dashboard-1.json](./grafana/MM2-dashboard-1.json) monitoring dashboard

#### Kafka Connect MirrorMaker Tasks

1. If you used the manual build, clone this repository on your instance

    ```
    git clone https://github.com/aws-samples/mirrormaker2-msk-migration.git
    ```

    If you used the automated build, copy the configured task definitions from S3 to your instance - the S3 URIs for these files can be found in the terraform outputs:

    ```
    aws s3 cp s3://my-config-bucket/connector/mm2-msc-iam-auth.json .
    aws s3 cp s3://my-config-bucket/connector/mm2-hbc-iam-auth.json .
    aws s3 cp s3://my-config-bucket/connector/mm2-cpc-iam-auth.json .
    ```

2. Edit the connector json files in [configurations](./Configuration/connectors/) directory with your broker addresses if not already populated.
    
3. Run the source connector, Example for IAM:

    ```
    curl -X PUT -H "Content-Type: application/json" --data @mm2-msc-iam-auth.json http://kafkaconnect.migration:8083/connectors/mm2-msc/config | jq '.'

    ```

4. Check the status of the connector to make sure it's running:

    ```
    curl -s kafkaconnect.migration:8083/connectors/mm2-msc/status | jq .
    ```

5. Repeat steps 3&4 for two other connectors:

    ```
    curl -X PUT -H "Content-Type: application/json" --data @mm2-cpc-iam-auth.json http://kafkaconnect.migration:8083/connectors/mm2-cpc/config | jq '.'

    curl -s kafkaconnect.migration:8083/connectors/mm2-cpc/status | jq .

    curl -X PUT -H "Content-Type: application/json" --data @mm2-hbc-iam-auth.json http://kafkaconnect.migration:8083/connectors/mm2-hbc/config | jq '.'

    curl -s kafkaconnect.migration:8083/connectors/mm2-hbc/status | jq .
    
    ```

If you need help running a sample Kafka producer / Consumer, refer to [MSK Labs Migration Workshop](https://catalog.workshops.aws/msk-labs/en-US/migration/mirrormaker2/usingkafkaconnectgreaterorequal270/customreplautosync/migrationlab1)

## FAQ

### When should I use this code sample to run MirrorMaker2?
There are a few main use cases for MirrorMaker2 in migrations:

1. **When you want to support any authentication mode** - MirrorMaker2 on ECS Fargate can support any Kafka cluster authentication mode, and supports Kafka clusters that are on-prem, self-managed on EC2, or 3rd party hosted.
2. **When you want custom topic naming conventions** - In this sample we want to use a custom replication policy JAR to change how MirrorMaker2 names topics in the replicated cluster. Kafka Connect on ECS Fargate supports this.
3. **When you want detailed monitoring of Kafka Connect** - In this sample we want to analyze the Prometheus metrics that Kafka Connect and MirrorMaker2 surface to support the migration operations. Because we value monitoring these metrics, we deploy in ECS where we can scrape Prometheus metrics exposed by Kafka Connect and fully monitor and operate MirrorMaker2 for the migration.

### What does it cost to run this solution?
There are a few key components to the overall cost of running Kafka Connect on ECS Fargate to run MirrorMaker2:

1. Baseline ECS Costs

    There are 3 ECS services recommended for running Kafka Connect and MirrorMaker2:

    * Prometheus (2048 CPU, 4096 Memory per task)
    * Grafana (1024 CPU, 3072 Memory per task)  
    * Kafka Connect (1024 CPU, 4096 Memory per task)  

    Each service may have 1 or more tasks. For Prometheus and Grafana, 2-3 tasks may be used for high availability. These services do not have a backend data store configured, and therefore aren't persistent across reboots. Adding persistent storage would increase the cost of the solution. 

    The ECS costs will be based on the total number of ECS tasks and their CPU/memory configuration, as outlined in the [ECS Fargate pricing page](https://aws.amazon.com/ecs/pricing/).
    
2. Scaling Considerations

    For Kafka Connect, the service is autoscaled based on the load in the Kafka cluster being replicated. This can be capped to a maximum task limit to limit the overall cost of the solution.

    In MirrorMaker2, the Kakfa Connect tasks are used to consume from the cluster partitions. For example:
    
        * 10 partitions, 5 MirrorMaker2 tasks yields 2 partitions per task
        * 10 partitions, 10 MirrorMaker2 tasks yields 1 partition per task
        
    ECS will autoscale the number of ECS tasks, and therefore MirrorMaker2 tasks, based on the CPU of the ECS tasks. At most, for a cluster with `X` partitions you can expect a total of `X` Kafka Connect tasks, and therefore `X/10` ECS tasks for Kafka Connect (assuming `tasks.max=10`).

3. MSK Costs

    During the migration you will use an MSK cluster for storing the replicated
    topic data. You can use [this blog](https://aws.amazon.com/blogs/big-data/best-practices-for-right-sizing-your-apache-kafka-clusters-to-optimize-performance-and-cost/) 
    to help with right sizing your cluster and understanding cluster costs.


### How can I fine-tune the replication settings?

There are several MirrorMaker settings for the **MirrorSourceConnector (MSC)** and **MirrorCheckpointConnector (CPC)** tasks that can be used to fine-tune replication, in addition to producer level configurations:

#### Message Max Sizes
The default Kafka Connect configurations support message sizes up to 37 MB. You may also
need to update the `message.max.bytes` broker or topic level configurations to handle large message
sizes if required for your use case. 

#### Producer level settings
Producer-level configurations are set in the Kafka Connect settings. These are set when the Kafka Connect Docker image is built, using the worker configurations ([Configuration/workers/](./Configuration/workers/)). 

You can optionally choose to load these dynamically during startup by providing the `KAFKA_CONNECT_PROPERTIES_S3_URI` environment variable, and providing the ECS task the IAM permissions needed to read the file from the S3 bucket.
This will cause the `connect-distributed.properties` file to be read on container startup via [start-kafka-connect.sh](./start-kafka-connect.sh).

Additionally, if using mTLS authentication for the Kafka Connect cluster to store its internal state, you can load the Keystore and Truststore dynamically via S3 with the `KAFKA_CONNECT_KEYSTORE_S3_URI`and `KAFKA_CONNECT_TRUSTSTORE_S3_URI` environment variables.

#### MSC

| Config | Default Setting in Sample | Description |
|--------|---------------------------|-------------|
| `replication.policy.class` | `...CustomMM2ReplicationPolicy` | Custom Java  code to rename topics from the source cluster to the destination cluster. Allows changing or not changing topic names to assist with producer/consumer logic in migration. |
| `tasks.max` | `4` | The overall number of Kafka Connect tasks running across all distributed worker nodes. The ideal setting for this allows for 5-10 partitions per task (e.g. `tasks.max = Total Partition Count / 5`). |
| `replication.factor` | `3` | The replication factor for newly created topics - set based on the configuration of the destination cluster. |
| `offset-syncs.topic.replication.factor` | `3` | The replication factor for the internal MirrorMaker topic used to replicate offsets to the destination cluster - set based on the configuration of the destination cluster. |
| `sync.topic.acls.interval.seconds` | `600` | Frequency of the ACL sync. Setting too low can cause disruption in the source cluster due to the overhead caused by high frequency ACL polling. |
| `sync.topic.configs.interval.seconds` | `600` | Frequency of the topic configuration sync. Setting too low can cause disruption in the source cluster due to the overhead caused by high frequency config polling. |
| `refresh.topics.interval.seconds` | `300` | Frequency of finding and replicating newly added topics. Setting too low can cause disruption in the source cluster due to the overhead caused by high frequency topic polling. |
| `refresh.groups.interval.seconds` | `20` | Frequency of the Kafka consumer group sync. Setting too low can cause disruption in the source cluster due to the overhead caused by high frequency group polling |
| `producer.enable.idempotence` | `true` | Gives the MirrorMaker2 Producers PIDs and message sequence numbers that allows Kafka brokers to reject messages if lower sequence numbers are ever recieved (the default behavior as of Kafka 3.0). |
| `max.poll.records` | `50,000` | Maximum number of records returned in a single poll operation. Can tune based on your throughput and message size, but generally can be a sensible default. |
| `receive.buffer.bytes` | `33,554,432` | TCP receive buffer size. Kafka default is 64 KB so a higher value here allows for less disruption in high throughput workloads. |
| `send.buffer.bytes` | `33,554,432` | TCP send buffer size. Kafka default is 128 KB so a higher value here allows for less disruption in high throughput workloads.  |
| `max.partition.fetch.bytes` | `3,355,4432` | The maximum amount of data returned for a single partition - set to match the send/receive buffer sizes since we always read and write the same amount of data for MirrorMaker2.  |
| `message.max.bytes` | `37,755,000` | Broker level setting for maxium message size, maybe unneeded here? |
| `compression.type` | `gzip` | Broker level setting for compression, maybe unneeded here?  |
| `max.request.size` | `26,214,400` | Max request size from a producer - must be large than the largest message being sent (e.g. `max.message.bytes` in the topic and `message.max.bytes` in the broker).  |
| `buffer.memory` | `524,288,000` | In memory buffer to store messages for batching and if messages can't be sent to the broker. Allows for higher throughput by sending larger message batches. After reaching this buffer size and wiating `max.block.ms` the producer will shut down. Can change want to tune producer shutdown behavior during a broker disruption. |
| `batch.size` | `524,288` | The maximum amount of data that can be sent in a single request. Should be smaller than the buffer memory to allow efficient use of the buffer. |

#### CPC

| Config | Default Setting in Sample | Description |
|--------|---------------------------|-------------|
| `tasks.max` | `1` | Should always be 1 for CPC | 
| `replication.factor` | `3` | Replication factor for new topics - set based on the configuration of the destination cluster. |
| `checkpoints.topic.replication.factor` | `3` | Replication factor for the internal offset tracking topic - set based on the configuration of the destination cluster. |
| `emit.checkpoints.interval.seconds` | `20` | Frequency of retrieving and syncing consumer group offsets to the replication topic. |
| `sync.group.offsets.interval.seconds` | `20` | Frequency of syncing consumer group offsets in the destination cluster. |
| `sync.group.offsets.enabled` | `true` | Whether or not to automatically sync offsets to the destination consumer groups (vs. only tracking in the offset topic). Can set to false if you want to manually manage offsets in the destination. |

### How can I minimize the number of duplicate messages I process in my consumers?

Consumer group offsets are replicated by the MirrorMaker2 CPC task. The offsets are replicated periodically **while 
there is an active consumer in the souce cluster**. This means that when the consumer is stopped on the source cluster, the offsets
will stop being replicated. This will cause duplicate messages to be consumed when the consumer starts on the target cluster. The number
of duplicate messages will depend on the frequency of the offset sync.

The offsets are replicated based on two configurations:

| Config | Default Setting in Sample | Description |
|--------|---------------------------|-------------|
| `emit.checkpoints.interval.seconds` | `20` | Frequency of retrieving and syncing consumer group offsets to the replication topic. |
| `sync.group.offsets.interval.seconds` | `20` | Frequency of syncing consumer group offsets in the destination cluster. |

For example, if these are set to 20 seconds, then there may be up to 20 seconds of data that are consumed and committed
on the source cluster, but not be sync'ed to the target cluster. To minimize these duplicates, you can reduce these intervals.
Note that setting these lower can impact performance on the source/target cluster. We recommend monitoring cluster CPU/memory closely
if you reduce these below 20 seconds.

To understand the current replicated offset positions in the source/target cluster, you can use the `kafka-consumer-groups.sh` script provided by Kafka:

```sh
bin/kafka-consumer-groups.sh \
    --describe \
    --bootstrap-server "${CLUSTER_BROKER_CONNECTION_STRING}"  \
    --group "${CONSUMER_GROUP_NAME}" \
    --command-config client.properties
```

This functionality may change in the future, as the Kafka community is actively investigating methods to further reduce offset replication
delay ([KAFKA-16364](https://issues.apache.org/jira/browse/KAFKA-16364)).

### My replication latency is high, what do I do?

1. Check the Kafka Connect task record counts (`kafka_connect_source_task_source_record_active_count`) to see if records are evenly balanced across tasks, and that tasks generally have 2,000-20,000 records each. If tasks have more than this, it's possible that they are over-provisioned with partitions.
2. Adjust `tasks.max` to balanace partitions across the tasks so that each task gets 5-10 partitions each.
3. Ensure that the compute for Kafka Connect is sized correctly so that each compute node runs at ~70% CPU and ~50% memory

After validating these settings if your replication latency is still high, you may need to investigate the settings for `max.message.bytes` and `message.max.bytes` to ensure that buffers are sized correctly for the Kafka Connect producer and consumer sides in the MSC settings.

### How does scaling work in Kafka  Connect? How should I size the ECS tasks and `tasks.max` setting?
Kafka Connect is built to be a distributed framework scaling horizontally across
task compute nodes. To scale Kafka Connect, we simply add more worker nodes to load balance tasks across workers. 
MirrorMaker2 should size `tasks.max` so that each MirrorSourceConnector task has 5-10 partitions to replicate.

### What metrics should I monitor to understand the health of Kafka Connect / MirrorMaker2?

#### 1. **`kafka_connect_mirror_source_connector_replication_latency_ms_avg`**:

* **What it shows:** This shows the average replication latency in milliseconds between the source and destination Kafka clusters (time for a message to be replicated from the source cluster to the destination cluster)
* **Why it matters:** This metric indicates overall performance of the MirrorMaker 2 replication process. A lower latency indicates faster and more efficient replication.

#### 2. **`kafka_consumer_fetch_manager_records_lag`**:

* **What it shows:** This shows the consumer lag, which represents the difference between the latest offset in the source cluster and the current offset in the destination cluster.
* **Why it matters:** Consumer lag indicates how far behind the destination cluster consumers are compared to the source cluster. A high consumer lag can suggest issues with the replication process or the ability of the destination cluster to consume the data at the same pace as the source cluster.

#### 3. **`kafka_connect_mirror_source_connector_record_age_ms_avg`**:
* **What it shows:** This shows the time difference between when the record was produced and when it was replicated to the destination cluster. 
* **Why it matters:** This metric provides insight into the timeliness of the replication process. A lower average record age indicates that the data is being replicated more quickly, which is desirable for real-time applications.

#### 4. **`kafka_consumer_fetch_manager_fetch_latency_avg`**:
* **What it shows:** This shows the latency experienced by the consumer when fetching data from the destination Kafka cluster. 
* **Why it matters:** The consumer fetch latency is an important metric to monitor, as it can impact the overall performance of the data processing pipeline. A low consumer fetch latency is desirable, as it indicates that the destination cluster can serve the data to consumers in a timely manner.

#### 5. **`kafka_connect_source_task_source_record_active_count`**:
* **What it shows:** This shows the number of records processed by each Kafka Connect task. 
* **Why it matters:** The number of records per task shows the aggregate throughput that Kafka Connect is processing. Each MSC task should be balanced with a similar number of overall records, and any MSC task with many more or fewer records indicates an unbalanced MirrorMaker2 replication state. This likely indicates a hot partition, or an incorrect setting for `tasks.max`.


### Why am I getting `InvalidRecordException` with timestamp out of range error?

* **What is the error:** This shows as an exception which causes the tasks fail and replication stops. It could happen right after you start the source connector, or when the connector has stopped for a long time and you restart it again. This error usually shows in logs as follows:

```
org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception from producer send callback
	at org.apache.kafka.connect.runtime.WorkerSourceTask.maybeThrowProducerSendException(WorkerSourceTask.java:291)
	at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:352)
	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:258)
	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:188)
	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:243)
	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:829)
Caused by: org.apache.kafka.common.InvalidRecordException: Timestamp 1716652875350 of message with offset 0 is out of range. The timestamp should be within [1716927328590, 1717100128590]

```

* **Root cause:** There is a broker level configuration `log.message.timestamp.difference.max.ms` that manages how the broker should validate the events' timestamp. If this configuration is set to a  value that is shorter than the age of the oldest message on a source topic, this error will occur.

* **How to fix it:** If you expect to replicate the data which is older than the configured value, you would need to increase this value and restart your Kafka brokers. 


### Why are we seeing negative offset lags, when inspecting the `__consumer_offsets` topic, for only a subset of partitions for a given consumer?

* **What is causing this error:** This bug occurs when using MirrorMaker2 with `sync.group.offsets.enabled = true`

    If a source partition is empty, but the source consumer group's offset for that partition is non-zero, then MirrorMaker sets the target consumer group's offset for that partition to the literal, not translated, offset of the source consumer group. This state can be reached if the source consumer group consumed some records that were now deleted (like by a retention policy), or if MirrorMaker replication is set to start at "latest". This bug causes the target consumer group's lag for that partition to be negative and breaks offset sync for that partition until lag is positive.

    The correct behavior when the source partition is empty would be to set the target offset to the translated offset, not literal offset, which in this case would always be 0. [More information](https://issues.apache.org/jira/browse/KAFKA-12635).

* **What is the solution:** Manually resetting the consumer group offsets on target cluster, before consumers start to read from the target cluster. Or upgrading the Kafka Connect version to >=3.3. 

### Why do I need both `target.cluster.bootstrap.servers` and `producer.override.bootstrap.servers` (but not for `source` and `consumer`)?

Kafka Connect and MirrorMaker2 use a variety of different Kafka clients
internally for their operations. The `target.*` and `source.*` Kafka 
client configurations are used for MirrorMaker2 operations such as 
offset syncs, metadata management, and admin client management to 
interact with the source/target Kafka clusters. **This includes reading
topic data from the source cluster.**

However, for the Producer client writing records to the target cluster, MirrorMaker2 uses the
Kafka Connect "Framework" Kafka Client, which comes from the worker 
configuration in `connect-distributed.properties`. Depending on where
you run Kafka Connect (against the source, target, or another cluster), 
this means that MirrorMaker2 may or may not use the right Producer
client configuration. Setting `producer.override.*` level settings 
ensure that no matter where Kafka Connect is running, MirrorMaker2
will have the right client configurations for the producers. 

So, we need both the `target.*` configs and `producer.override.*` configurations to make sure both the MirrorMaker2 internal clients AND the
"framework" Kafka Connect clients are used correctly for interacting
with the target Kafka cluster.

In our examples we assume that Kafka Connect and the target cluster
use the same authentication and encryption settings, so we only set 
the `producer.override.bootstrap.servers` settings in the task configs.
However, if your Kafka Connect and target cluster use different settings,
you need to override all of the relevant client settings for the producer:

```
"producer.override.bootstrap.servers": "${TARGET_BROKERS}",
"producer.override.security.protocol": "SASL_SSL",
"producer.override.sasl.mechanism": "AWS_MSK_IAM",
...
```
