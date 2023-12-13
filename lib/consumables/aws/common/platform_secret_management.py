#!/usr/bin/env python3

import boto3
from botocore.config import Config
import json
import logging
import os
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)
region = 'ap-southeast-2'
failure_msg = "Failed to create SSM parameters."
success_msg = "Successfully created the SSM parameters."
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
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        if e.response['Error']['Code'] in 'ValidationError':
            parameters = get_ssm_parameters(sections_metadata, instanceid)
            if parameters:
                for secret in parameters:
                    delete_secret(secret.get('Name'))


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
        client.delete_parameter(Name=paramName)
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e


def put_parameter(metadata, instance, kms_key, key, value):
    logger.info("Applying the ssm parameter for instance id:- " + instance)
    name = '/platform/' + metadata['ams'] + '/' + metadata['qda'] + '/' + metadata['as'] + '/' + metadata['ase'] + '/' + metadata['branch'] + '/' + metadata['build'] + '/' + instance + '/' + key
    try:
        client.put_parameter(
                Name=name,
                Value=value,
                Overwrite=True,
                Type='SecureString',
                KeyId=kms_key
                )
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e


def read_secrets_from_s3(bucket, file_path):
    try:
        s3resource = boto3.resource('s3')
        secrets = json.loads(s3resource.Object(bucket, file_path).get()["Body"].read())
        return secrets
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e


def handler(event, context):
    logger.info(json.dumps(event))
    eventType = event.get('ExecutionType', None)
    instance = ''
    if eventType is None:
        message = json.loads(event[u'Records'][0][u'Sns'][u'Message'])
        logger.info("Parsing variables from Autoscale lifecyclehook")
        instance = message.get('EC2InstanceId', None)
        if instance is None:
            logger.info('Message did not include an instance ID; ignoring')
            return
        metadata = json.loads(message['NotificationMetadata'])
        kms_key = metadata['KmsId']
        asgname = message['AutoScalingGroupName']
        actiontoken = message['LifecycleActionToken']
        lifecyclehookname = message['LifecycleHookName']
        storage_bucket = metadata['SecretsStorageBucket']
        file_location = metadata['SecretsStorageFileLocation']
        sections_metadata = json.loads(metadata['Sections'])
    else:
        logger.info("Parsing variables for EC2 Instance")
        instance = event.get('EC2InstanceId')
        kms_key = os.environ.get('KmsId')
        storage_bucket = os.environ.get('SecretsStorageBucket')
        file_location = os.environ.get('SecretsStorageFileLocation')
        sections_metadata = json.loads(os.environ.get('Sections'))

    logger.info("EC2 Instance ID: %s" % instance)

    try:
        secrets = read_secrets_from_s3(storage_bucket, file_location)
        for secret_key in secrets:
            if put_parameter(sections_metadata,
                    instance,
                    kms_key,
                    secret_key,
                    encrypted_secret(secrets[secret_key], kms_key)) == 1:
                if eventType is None:
                    complete_asg_lifecycle(lifecyclehookname,
                            asgname,
                            actiontoken,
                            instance,
                            "ABANDON",
                            sections_metadata)
                logger.error(failure_msg)
                raise Exception(failure_msg)
    except Exception as e:
        if eventType is None:
            complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "ABANDON", sections_metadata)
        else:
            logger.error(e)
            raise Exception(failure_msg)

    logger.info(success_msg)
    if eventType is None:
        complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "CONTINUE", sections_metadata)


def encrypted_secret(value, kms_key):
    try:
        kclient = boto3.client('kms', config=config)
        response = kclient.encrypt(KeyId=kms_key, Plaintext=value)
        b = base64.b64encode(response['CiphertextBlob'])
        return b.decode('UTF-8')
    except Exception as e:
        msg = "Unexpected error: " + str(e)
        logger.error(msg)
        raise e
