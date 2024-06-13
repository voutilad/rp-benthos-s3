terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.53.0"
    }
  }
}

variable "s3_bucket_name" {
  type = string
}

variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "role_name" {
  type = string
  default = "rp_connect_demo_role"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Description = "Redpanda Connect Demo"
    }
  }
}

resource "aws_s3_bucket" "bucket" {
  bucket = var.s3_bucket_name
}

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

data "aws_iam_policy" "lambda_exec_policy" {
  name = "AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "bucket_policy" {
  name = "${var.s3_bucket_name}_policy"
  policy = data.aws_iam_policy_document.rp_connect_demo_policy.json
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
  ]
}

resource "aws_lambda_layer_version" "layer_rpk" {
  filename = "layers/rpk.zip"
  layer_name = "rp_connect_demo_rpk_layer"
  compatible_runtimes = [ "provided.al2023" ]
  compatible_architectures = [ "arm64" ]
}

resource "aws_lambda_layer_version" "layer_connect" {
  filename = "layers/connect.zip"
  layer_name = "rp_connect_demo_connect_layer"
  compatible_runtimes = [ "provided.al2023" ]
  compatible_architectures = [ "arm64" ]
}

resource "aws_lambda_function" "lambda" {
  function_name = "rp_connect_demo_function"
  role = aws_iam_role.rp_connect_demo_role.arn

  filename = "layers/app.zip"
  handler = "unused"
  runtime = "provided.al2023"
  architectures = [ "arm64" ]

  layers = [
    aws_lambda_layer_version.layer_rpk.arn,
    aws_lambda_layer_version.layer_connect.arn,
  ]
}

resource "aws_lambda_alias" "lambda_latest" {
  name = "${aws_lambda_function.lambda.function_name}_alias"
  function_name = aws_lambda_function.lambda.function_name
  function_version = "$LATEST"
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id = "AllowRPConnectExecutionFromS3"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda.arn
    events = [ "s3:ObjectCreated:*" ]
  }

  depends_on = [
    aws_lambda_permission.allow_s3
  ]
}
