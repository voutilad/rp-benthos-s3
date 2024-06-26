terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.53.0"
    }
    random = {
      source = "hashicorp/random"
      version = "3.6.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Description = "Redpanda Connect Demo"
    }
  }
}

################################################################################
## Variables
################################################################################

variable "s3_bucket_name" {
  type = string
  description = "Name of the S3 bucket to create."
}

variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "aws_lambda_ext_arn" {
  type = string
  default = "arn:aws:lambda:us-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension-Arm64:11"
  description = "See https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html#arm64"
}

variable "role_name" {
  type = string
  description = "Name of the IAM role to create for managing S3 bucket access."
  default = "rp_connect_demo_role"
}

variable "redpanda_bootstrap" {
  type = string
  description = "Bootstrap server url for Redpanda cluster."
}

variable "redpanda_username" {
  type = string
  description = "Redpanda Kafka API user."
  default = "blobfish"
}

variable "redpanda_password" {
  type = string
  description = "Redpanda Kafka API password."
  sensitive = true
}

variable "redpanda_sasl_mechanism" {
  type = string
  description = "SASL mechanism to use for authentication."
  default = "SCRAM-SHA-256"
}

variable "redpanda_topic" {
  type = string
  description = "Redpanda topic to produce to."
  default = "documents"
}

variable "redpanda_use_tls" {
  type = bool
  description = "Use TLS when connecting to Redpanda?"
  default = true
}

variable "redpanda_delete_objects" {
  type = bool
  description = "Delete objects from S3 after processing?"
  default = true
}

################################################################################
## Data
################################################################################

data "aws_iam_policy_document" "rp_connect_demo_policy" {
  statement {
    effect = "Allow"
    actions = [ "s3:Get*", "s3:List*", "s3:Put*", "s3:DeleteObject" ]
    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "rp_connect_demo_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [ "secretsmanager:GetSecretValue" ]
    resources = [
      aws_secretsmanager_secret.redpanda_secret.arn
    ]
  }
}

data "aws_iam_policy" "lambda_exec_policy" {
  name = "AWSLambdaBasicExecutionRole"
}

data "aws_caller_identity" "current" {}

################################################################################
## Resources
################################################################################

# Secrets in AWS can't be deleted faster than 7 days. Use a
# psuedo-random suffix for demo purposes in case we need to destroy
# and recreate everything.
resource "random_integer" "suffix" {
  min = 100000
  max = 999999
}

# Create our bucket and set up some IAM policies and roles to manage access.
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "${var.s3_bucket_name}-"
  force_destroy = true
}

resource "aws_iam_policy" "bucket_policy" {
  name = "${var.s3_bucket_name}_policy"
  policy = data.aws_iam_policy_document.rp_connect_demo_policy.json
}

# Create our Secret for storing password and connectivity information.
resource "aws_secretsmanager_secret" "redpanda_secret" {
  name = "rp_connect_demo_secret-${resource.random_integer.suffix.result}"
}

resource "aws_secretsmanager_secret_version" "redpanda_secret_version" {
  secret_id = aws_secretsmanager_secret.redpanda_secret.id
  secret_string = jsonencode({
    RP_CONNECT_BROKER = var.redpanda_bootstrap
    RP_CONNECT_USERNAME = var.redpanda_username
    RP_CONNECT_PASSWORD = var.redpanda_password
    RP_CONNECT_SASL_MECH = var.redpanda_sasl_mechanism
    RP_CONNECT_TLS = var.redpanda_use_tls
  })
}

resource "aws_iam_policy" "secrets_read_policy" {
  name = "Allow-Reading-RP-Connect-Secrets"
  policy = data.aws_iam_policy_document.rp_connect_demo_secrets_policy.json
}

resource "aws_iam_role" "rp_connect_demo_role" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  managed_policy_arns = [
    data.aws_iam_policy.lambda_exec_policy.arn,
    aws_iam_policy.bucket_policy.arn,
    aws_iam_policy.secrets_read_policy.arn,
  ]
}

# Configure a layer for RPK.
resource "aws_lambda_layer_version" "layer_rpk" {
  filename = "layers/rpk.zip"
  layer_name = "rp_connect_demo_rpk_layer"
  compatible_runtimes = [ "provided.al2023" ]
  compatible_architectures = [ "arm64" ]
}

# Create another layer for the "Redpanda Connect" component of RPK.
resource "aws_lambda_layer_version" "layer_connect" {
  filename = "layers/connect.zip"
  layer_name = "rp_connect_demo_connect_layer"
  compatible_runtimes = [ "provided.al2023" ]
  compatible_architectures = [ "arm64" ]
}

# Assemble our Lambda using the above layers.
resource "aws_lambda_function" "lambda" {
  function_name = "rp_connect_demo_function"
  role = aws_iam_role.rp_connect_demo_role.arn

  filename = "layers/app.zip"
  handler = "unused"
  runtime = "provided.al2023"
  architectures = [ "arm64" ]

  # The demo seems to work well with 512MiB memory, maybe because it means AWS
  # ends up providing a larger vCPU time slice. If you process large files, you
  # should increase this appropriately.
  memory_size = 512

  # You may want to tune the timeout, but in general the 3 second default does
  # not work for this demo! 5 minutes seems to work well in most cases.
  timeout = 300

  layers = [
    aws_lambda_layer_version.layer_rpk.arn,
    aws_lambda_layer_version.layer_connect.arn,
    var.aws_lambda_ext_arn,
  ]

  environment {
    variables = {
      RP_CONNECT_TOPIC = var.redpanda_topic
      RP_CONNECT_DELETE_OBJECTS = var.redpanda_delete_objects
      RP_CONNECT_SECRETS_ID = aws_secretsmanager_secret.redpanda_secret.id
    }
  }
}

# Use an alias to point to the latest version of our function.
resource "aws_lambda_alias" "lambda_latest" {
  name = "${aws_lambda_function.lambda.function_name}_alias"
  function_name = aws_lambda_function.lambda.function_name
  function_version = "$LATEST"
}

# Allow S3 to invoke the latest version of our Lambda Function.
resource "aws_lambda_permission" "allow_s3" {
  statement_id = "AllowRPConnectExecutionFromS3"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal = "s3.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id
  source_arn = aws_s3_bucket.bucket.arn

  qualifier = aws_lambda_alias.lambda_latest.name
}

# Wire up the notification from the Bucket to the Lambda function.
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_alias.lambda_latest.arn
    events = [ "s3:ObjectCreated:*" ]
  }

  depends_on = [
    aws_lambda_permission.allow_s3
  ]
}
