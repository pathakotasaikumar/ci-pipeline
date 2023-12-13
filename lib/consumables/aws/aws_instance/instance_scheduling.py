from __future__ import print_function

import boto3
import logging
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):

    ec2_client = boto3.client('ec2')
    result = dict(event)

    try:
        instance_id = event['InstanceId']
        action = event['Action']
    except KeyError as e:
        raise Exception("Invalid Parameters")

    if action == 'stop':
        try:
            logger.info("instance_id: " + instance_id + " - executing 'stop'")
            
            response = ec2_client.stop_instances(
                InstanceIds=[
                    instance_id,
                ],
                DryRun=False,
                Force=True
            )
            result['DesiredStatus'] = 'stopped'
            result['Action'] = 'check'
            result['Checks'] = 0
            result['Status'] = response['StoppingInstances'][0]['CurrentState']['Name']
            
            logger.info("instance_id: " + instance_id + " - response: " +  json.dumps(response))
            logger.info("instance_id: " + instance_id + " - result: "   +  json.dumps(result))
            
            return result
        except Exception as e:
            logger.error(e)
            raise Exception(e)

    elif action == 'start':
        try:
            logger.info("instance_id: " + instance_id + " - executing 'start'")
            
            response = ec2_client.start_instances(
                InstanceIds=[
                    instance_id,
                ],
                DryRun=False
            )
            result['DesiredStatus'] = 'running'
            result['Action'] = 'check'
            result['Checks'] = 0
            result['Status'] = response['StartingInstances'][0]['CurrentState']['Name']
            
            logger.info("instance_id: " + instance_id + " - response: " +  json.dumps(response))
            logger.info("instance_id: " + instance_id + " - result: "   +  json.dumps(result))
            
            return result
        except Exception as e:
            logger.error(e)
            raise Exception(e)

    else:
        logger.error("Invalid action: " + action)
        raise Exception("Invalid action")
