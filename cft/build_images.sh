#!/bin/bash
set -e

ACCOUNT_ID=$1
REGION=$2

if [ -z "${ACCOUNT_ID}" ] || [ -z "${REGION}" ]; then
    echo "Usage: "
    echo "./build_images.sh ACCOUNT_ID REGION"
    echo "./build_images.sh 012345678910 us-east-1"
    exit 1
fi

aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Building kafka-connect image"

cd kafka-connect/
DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build -t "kafka-connect" .
docker tag "kafka-connect:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kafka-connect:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kafka-connect:latest"
cd - 

echo "Building prometheus image"

cd prometheus/
DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build -t "prometheus" .
docker tag "prometheus:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prometheus:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prometheus:latest"
cd -

echo "Building prometheus-ecs-discovery image"

cd prometheus-ecs-discovery/
DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build -t "prometheus-ecs-discovery" .
docker tag "prometheus-ecs-discovery:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prometheus-ecs-discovery:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prometheus-ecs-discovery:latest"
cd -

