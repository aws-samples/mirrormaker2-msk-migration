# MSK Migration Resources

This repository accompanies the [Amazon MSK migration lab](https://amazonmsk-labs.workshop.aws/en/migration.html).  
It includes resources used in the lab including AWS CloudFormation templates, configuration files and Java code. This repository differs from the lab in deploying MirrorMaker on ECS Fargate for improved resilience, scalability, and maintainability.  

## Overview

For more background on Kafka Connect, please see [kafka-connect](docker/kafka-connect/README.md).

## Deployment

### Infrastructure
First, we need to build the backend infrastructure (ECS tasks, Kafka clusters, etc) for the migration tasks. We can do this either with the automated build scripts, or manually.

#### Option 1: Automated Infrastructure Build
The majority of the required infrastructure for this example can be built and deployed using the Terraform source located in [terraform/](./terraform/README.md). The only thing not provisioned in the Terraform example are the VPC to deploy in, and the build/push of the Docker images. After the Terraform has been deployed, the images can be automatically built using the provided [build script](docker/build.sh) to build and push to ECR.

```
cd terraform/
terraform init
terraform apply -var-file main.tfvars

cd -
cd docker/
./build.sh 012345678910 us-east-1
```

Finally, you will need to deploy the Kafka Connect tasks. 

#### Option 2: Manual Infrastructure Build

##### Prerequisites

In this section, you learn how to deploy necessary docker images to your docker image repository. This code example as the following requirements. 

* You are familiar with setting up Proxy to view websites hosted on the private networks. We suggest using FoxyProxy for this code example: [https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-connect-master-node-proxy.html](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-connect-master-node-proxy.html). This setup will require an Amazon EC2 bastion host with SSM or SSH connectivity from your local machine.

    * An alternative is to use a virtual desktop like [AWS WorkSpaces](https://aws.amazon.com/workspaces/) which can be deployed with VPC connectivity to access private resources.

* An identity principle attached with a policy document for Amazon EC2, Amazon VPC, and Amazon ECS full access

* Amazon ECR as your container image repository

* Existing Amazon VPC with public and private subnets

* A source and target Amazon MSK in a same or different Amazon VPC. For Amazon MSK clusters in different Amazon VPCs, enable multi-VPC connectivity for the cluster and create a connectivity to Amazon MSK from the remote VPC

* An [Amazon ECS task execution IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html). This code example uses the following policies: (**It's a best practice to always use minimum required permissions for your environment**)

    - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    - arn:aws:iam::aws:policy/AmazonEC2FullAccess
    - arn:aws:iam::aws:policy/AmazonECS_FullAccess
    - arn:aws:iam::aws:policy/AmazonMSKFullAccess
    - arn:aws:iam::aws:policy/AWSGlueSchemaRegistryFullAccess

* If you are using IAM authentication for connecting to Amazon MSK, find an example [examples/task-definitions/msk-iam-auth-inline-policy.json](examples/task-definitions/msk-iam-auth-inline-policy.json) inline policy

* If you want to use IAM authentication for Amazon MSK, attach the [required permissions](https://docs.aws.amazon.com/msk/latest/developerguide/security_iam_id-based-policy-examples.html) as a separate IAM policy document to your ECS task execution role


##### Push Kafka connect docker image to Amazon ECR

1. Create a private Amazon ECR repository. See [Creating a private repository](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-create.html)  to create.

2. Make sure docker engine is running on your development machine. 

3. Push `Kafka-Connect` docker image to your private repository.

    **Important:** Our ECS task requires an ARM x86 based image. If you are running docker on an AMD host (such as an Apple computer), please build the image explicitly specifying an ARM build: `DOCKER_DEFAULT_PLATFORM="linux/amd64" docker build .` 

    ```
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com

    # chose a value from these options: {iam, sasl, mtls, no-auth}
    docker build --build-arg="AUTH={Your preferred auth}" -t kafka-connect-distributed . 

    docker tag kafka-connect-distributed:latest {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest 

    docker push {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest
    ```

##### Push Prometheus docker image to Amazon ECR

1. Create another ECR repository for Prometheus.

2. Push `prometheus` docker image to your private repository.

    ```
    cd prometheus

    docker build -t prometheus .

    docker tag prometheus:latest {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest 

    docker push {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest
    ```

##### Create an Amazon ECS cluster

The applications we are about to deploy need connectivity from your local machine. Depending on how you connect to your internal AWS resources the setup may vary. This code example assumes you're connection from the internet. For simplicity we use SSH tunnel via a local proxy. For more information about creating an SSH tunnel, see [Option 2, part 1: Set up an SSH tunnel to the primary node using dynamic port forwarding](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ssh-tunnel.html). 

Alternatively you can setup an internet facing load lancer and assign it with a custom domain name, or use a virtual desktop with Amazon WorkSpaces.

##### Step 1: Create the Service Discovery resources in AWS Cloud Map

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

##### Step 2: Create the Amazon ECS resources

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

    docker run -i --rm -v ./examples/task-definitions/:/fargate -e KAFKA_CONNECT_IMAGE_URL=$KAFKA_CONNECT_IMAGE_URL -e BROKER_ADDRESSES=$BROKER_ADDRESSES -e AWS_REGION=$AWS_REGION -e TASK_ROLE_ARN=$TASK_ROLE_ARN -e EXECUTION_ROLE_ARN=$EXECUTION_ROLE_ARN -e AUTH=$AUTH centos bash

    cp ./fargate/kafka-connect.json ./fargate/kafka-connect.json.back

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
    
```
    Type `exit` to return.

3. Register the task definitions using the json files:

```
    aws ecs register-task-definition \
      --cli-input-json file://./examples/task-definitions/kafka-connect.json

    aws ecs register-task-definition \
      --cli-input-json file://./examples/task-definitions/prometheus.json

    aws ecs register-task-definition \
      --cli-input-json file://./examples/task-definitions/grafana.json
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

### Application and Monitoring
Once the infrastructure is deployed and our ECS tasks reach the RUNNING state, we can set up the monitoring and MirrorMaker tasks. To access the ECS tasks, ensure you have an SSH tunnel/proxy running to set up the connectivity, or use a bastion host / Amazon WorkSpaces virtual desktop.

To make a ssh tunnel to your Amazon EC2 bastion and specify the port your proxy is using:

```
ssh -i privatekey.pem ec2-user@ec2-xx-xxx-xxx-xxx.compute-1.amazonaws.com -ND 8157
```

#### Grafana/Prometheus

    1. Navigate to [http://prometheus.monitoring:9090]([http://prometheus.monitoring:9090) and verify you can view main page. Note that this URL may differ if you used the automated build - the URLs for these services can be found in the terraform outputs.

    2. Navigate to [http://graphana.monitoring:3000](http://graphana.monitoring:3000) and verify you can view dashboard

        * The default username and password is `admin`

    3. Add a new source: 
    
        1. Select Prometheus as type 
        2. Enter: `http://prometheus.monitoring:9090` as URL 3-Click **Test and Save** button

    4. Import the [examples/grafana/MM2-dashboard-1.json](examples/grafana/MM2-dashboard-1.json) monitoring dashboard

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

2. Edit the connector json files in [configurations](docker/kafka-connect/Configuration/connectors) directory with your broker addresses if not already populated.
    
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

### Why not use MSK Connect?
We choose to run Kafka Connect on ECS to deploy MirrorMaker for this use case instead of MSK Connect. There are two main reasons for this:

1. For a migration use case, we want to use a custom replication policy JAR to change how MirrorMaker names topics in the replicated cluster. Due to the JAR naming conventions, MSK Connect will not recognize our custom replication policy, and therefore won't allow our custom topic naming logic.
2. MSK Connect doesn't allow us to monitor detailed Prometheus metrics for the MirrorMaker tasks. Because we value monitoring these metrics, we deploy in ECS where we can scrape Prometheus metrics exposed by Kafka Connect.
