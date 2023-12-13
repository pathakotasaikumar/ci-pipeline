from botocore.vendored import requests
import json
import boto3
import cfnresponse

sns = boto3.client('sns')

def deleteTopics(topic_prefix):
    paginator = sns.get_paginator('list_topics')
    page_iterator = paginator.paginate()
    for page in page_iterator:
        for topic in page['Topics']:
            if topic_prefix in topic['TopicArn']:
                sns.delete_topic(
                    TopicArn=topic['TopicArn']
                )

def lambda_handler(event, context):
    responseStatus = 'FAILED'
    responseData = {}

    if event['RequestType'] == 'Create':
        responseStatus = 'SUCCESS'
    if event['RequestType'] == 'Update':
        responseStatus = 'SUCCESS'
    if event['RequestType'] == 'Delete':
        try:
            deleteTopics(event['ResourceProperties']['TopicPrefix'])
            responseStatus = 'SUCCESS'
        except Exception as e:
            print("deleteTopics(..) failed executing:" + str(e))
            responseStatus = 'FAILED'

    cfnresponse.send(event, context, responseStatus, responseData)
