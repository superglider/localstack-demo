
############################
# S3
############################
resource "aws_s3_bucket" "terraform_reports" {
  bucket = "terraform-demo-reports"
}

############################
# DynamoDB
############################
resource "aws_dynamodb_table" "terraform_incoming_requests" {
  name         = "terraform-IncomingRequests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "terraform_processed_requests" {
  name         = "terraform-ProcessedRequests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

############################
# SQS
############################
resource "aws_sqs_queue" "terraform_demo_queue" {
  name = "terraform-demo-queue"
}

############################
# Lambda: ingest
############################
resource "aws_lambda_function" "terraform_ingest" {
  function_name = "terraform-ingest"
  runtime       = "python3.9"
  handler       = "ingest_lambda.handler"
  role          = "arn:aws:iam::000000000000:role/dummy"

  filename         = "${path.module}/ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/ingest.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.terraform_incoming_requests.name
      QUEUE_URL  = aws_sqs_queue.terraform_demo_queue.id
    }
  }
}

############################
# Lambda: processor
############################
resource "aws_lambda_function" "terraform_processor" {
  function_name = "terraform-processor"
  runtime       = "python3.9"
  handler       = "process_lambda.handler"
  role          = "arn:aws:iam::000000000000:role/dummy"

  filename         = "${path.module}/process.zip"
  source_code_hash = filebase64sha256("${path.module}/process.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.terraform_processed_requests.name
      BUCKET    = aws_s3_bucket.terraform_reports.bucket
    }
  }
}

############################
# SQS → Lambda mapping
############################
resource "aws_lambda_event_source_mapping" "terraform_sqs_mapping" {
  event_source_arn = aws_sqs_queue.terraform_demo_queue.arn
  function_name    = aws_lambda_function.terraform_processor.arn
}

############################
# API Gateway
############################
resource "aws_api_gateway_rest_api" "terraform_api" {
  name = "terraform-demo-api"
}

resource "aws_api_gateway_resource" "terraform_ingest_resource" {
  rest_api_id = aws_api_gateway_rest_api.terraform_api.id
  parent_id   = aws_api_gateway_rest_api.terraform_api.root_resource_id
  path_part   = "ingest"
}

resource "aws_api_gateway_method" "terraform_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
  resource_id   = aws_api_gateway_resource.terraform_ingest_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "terraform_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.terraform_api.id
  resource_id = aws_api_gateway_resource.terraform_ingest_resource.id
  http_method = aws_api_gateway_method.terraform_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.terraform_ingest.invoke_arn
}

############################
# Allow API Gateway → Lambda
############################
resource "aws_lambda_permission" "terraform_apigw_permission" {
  statement_id  = "AllowAPIGatewayInvokeTerraform"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraform_ingest.function_name
  principal     = "apigateway.amazonaws.com"
}

############################
# API Deployment + Stage
############################
resource "aws_api_gateway_deployment" "terraform_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.terraform_api.id

  triggers = {
    redeploy = sha1(jsonencode(aws_api_gateway_rest_api.terraform_api))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.terraform_post_method,
    aws_api_gateway_integration.terraform_lambda_integration
  ]
}

resource "aws_api_gateway_stage" "terraform_stage" {
  deployment_id = aws_api_gateway_deployment.terraform_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
  stage_name    = "local"
}
