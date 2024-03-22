## Manual Deployment to ECS
This section outlines the steps to manually create ECS infrastructure to run Kafka Connect.

### Step 0. Prerequisites

In this section, you learn how to deploy necessary docker images to your docker image repository. This code example as the following requirements. 

* You are familiar with setting up Proxy to view websites hosted on the private networks. We suggest using [FoxyProxy](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-connect-master-node-proxy.html) for this code example. This setup will require an Amazon EC2 bastion host with SSM or SSH connectivity from your local machine.

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

* If you are using IAM authentication for connecting to Amazon MSK, find an example [Fargate/msk-iam-auth-inline-policy.json](./Fargate/msk-iam-auth-inline-policy.json) inline policy

* If you want to use IAM authentication for Amazon MSK, attach the [required permissions](https://docs.aws.amazon.com/msk/latest/developerguide/security_iam_id-based-policy-examples.html) as a separate IAM policy document to your ECS task execution role


### Step 1. Push Kafka connect docker image to Amazon ECR

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

### Step 2. Push Prometheus docker image to Amazon ECR

1. Create another ECR repository for Prometheus.

2. Push `prometheus` docker image to your private repository.

     **Important:** This task also requires an ARM x86 image. 

    ```
    cd prometheus

    docker build -t prometheus .

    docker tag prometheus:latest {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest 

    docker push {AWS Account ID}.dkr.ecr.us-east-1.amazonaws.com/{Private repository name}:latest
    ```

### Step 3. Create an Amazon ECS cluster

The applications we are about to deploy need connectivity from your local machine. Depending on how you connect to your internal AWS resources the setup may vary. This code example assumes you're connection from the internet. For simplicity we use SSH tunnel via a local proxy. For more information about creating an SSH tunnel, see [Option 2, part 1: Set up an SSH tunnel to the primary node using dynamic port forwarding](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ssh-tunnel.html). 

Alternatively you can setup an internet facing load lancer and assign it with a custom domain name, or use a virtual desktop with Amazon WorkSpaces.

### Step 4: Create the Service Discovery resources in AWS Cloud Map

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

### Step 5: Create the Amazon ECS resources

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

    docker run -i --rm -v ./Fargate/:/fargate -e KAFKA_CONNECT_IMAGE_URL=$KAFKA_CONNECT_IMAGE_URL -e BROKER_ADDRESSES=$BROKER_ADDRESSES -e AWS_REGION=$AWS_REGION -e TASK_ROLE_ARN=$TASK_ROLE_ARN -e EXECUTION_ROLE_ARN=$EXECUTION_ROLE_ARN -e AUTH=$AUTH centos bash

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