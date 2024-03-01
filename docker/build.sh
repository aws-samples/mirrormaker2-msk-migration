#!/bin/bash
set -e

ACCOUNT_ID=$1
REGION=$2

if [ -z "${ACCOUNT_ID}" ] || [ -z "${REGION}" ]; then
    echo "Usage: "
    echo "./build.sh ACCOUNT_ID REGION"
    echo "./build.sh 012345678910 us-east-1"
    exit 1
fi

aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

for image in kafka-connect prometheus; do
    cd "${image}"
    DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build -t "${image}" .
    docker tag "${image}:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${image}:latest"
    docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${image}:latest"
    cd ..
done