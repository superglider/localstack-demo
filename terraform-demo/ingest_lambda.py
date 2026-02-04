import json, uuid, os
import boto3

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE = os.environ["TABLE_NAME"]
QUEUE_URL = os.environ["QUEUE_URL"]

def handler(event, context):
    body = json.loads(event["body"])
    request_id = str(uuid.uuid4())
    
    # store request
    dynamodb.Table(TABLE).put_item(Item={
        "id": request_id,
        "payload": body
    })
    
    # send for processing
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({
            "id": request_id,
            "payload": body
        })
    )
    
    return {
        "statusCode": 200,
        "body": json.dumps({"id": request_id})
    }
