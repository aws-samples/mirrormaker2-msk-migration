# kafka-connect

### Kafka Connect workers

Kafka Connect workers operate as a cluster to facilitate scalable and fault-tolerant data integration in Apache Kafka. In this setup, multiple Kafka Connect worker instances collaborate to distribute and parallelize the processing of connectors and tasks. Each worker in the cluster is responsible for executing a subset of connectors and their associated tasks, which are units of work responsible for moving data between Kafka and external systems. The workers share configuration information and coordinate through the Kafka broker to ensure a cohesive and balanced distribution of tasks across the cluster. This distributed architecture enables horizontal scaling, allowing the Kafka Connect cluster to handle increased workloads and provides resilience by redistributing tasks in the event of worker failures, thereby ensuring continuous and reliable data integration across connected systems.

### Kafka connect worker configuration file

The Kafka Connect worker configuration file is a crucial component in defining the behavior and settings of a Kafka Connect worker. This configuration file typically includes details such as the **Kafka bootstrap servers**, **group ID**, key and value **converters**, and specific connector configurations, allowing users to tailor the worker's behavior to their specific data integration requirements.

This code example provides different configuration files based on each authentication scheme. Refer to [Configuration/workers](Configuration/workers) to view these files. 

### Mirror Maker source connector configuration

This file typically includes details such as connection properties, topic configurations, and any additional settings required for extracting data from the source topics and publishing it to the target Kafka cluster. Users leverage this configuration file to tailor the source connector's behavior, ensuring seamless integration and effective data ingestion from the source to Kafka. Submitting the contents of this file via a POST or PUT REST Api for the first time, starts the source connector. Further calls will update the connector configuration and restart its tasks. MM2 source connector scale horizontally by increasing the value for `task.max` configuration.

This example provides distinct configuration files for each connector per each authentication scheme. Refer to [Configuration/connectors](Configuration/connectors) for more information.

## Build

### Using Maven

```
mvn clean install -f pom.xml
```

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

### Using Docker

```
docker build . -t kafka-connect-270:latest
```

A local docker images will be created. 

### Running on the local computer using Docker

```
docker run --rm -p 3600:3600 -e BROKERS=localhost:9092 -e GROUP=my-kafka-connect kafka-connect-270:latest
```
