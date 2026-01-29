import boto3
import json
import logging
import os
from datetime import datetime, timezone

#set logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients
ec2 = boto3.client('ec2')
sns = boto3.client('sns')

# env vars for arn's and instance ID
INSTANCE_ID = os.environ[ "INSTANCE_ID"]
SNS_TOPIC_ARN = os.environ[ "SNS_TOPIC_ARN"]

def _safejson(obj):
    try:
        return json.dumps(obj, default=str)
    except Exception:
        return str(obj)
    
def lambda_handler(event, context):
    now = datetime.now(timezone.utc).isoformat()

    logger.info("Lambda function triggered by event: %s",  _safejson(event))

    #set API gateway event - if payload is received via webhook through API gateway
    payload = event
    if isinstance(event, dict) and "body" in event and event["body"]:
        try:
            payload = json.loads(event["body"])
        except Exception:
            payload = {"raw_body": event["body"]}

    try:
        ec2.reboot_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f"EC2 instance {INSTANCE_ID} reboot initiated successfully.") 

        message = f"EC2 instance {INSTANCE_ID} has been successfully rebooted by the Lambda function."
        subject = "[EC2 Alert] Instance Rebooted"

        # Publish notification to SNS
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=subject
        )
        logger.info(f"SNS notification sent to topic {SNS_TOPIC_ARN}")

        return {
            'statusCode': 200,
            'body': json.dumps('Instance rebooted and notification sent.')
        }
    
    except Exception as e:
        logger.error(f"Error rebooting EC2 instance or sending SNS notification: {e}")
        
        # Send error notification to SNS
        error_message = f"An error occurred while trying to reboot EC2 instance {INSTANCE_ID}: {str(e)}"
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=error_message,
            Subject="[EC2 Alert] Error during instance reboot"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {e}")
        }
       

    



