# ------------------------------------------------------------------------------------------------------------
# Provider
# ------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}



# ------------------------------------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------------------------------------

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-${random_id.bucket_suffix.hex}"

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Application = "Noughts and Crosses"
  }
}



# ------------------------------------------------------------------------------------------------------------
# S3 Frontend Bucket
# ------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket = local.bucket_name

  tags = local.common_tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}



# ------------------------------------------------------------------------------------------------------------
# S3 Ownership Controls
# ------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}



# ------------------------------------------------------------------------------------------------------------
# S3 Public Access Block
# ------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



# ------------------------------------------------------------------------------------------------------------
# S3 Server-Side Encryption
# ------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}



# ------------------------------------------------------------------------------------------------------------
# DynamoDB Game Statistics Table
# ------------------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "game_stats" {
  name         = "${var.project_name}-stats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = local.common_tags
}



# ------------------------------------------------------------------------------------------------------------
# Lambda Source Package
# ------------------------------------------------------------------------------------------------------------

data "archive_file" "game_stats_lambda" {
  type        = "zip"
  output_path = "${path.module}/game_stats_lambda.zip"

  source {
    filename = "index.py"
    content  = <<LAMBDA_PY
import json
import os

import boto3


dynamodb = boto3.client("dynamodb")
TABLE_NAME = os.environ["STATS_TABLE_NAME"]
ALLOWED_RESULTS = {"user", "computer", "draw"}


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        },
        "body": json.dumps(body),
    }


def get_stats():
    item = dynamodb.get_item(
        TableName=TABLE_NAME,
        Key={"id": {"S": "global"}},
    ).get("Item", {})

    return {
        "gamesPlayed": int(item.get("games_played", {"N": "0"})["N"]),
        "userWins": int(item.get("user_wins", {"N": "0"})["N"]),
        "computerWins": int(item.get("computer_wins", {"N": "0"})["N"]),
        "draws": int(item.get("draws", {"N": "0"})["N"]),
    }


def update_stats(result):
    user_increment = 1 if result == "user" else 0
    computer_increment = 1 if result == "computer" else 0
    draw_increment = 1 if result == "draw" else 0

    updated = dynamodb.update_item(
        TableName=TABLE_NAME,
        Key={"id": {"S": "global"}},
        UpdateExpression="ADD games_played :one, user_wins :user, computer_wins :computer, draws :draw",
        ExpressionAttributeValues={
            ":one": {"N": "1"},
            ":user": {"N": str(user_increment)},
            ":computer": {"N": str(computer_increment)},
            ":draw": {"N": str(draw_increment)},
        },
        ReturnValues="ALL_NEW",
    )["Attributes"]

    return {
        "gamesPlayed": int(updated.get("games_played", {"N": "0"})["N"]),
        "userWins": int(updated.get("user_wins", {"N": "0"})["N"]),
        "computerWins": int(updated.get("computer_wins", {"N": "0"})["N"]),
        "draws": int(updated.get("draws", {"N": "0"})["N"]),
    }


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("rawPath", "")

    if method == "OPTIONS":
        return response(200, {"ok": True})

    if method == "GET" and path == "/stats":
        return response(200, get_stats())

    if method == "POST" and path == "/result":
        try:
            body = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            return response(400, {"error": "Request body must be valid JSON."})

        result = body.get("result")

        if result not in ALLOWED_RESULTS:
            return response(400, {"error": "Result must be user, computer, or draw."})

        return response(200, update_stats(result))

    return response(404, {"error": "Not found."})
LAMBDA_PY
  }
}



# ------------------------------------------------------------------------------------------------------------
# Lambda IAM Role and Permissions
# ------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "game_stats_lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "game_stats_lambda" {
  name               = "${var.project_name}-game-stats-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.game_stats_lambda_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "game_stats_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem"
    ]

    resources = [aws_dynamodb_table.game_stats.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "game_stats_lambda" {
  name   = "${var.project_name}-game-stats-lambda-policy"
  role   = aws_iam_role.game_stats_lambda.id
  policy = data.aws_iam_policy_document.game_stats_lambda.json
}

resource "aws_cloudwatch_log_group" "game_stats_lambda" {
  name              = "/aws/lambda/${var.project_name}-game-stats"
  retention_in_days = 7

  tags = local.common_tags
}



# ------------------------------------------------------------------------------------------------------------
# Game Statistics Lambda Function
# ------------------------------------------------------------------------------------------------------------

resource "aws_lambda_function" "game_stats" {
  function_name    = "${var.project_name}-game-stats"
  role             = aws_iam_role.game_stats_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.game_stats_lambda.output_path
  source_code_hash = data.archive_file.game_stats_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      STATS_TABLE_NAME = aws_dynamodb_table.game_stats.name
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.game_stats_lambda,
    aws_cloudwatch_log_group.game_stats_lambda
  ]
}



# ------------------------------------------------------------------------------------------------------------
# HTTP API Gateway
# ------------------------------------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "game_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "game_stats_lambda" {
  api_id                 = aws_apigatewayv2_api.game_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.game_stats.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_stats" {
  api_id    = aws_apigatewayv2_api.game_api.id
  route_key = "GET /stats"
  target    = "integrations/${aws_apigatewayv2_integration.game_stats_lambda.id}"
}

resource "aws_apigatewayv2_route" "post_result" {
  api_id    = aws_apigatewayv2_api.game_api.id
  route_key = "POST /result"
  target    = "integrations/${aws_apigatewayv2_integration.game_stats_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.game_api.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.game_stats.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.game_api.execution_arn}/*/*"
}



# ------------------------------------------------------------------------------------------------------------
# CloudFront Origin Access Control
# ------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac"
  description                       = "Allow CloudFront to read the private S3 frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}



# ------------------------------------------------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} static frontend"
  default_root_object = "index.html"
  price_class         = var.price_class

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed cache policy: CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}



# ------------------------------------------------------------------------------------------------------------
# S3 Bucket Policy for CloudFront Access
# ------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.frontend
  ]
}
