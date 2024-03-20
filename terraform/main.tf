/**
* # Kafka Connect Example 
* 
* Provision MSK and ECS resources to demonstrate using Kafka 
* Connect to migrate data between two Kafka clusters. 
*
* This Terraform file (`main.tf`) will provision:
* * Two MSK clusters (source/target)
* * The relevant security groups & configurations for MSK
* * ECS resources for Kafka Connect, Prometheus, and Grafana
*   * For images, only the ECR repositories for Kafka Connect and Prometheus will be provisioned
*   * You still need to build and push the associated Docker images to the ECR repositories
* 
* Note that this project relies on two public images for Prometheus and Grafana. For 
* the ECS tasks to start up, you will need to have a NAT gateway to provide internet 
* connectivity for ECS to pull the public images.
*
* ## Usage
* First, update the `main.tfvars` file with the appropriate settings for your use case (e.g. account ID, region, VPC Id etc.)
*
* Initialize the project:
* ```
* terraform init
* ```
* 
* View the planned resources that will be created in your account:
* ```
* terraform plan -var-file main.tfvars
* ```
* 
* Apply the Terraform file to create required resources:
* ```
* terraform apply -var-file main.tfvars
* ```
*
* The apply may take up to 90 minutes while the MSK
* clusters are created. This is normal, as the MSK clusters take
* time to provision and configure. 
*/

variable "region" {
  type        = string
  description = "The region to create resources in."
  default     = "us-east-1"
}
variable "partition" {
  type        = string
  description = "The partition to create resources in."
  default     = "aws"
}
variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
variable "account-id" {
  type        = string
  description = "The account to create resources in."
}
variable "app-shorthand-name" {
  type        = string
  description = "Unique app name prefix to prepend to resource names."
}
variable "vpc-id" {
  type        = string
  description = "The VPC to provision resources in."
}


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.19.0"
    }
  }
}
provider "aws" {
  region = var.region
  default_tags { tags = var.tags }
}

locals {
  base-name = "${var.app-shorthand-name}.${var.region}"
}

data "aws_caller_identity" "current" {
  lifecycle {
    # Require that account ID is consistent with current credentials
    postcondition {
      condition = self.account_id == var.account-id
      error_message = join(
        "\n",
        [
          "Configured account ID does not match account ID from AWS credentials.",
          "Configured: ${var.account-id}",
          "From credentials: ${self.account_id}",
        ]
      )
    }
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc-id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }

  lifecycle {
    # Require that the user has only 2-3 private subnets for the cluster
    postcondition {
      condition = length(self.ids) >= 2 && length(self.ids) <= 3
      error_message = join(
        "\n",
        [
          "Invalid number of private subnets identified. Only 2 or 3 private subnets supported.",
          "VPC: ${var.vpc-id}",
          "Subnet Count: ${length(self.ids)}",
          "Subnets: ${jsonencode(self.ids)}",
        ]
      )
    }
  }
}

resource "aws_security_group" "msk" {
  name        = "${local.base-name}.sg.msk"
  description = "Security group for msk clusters."
  vpc_id      = var.vpc-id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "${local.base-name}.sg.msk"
  }
}
resource "aws_kms_key" "msk" {
  description             = "msk KMS key."
  deletion_window_in_days = 30
  enable_key_rotation     = "true"
  tags = {
    "Name" = "${local.base-name}.kms.msk"
  }
}
resource "aws_kms_alias" "alias" {
  name          = replace("alias/${local.base-name}.kms.msk", ".", "_")
  target_key_id = aws_kms_key.msk.key_id
}
resource "aws_cloudwatch_log_group" "main" {
  for_each          = { "source" : "source", "target" : "target" }
  name              = "/aws/msk/broker/${local.base-name}-${each.key}"
  retention_in_days = 3
}
resource "aws_msk_configuration" "main" {
  kafka_versions    = ["3.5.1"]
  name              = replace("${local.base-name}.msk.config", ".", "-")
  server_properties = <<EOF
    auto.create.topics.enable=true
    log.retention.hours=8
    default.replication.factor=3
    min.insync.replicas=2
    num.io.threads=8
    num.network.threads=5
    num.partitions=6
    num.replica.fetchers=2
    replica.lag.time.max.ms=30000
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    socket.send.buffer.bytes=102400
    unclean.leader.election.enable=true
    zookeeper.session.timeout.ms=18000
    allow.everyone.if.no.acl.found=false
    EOF
}
resource "aws_msk_cluster" "main" {
  for_each               = { "source" : "source", "target" : "target" }
  cluster_name           = replace("${local.base-name}.msk.cluster.${each.key}", ".", "-")
  kafka_version          = "3.5.1"
  number_of_broker_nodes = length(data.aws_subnets.private.ids)

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }
  broker_node_group_info {
    instance_type  = "kafka.m5.large"
    client_subnets = data.aws_subnets.private.ids
    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
    security_groups = [aws_security_group.msk.id]
    connectivity_info {
      public_access {
        type = "DISABLED"
      }
      vpc_connectivity {
        client_authentication {
          tls = false
          sasl {
            iam   = true
            scram = true
          }
        }
      }
    }
  }

  client_authentication {
    sasl {
      iam   = true
      scram = true
    }
    unauthenticated = false
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      in_cluster    = true
      client_broker = "TLS"
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.main[each.key].name
      }
    }
  }

}



resource "aws_ecs_cluster" "main" {
  name = replace("${local.base-name}.ecs", ".", "_")
}
resource "aws_iam_policy" "ecs_task_custom_policy" {
  name = "${var.app-shorthand-name}.ecs.ecs-task-custom-policy"
  path = "/"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "AllowExecuteCommand",
          "Effect" : "Allow",
          "Action" : [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ],
          "Resource" : "*"
        },
        {
          "Sid" : "AllowIdentifyECSTasks",
          "Effect" : "Allow",
          "Action" : [
            "ecs:List*",
            "ecs:Describe*"
          ],
          "Resource" : [
            "*"
          ]
        },
        {
          "Sid" : "AllowS3IO",
          "Effect" : "Allow",
          "Action" : [
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket",
          ],
          "Resource" : [
            "arn:${var.partition}:s3:::${aws_s3_bucket.configs.bucket}",
            "arn:${var.partition}:s3:::${aws_s3_bucket.configs.bucket}/*"
          ]
        }
      ]
    }
  )
}
data "aws_iam_policy_document" "ecs_task" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.app-shorthand-name}.ecs.task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task.json
}
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.app-shorthand-name}.ecs.task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task.json
}
resource "aws_iam_role_policy_attachment" "task_custom" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_custom_policy.arn
}
resource "aws_iam_role_policy_attachment" "task_ssm_ro" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/AmazonSSMReadOnlyAccess"
}
resource "aws_iam_role_policy_attachment" "task_execution_ecr" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}
resource "aws_iam_role_policy_attachment" "task_execution_cloudwatch" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/CloudWatchFullAccess"
}
resource "aws_iam_role_policy" "task_msk" {
  name = "${var.app-shorthand-name}.iam.ecs-msk-admin"
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "kafka-cluster:Connect",
            "kafka-cluster:AlterCluster",
            "kafka-cluster:DescribeCluster",
            "kafka-cluster:DescribeClusterDynamicConfiguration",
            "kafka-cluster:AlterClusterDynamicConfiguration",
            "kafka-cluster:WriteDataIdempotently",
          ],
          "Resource" : "arn:${var.partition}:kafka:${var.region}:${var.account-id}:cluster/*/*"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "kafka-cluster:CreateTopic",
            "kafka-cluster:DescribeTopic",
            "kafka-cluster:AlterTopic",
            "kafka-cluster:DeleteTopic",
            "kafka-cluster:DescribeTopicDynamicConfiguration",
            "kafka-cluster:AlterTopicDynamicConfiguration",
            "kafka-cluster:WriteData",
            "kafka-cluster:ReadData"
          ],
          "Resource" : "arn:${var.partition}:kafka:${var.region}:${var.account-id}:topic/*/*"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "kafka-cluster:AlterGroup",
            "kafka-cluster:DeleteGroup",
            "kafka-cluster:DescribeGroup"
          ],
          "Resource" : "arn:${var.partition}:kafka:${var.region}:${var.account-id}:group/*/*"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "kafka-cluster:DescribeTransactionalId",
            "kafka-cluster:AlterTransactionalId",
          ],
          "Resource" : "arn:${var.partition}:kafka:${var.region}:${var.account-id}:transactional-id/*/*"
        }
      ]
    }
  )
}
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${local.base-name}.local"
  description = "${local.base-name} service discovery"
  vpc         = var.vpc-id
}
resource "aws_security_group" "ecs" {
  name        = "${local.base-name}.sg.ecs"
  description = "ECS"
  vpc_id      = var.vpc-id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
resource "aws_ecr_repository" "kafka-connect" {
  name                 = "kafka-connect"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}
resource "aws_cloudwatch_log_group" "kafka-connect" {
  name              = "/ecs/kafka-connect"
  retention_in_days = 5
}
resource "aws_ecs_task_definition" "kafka-connect" {
  family                   = "kafka-connect"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "4096"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(
    [
      {
        "name" : "kafka-connect",
        "image" : "${aws_ecr_repository.kafka-connect.repository_url}:latest",
        "cpu" : 0,
        "portMappings" : [
          {
            "name" : "kafka-connect-8083-tcp",
            "containerPort" : 8083,
            "hostPort" : 8083,
            "protocol" : "tcp",
            "appProtocol" : "http"
          },
          {
            "name" : "kafka-connect-3600-tcp",
            "containerPort" : 3600,
            "hostPort" : 3600,
            "protocol" : "tcp",
            "appProtocol" : "http"
          }
        ],
        "essential" : true,
        "environment" : [
          {
            "name" : "GROUP",
            "value" : "kafka-connect-fargate"
          },
          {
            "name" : "BROKERS",
            "value" : aws_msk_cluster.main["target"].bootstrap_brokers_sasl_iam,
          }
        ],
        "mountPoints" : [],
        "volumesFrom" : [],
        "dockerLabels" : {
          "PROMETHEUS_EXPORTER_JOB_NAME" : "kafka-connect",
          "PROMETHEUS_EXPORTER_PORT" : "3600"
        },
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-create-group" : "true",
            "awslogs-group" : "/ecs/kafka-connect",
            "awslogs-region" : var.region,
            "awslogs-stream-prefix" : "ecs"
          }
        }
      }
    ]
  )
}
resource "aws_service_discovery_service" "kafka-connect" {
  name = "kafka-connect"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
resource "aws_ecs_service" "kafka-connect" {
  name            = replace("${local.base-name}.ecs.service.kafka-connect", ".", "_")
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.kafka-connect.arn
  desired_count   = 1
  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.kafka-connect.arn
  }
  launch_type            = "FARGATE"
  enable_execute_command = true
}
resource "aws_appautoscaling_target" "kafka-connect" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = split(":", aws_ecs_service.kafka-connect.id)[5]
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "kafka-connect-cpu" {
  name               = "kafka-connect-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.kafka-connect.resource_id
  scalable_dimension = aws_appautoscaling_target.kafka-connect.scalable_dimension
  service_namespace  = aws_appautoscaling_target.kafka-connect.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}


resource "aws_ecr_repository" "prometheus" {
  name                 = "prometheus"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}
resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/prometheus"
  retention_in_days = 5
}
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "2048"
  memory                   = "4096"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  volume {
    name = "config"
  }
  ephemeral_storage {
    size_in_gib = 100
  }
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(
    [
      {
        "name" : "prometheus",
        "image" : "${aws_ecr_repository.prometheus.repository_url}:latest",
        "cpu" : 0,
        "portMappings" : [
          {
            "name" : "prometheus-9090-tcp",
            "containerPort" : 9090,
            "hostPort" : 9090,
            "protocol" : "tcp",
            "appProtocol" : "http"
          }
        ],
        "essential" : true,
        "environment" : [],
        "mountPoints" : [
          {
            "sourceVolume" : "config",
            "containerPath" : "/output",
            "readOnly" : false
          }
        ],
        "volumesFrom" : [],
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-create-group" : "true",
            "awslogs-group" : "/ecs/prometheus",
            "awslogs-region" : var.region,
            "awslogs-stream-prefix" : "ecs-prometheus"
          }
        }
      },
      {
        "name" : "discovery",
        "image" : "tkgregory/prometheus-ecs-discovery",
        "cpu" : 0,
        "portMappings" : [],
        "essential" : false,
        "command" : [
          "-config.write-to=/output/ecs_file_sd.yml"
        ],
        "environment" : [
          {
            "name" : "JMX_EXPORTER_BROKER_LIST",
            "value" : ""
          },
          {
            "name" : "NODE_EXPORTER_BROKER_LIST",
            "value" : ""
          }
        ],
        "mountPoints" : [
          {
            "sourceVolume" : "config",
            "containerPath" : "/output",
            "readOnly" : false
          }
        ],
        "volumesFrom" : [],
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-create-group" : "true",
            "awslogs-group" : "/ecs/prometheus",
            "awslogs-region" : var.region,
            "awslogs-stream-prefix" : "ecs-discovery"
          }
        }
      }
    ]
  )
}
resource "aws_service_discovery_service" "prometheus" {
  name = "prometheus"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
resource "aws_ecs_service" "prometheus" {
  name            = replace("${local.base-name}.ecs.service.prometheus", ".", "_")
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }
  launch_type            = "FARGATE"
  enable_execute_command = true
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/grafana"
  retention_in_days = 5
}
resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "3072"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(
    [
      {
        "name" : "grafana",
        "image" : "grafana/grafana",
        "cpu" : 0,
        "portMappings" : [
          {
            "name" : "grafana-3000-tcp",
            "containerPort" : 3000,
            "hostPort" : 3000,
            "protocol" : "tcp",
            "appProtocol" : "http"
          }
        ],
        "essential" : true,
        "environment" : [
          {
            "name" : "GF_INSTALL_PLUGINS",
            "value" : "grafana-clock-panel"
          }
        ],
        "environmentFiles" : [],
        "mountPoints" : [],
        "volumesFrom" : [],
        "ulimits" : [],
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-create-group" : "true",
            "awslogs-group" : "/ecs/grafana",
            "awslogs-region" : var.region,
            "awslogs-stream-prefix" : "ecs"
          }
        }
      }
    ]
  )
}
resource "aws_service_discovery_service" "grafana" {
  name = "grafana"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
resource "aws_ecs_service" "grafana" {
  name            = replace("${local.base-name}.ecs.service.grafana", ".", "_")
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.grafana.arn
  }
  launch_type            = "FARGATE"
  enable_execute_command = true
}


resource "aws_s3_bucket" "configs" {
  bucket        = "${local.base-name}.configs"
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "configs-versioning" {
  bucket = aws_s3_bucket.configs.bucket
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "configs-encryption" {
  bucket = aws_s3_bucket.configs.bucket
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "configs-block" {
  bucket                  = aws_s3_bucket.configs.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "connector-config-cpc" {
  bucket = aws_s3_bucket.configs.bucket
  key    = "connector/mm2-cpc-iam-auth.json"
  content = jsonencode({
    "name" : "mm2-cpc",
    "connector.class" : "org.apache.kafka.connect.mirror.MirrorCheckpointConnector",
    "clusters" : "msksource,mskdest",
    "source.cluster.alias" : "msksource",
    "target.cluster.alias" : "mskdest",
    "target.cluster.bootstrap.servers" : "${aws_msk_cluster.main["target"].bootstrap_brokers_sasl_iam}",
    "source.cluster.bootstrap.servers" : "${aws_msk_cluster.main["source"].bootstrap_brokers_sasl_iam}",
    "tasks.max" : "1",
    "key.converter" : " org.apache.kafka.connect.converters.ByteArrayConverter",
    "value.converter" : "org.apache.kafka.connect.converters.ByteArrayConverter",
    "replication.policy.class" : "com.amazonaws.kafka.samples.CustomMM2ReplicationPolicy",
    "replication.factor" : "3",
    "checkpoints.topic.replication.factor" : "3",
    "emit.checkpoints.interval.seconds" : "20",
    "sync.group.offsets.enabled" : "true",
    "source.cluster.security.protocol" : "SASL_SSL",
    "source.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "source.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "source.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
    "target.cluster.security.protocol" : "SASL_SSL",
    "target.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "target.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "target.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler"
  })
}
resource "aws_s3_object" "connector-config-hbc" {
  bucket = aws_s3_bucket.configs.bucket
  key    = "connector/mm2-hbc-iam-auth.json"
  content = jsonencode({
    "name" : "mm2-hbc",
    "connector.class" : "org.apache.kafka.connect.mirror.MirrorHeartbeatConnector",
    "clusters" : "msksource,mskdest",
    "source.cluster.alias" : "msksource",
    "target.cluster.alias" : "mskdest",
    "target.cluster.bootstrap.servers" : "${aws_msk_cluster.main["target"].bootstrap_brokers_sasl_iam}",
    "source.cluster.bootstrap.servers" : "${aws_msk_cluster.main["source"].bootstrap_brokers_sasl_iam}",
    "tasks.max" : "1",
    "key.converter" : " org.apache.kafka.connect.converters.ByteArrayConverter",
    "value.converter" : "org.apache.kafka.connect.converters.ByteArrayConverter",
    "replication.policy.class" : "com.amazonaws.kafka.samples.CustomMM2ReplicationPolicy",
    "replication.factor" : "3",
    "heartbeats.topic.replication.factor" : "3",
    "emit.heartbeats.interval.seconds" : "20",
    "source.cluster.security.protocol" : "SASL_SSL",
    "source.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "source.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "source.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
    "target.cluster.security.protocol" : "SASL_SSL",
    "target.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "target.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "target.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler"
  })
}
resource "aws_s3_object" "connector-config-msc" {
  bucket = aws_s3_bucket.configs.bucket
  key    = "connector/mm2-msc-iam-auth.json"
  content = jsonencode({
    "name" : "mm2-msc",
    "connector.class" : "org.apache.kafka.connect.mirror.MirrorSourceConnector",
    "clusters" : "msksource,mskdest",
    "source.cluster.alias" : "msksource",
    "target.cluster.alias" : "mskdest",
    "target.cluster.bootstrap.servers" : "${aws_msk_cluster.main["target"].bootstrap_brokers_sasl_iam}",
    "source.cluster.bootstrap.servers" : "${aws_msk_cluster.main["source"].bootstrap_brokers_sasl_iam}",
    "topics" : "ExampleTopic",
    "tasks.max" : "10",
    "key.converter" : " org.apache.kafka.connect.converters.ByteArrayConverter",
    "value.converter" : "org.apache.kafka.connect.converters.ByteArrayConverter",
    "replication.policy.class" : "com.amazonaws.kafka.samples.CustomMM2ReplicationPolicy",
    "replication.factor" : "3",
    "offset-syncs.topic.replication.factor" : "3",
    "sync.topic.acls.interval.seconds" : "20",
    "sync.topic.configs.interval.seconds" : "20",
    "refresh.topics.interval.seconds" : "20",
    "refresh.groups.interval.seconds" : "20",
    "producer.enable.idempotence" : "true",
    "consumer.group.id" : "mm2-msc",
    "source.cluster.max.poll.records" : "50000",
    "source.cluster.receive.buffer.bytes" : "33554432",
    "source.cluster.send.buffer.bytes" : "33554432",
    "source.cluster.max.partition.fetch.bytes" : "33554432",
    "source.cluster.message.max.bytes" : "37755000",
    "source.cluster.compression.type" : "gzip",
    "source.cluster.max.request.size" : "26214400",
    "source.cluster.buffer.memory" : "524288000",
    "source.cluster.batch.size" : "524288",
    "target.cluster.max.poll.records" : "20000",
    "target.cluster.receive.buffer.bytes" : "33554432",
    "target.cluster.send.buffer.bytes" : "33554432",
    "target.cluster.max.partition.fetch.bytes" : "33554432",
    "target.cluster.message.max.bytes" : "37755000",
    "target.cluster.compression.type" : "gzip",
    "target.cluster.max.request.size" : "26214400",
    "target.cluster.buffer.memory" : "524288000",
    "target.cluster.batch.size" : "52428",
    "source.cluster.security.protocol" : "SASL_SSL",
    "source.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "source.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "source.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
    "target.cluster.security.protocol" : "SASL_SSL",
    "target.cluster.sasl.mechanism" : "AWS_MSK_IAM",
    "target.cluster.sasl.jaas.config" : "software.amazon.msk.auth.iam.IAMLoginModule required;",
    "target.cluster.sasl.client.callback.handler.class" : "software.amazon.msk.auth.iam.IAMClientCallbackHandler"
  })
}
resource "aws_s3_object" "worker-config" {
  bucket  = aws_s3_bucket.configs.bucket
  key     = "worker/connect-distributed.properties"
  content = <<EOF
    bootstrap.servers=${aws_msk_cluster.main["target"].bootstrap_brokers_sasl_iam}
    group.id=mm2-worker
    key.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    key.converter.schemas.enable=true
    value.converter.schemas.enable=true
    offset.storage.topic=connect-offsets-mm2-worker
    offset.storage.replication.factor=3
    config.storage.topic=connect-configs-mm2-worker
    config.storage.replication.factor=3
    status.storage.topic=connect-status-mm2-worker
    status.storage.replication.factor=3
    offset.flush.interval.ms=10000
    connector.client.config.override.policy=All
    security.protocol=SASL_SSL
    sasl.mechanism = AWS_MSK_IAM
    sasl.jaas.config = software.amazon.msk.auth.iam.IAMLoginModule required;
    sasl.client.callback.handler.class = software.amazon.msk.auth.iam.IAMClientCallbackHandler
    producer.security.protocol=SASL_SSL
    producer.sasl.mechanism = AWS_MSK_IAM
    producer.sasl.jaas.config = software.amazon.msk.auth.iam.IAMLoginModule required;
    producer.sasl.client.callback.handler.class = software.amazon.msk.auth.iam.IAMClientCallbackHandler
    EOF
}


