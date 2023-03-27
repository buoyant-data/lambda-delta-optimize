#
# This Terraform file is necessary to configure the basic
# infrastructure around the Optimize lambda function

resource "aws_lambda_function" "optimize_lambda" {
  description   = "A simple lambda for optimizing a Delta table"
  filename      = "target/lambda/lambda-delta-optimize/bootstrap.zip"
  function_name = "delta-optimize"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "provided"
  runtime       = "provided.al2"

  environment {
    variables = {
      AWS_S3_LOCKING_PROVIDER = "dynamodb"
      DATALAKE_LOCATION    = "s3://my-bucket/databases/my-table"
      RUST_LOG             = "info"
    }
  }
}

variable "s3_bucket_arn" {
  type        = string
  default     = "*"
  description = "The ARN for the S3 bucket that the optimize function will optimize"
}

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

    actions = [
      "sts:AssumeRole",
    ]
  }
}

resource "aws_iam_policy" "lambda_permissions" {
  name = "lambda-optimize-permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:*"]
        Resource = aws_dynamodb_table.delta-locking-table.arn
        Effect   = "Allow"
      },
      {
        Action   = ["s3:*"]
        Resource = var.s3_bucket_arn
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "iam_for_lambda" {
  name                = "iam_for_optimize_lambda"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = [aws_iam_policy.lambda_permissions.arn]
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

# The DynamoDb table is used for providing safe concurrent writes to delta
# tables. The name "delta_rs_lock_table" is the hard-coded default in delta-rs
resource "aws_dynamodb_table" "delta-locking-table" {
  name         = "delta_rs_lock_table"
  billing_mode = "PROVISIONED"
  # Default name of the partition key hard-coded in delta-rs
  hash_key       = "key"
  read_capacity  = 10
  write_capacity = 10

  attribute {
    name = "key"
    type = "S"
  }
}
