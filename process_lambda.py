import json, os, boto3

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE = os.environ["TABLE_NAME"]
BUCKET = os.environ["BUCKET"]

def handler(event, context):
    for record in event["Records"]:
        msg = json.loads(record["body"])
        request_id = msg["id"]
        
        result = {
            "id": request_id,
            "status": "processed"
        }
        
        # store result
        dynamodb.Table(TABLE).put_item(Item=result)
        
        # write report to S3
        s3.put_object(
            Bucket=BUCKET,
            Key=f"reports/{request_id}.json",
            Body=json.dumps(result)
        )
