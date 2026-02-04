###############################
#S3 bucket

awslocal s3 mb s3://demo-reports

###############################
#DynamoDB

awslocal dynamodb create-table `
  --table-name IncomingRequests `
  --attribute-definitions AttributeName=id,AttributeType=S `
  --key-schema AttributeName=id,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST

awslocal dynamodb create-table `
  --table-name ProcessedRequests `
  --attribute-definitions AttributeName=id,AttributeType=S `
  --key-schema AttributeName=id,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST

###############################
#SQS queue

$QUEUE_URL = awslocal sqs create-queue `
  --queue-name demo-queue `
  --query 'QueueUrl' `
  --output text


###############################
#compress the python files

Compress-Archive -Path ingest_lambda.py -DestinationPath ingest.zip -Force
Compress-Archive -Path process_lambda.py -DestinationPath process.zip -Force


###############################
#create ingest lambda

awslocal lambda create-function `
  --function-name ingest `
  --runtime python3.9 `
  --handler ingest_lambda.handler `
  --zip-file fileb://ingest.zip `
  --role arn:aws:iam::000000000000:role/dummy `
  --environment Variables="{TABLE_NAME=IncomingRequests,QUEUE_URL=$QUEUE_URL}"

###############################
#create process lambda

awslocal lambda create-function `
  --function-name processor `
  --runtime python3.9 `
  --handler process_lambda.handler `
  --zip-file fileb://process.zip `
  --role arn:aws:iam::000000000000:role/dummy `
  --environment Variables="{TABLE_NAME=ProcessedRequests,BUCKET=demo-reports}"

###############################
# invoke process lambda from SQS messages


awslocal lambda create-event-source-mapping `
  --function-name processor `
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:demo-queue

###############################
# API GATEWAY


#CREATE REST API

$API_ID = awslocal apigateway create-rest-api `
  --name demo-api `
  --query id `
  --output text

#GET API ID

$ROOT_ID = awslocal apigateway get-resources `
  --rest-api-id $API_ID `
  --query 'items[0].id' `
  --output text

#CREATE INGEST API PATH

$RESOURCE_ID = awslocal apigateway create-resource `
  --rest-api-id $API_ID `
  --parent-id $ROOT_ID `
  --path-part ingest `
  --query id `
  --output text

#CREATE POST METHOD

awslocal apigateway put-method `
  --rest-api-id $API_ID `
  --resource-id $RESOURCE_ID `
  --http-method POST `
  --authorization-type NONE

#CREATE INTEGRATION OF API GATEWAY API WITH LAMBDA

awslocal apigateway put-integration `
  --rest-api-id $API_ID `
  --resource-id $RESOURCE_ID `
  --http-method POST `
  --type AWS_PROXY `
  --integration-http-method POST `
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ingest/invocations


#ADD PERMISSION TO INVOKE LAMBDA

awslocal lambda add-permission `
  --function-name ingest `
  --statement-id apigateway-test-1 `
  --action "lambda:InvokeFunction" `
  --principal apigateway.amazonaws.com

#DEPLOY API

awslocal apigateway create-deployment `
  --rest-api-id $API_ID `
  --stage-name local

