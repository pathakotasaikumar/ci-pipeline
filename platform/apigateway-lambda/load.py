from __future__ import print_function
import boto3, botocore.config, json, logging, re, os, uuid


logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(event)
    if event['path'] == '/lambdaBuild':
        return { 'buildNumber' : os.environ['Build']}
    elif event['path'] == '/lambdaEnvironment':
        return { 'environement' : os.environ['Environment']}
    else:
        msg = { 'msg' : 'Unknown build path used.' }
        raise Exception(msg)
