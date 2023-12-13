#!/usr/bin/env python3

import boto3
from botocore.config import Config
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
region = 'ap-southeast-2'
failure_msg = "Failed to delete SSM parameters."
success_msg = "Successfully delete the SSM parameters."
config = Config(
        region_name=region,
        retries={
            'max_attempts': 10,
            'mode': 'standard'
            }
        )
client = boto3.client('ssm', config=config)


def complete_asg_lifecycle(hookname, asg, actiontoken, instanceid, result, sections_metadata):
    try:
        asg_client = boto3.client('autoscaling', config=config)
        asg_response = asg_client.complete_lifecycle_action(
                LifecycleHookName=hookname,
                AutoScalingGroupName=asg,
                LifecycleActionToken=actiontoken,
                LifecycleActionResult=result,
                InstanceId=instanceid)
        logger.info(asg_response[u'ResponseMetadata'][u'HTTPStatusCode'])
    except Exception as e:
        if e.response['Error']['Code'] in 'ValidationError':
            parameters = get_ssm_parameters(sections_metadata, instanceid)
            if parameters:
                for secret in parameters:
                    delete_secret(secret.get('Name'))
        else:
            msg = "Unexpected error: " + str(e)
            logger.error(msg)


def get_ssm_parameters(metadata, instance):
    logger.info("Retrieving the ssm parameter for instance id:- " + instance)
    try:
        response = client.get_parameters_by_path(
                Path='/platform/' + metadata['ams'] + '/' + metadata['qda'] + '/' + metadata['as'] + '/' + metadata['ase'] + '/' + metadata['branch'] + '/' + metadata['build'] + '/' + instance
                )
        return response.get('Parameters')
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e


def delete_secret(paramName):
    logger.info("Deleting SSM Parameter " + paramName)
    try:
        client.delete_parameter(
                Name=paramName
                )
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e


def handler(event, context):
    logger.info(json.dumps(event))
    message = json.loads(event[u'Records'][0][u'Sns'][u'Message'])
    logger.info("Parsing variables from Autoscale lifecyclehook")

    instance = message['EC2InstanceId']
    metadata = json.loads(message['NotificationMetadata'])
    asgname = message['AutoScalingGroupName']
    actiontoken = message['LifecycleActionToken']
    lifecyclehookname = message['LifecycleHookName']
    sections_metadata = json.loads(metadata['Sections'])
    logger.info("EC2 Instance ID: %s" % instance)

    try:
        parameters = get_ssm_parameters(sections_metadata, instance)
        if not parameters:
            complete_asg_lifecycle(lifecyclehookname,
                    asgname,
                    actiontoken,
                    instance,
                    "CONTINUE",
                    sections_metadata)
        return

        for secret in parameters:
            delete_secret(secret.get('Name'))

        logger.info(success_msg)
    except Exception as e:
        logger.error(e)
        complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "CONTINUE", sections_metadata)
