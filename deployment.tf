#
# This Terraform file is necessary to configure the basic
# infrastructure around the Optimize lambda function

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_key" {
  type    = string
  default = ""
}

provider "aws" {
  region     = "us-west-2"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      environment = terraform.workspace
      workspace   = terraform.workspace
    }
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_lambda_function" "optimize_lambda" {
  description   = "A simple lambda for optimizing a Delta table"
  filename      = "target/lambda/lambda-delta-optimize/bootstrap.zip"
  function_name = "delta-optimize"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "provided"
  runtime       = "provided.al2"

  environment {
    variables = {
      RUST_LOG = "info"
    }
  }
}

resource "aws_cloudwatch_event_rule" "every_hour" {
  name                = "execute-every-hour"
  description         = "Simple CloudWatch Event rule that triggers every hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "check_lambda_every_hour" {
  rule      = aws_cloudwatch_event_rule.every_hour.name
  target_id = "delta-optimize"
  arn       = aws_lambda_function.optimize_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_function" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.optimize_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_hour.arn
}
