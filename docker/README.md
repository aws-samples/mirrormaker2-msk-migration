# Docker images for Kafka Connect

This folder contains the Dockerfile and related resources for Kafka Connect and Prometheus.

## Image Build
The `build.sh` script will build and deploy the Kafka Connect and Prometheus images to ECR repositories. It requires that the ECR repositories have already been created, and are named `kafka-connect` and `prometheus`. 

Usage:

`./build.sh ACCOUNT_ID REGION`

`./build.sh 012345678910 us-east-1`

The build script includes environment variabls to build AMD x86 images, even when running on
ARM hosts. If you choose to build and deploy your images manually without the build script, please
ensure you build AMD x86 images:

`DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build .`

## Kafka Connect
The `kafka-connect` folder contains the definitions for `CustomMM2ReplicationPolicy` and Centos-based
Java dependencies necessary for running Kafka Connect, as outlined in the main README. It also 
contains the Kafka Connect configuration examples for MirrorMaker tasks in a variety of scenarios
(such as IAM authentication, mTLS authentication, etc.).

## Prometheus 
The `prometheus` folder contains a custom Prometheus image that includes the necessary scrape
targets and intervals to gather Prometheus metrics from the Kafka brokers.