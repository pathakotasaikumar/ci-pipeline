import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def complete_asg_lifecycle(hookname, asg, actiontoken, instanceid, result):
    try:
        asg_client = boto3.client('autoscaling')
        asg_response = asg_client.complete_lifecycle_action(
                LifecycleHookName=hookname,
                AutoScalingGroupName=asg,
                LifecycleActionToken=actiontoken,
                LifecycleActionResult=result,
                InstanceId=instanceid)
        logger.info(asg_response[u'ResponseMetadata'][u'HTTPStatusCode'])
    except Exception as e:
        logger.error(e)


def attach_volume(volume, instance, device):
    logger.info("Attaching %s to %s as %s", volume, instance, device)
    try:
        ec2 = boto3.client('ec2')
        ec2_response = ec2.attach_volume(VolumeId=volume, InstanceId=instance, Device=device)
        logger.info(ec2_response[u'ResponseMetadata'][u'HTTPStatusCode'])
    except Exception as e:
        logger.error(e)
        return 1


def handler(event, context):
    logger.info(json.dumps(event))
    message = json.loads(event[u'Records'][0][u'Sns'][u'Message'])
    logger.info(message)

    instance = message['EC2InstanceId']
    metadata = message['NotificationMetadata']
    asgname = message['AutoScalingGroupName']
    actiontoken = message['LifecycleActionToken']
    lifecyclehookname = message['LifecycleHookName']

    logger.info("EC2 Instance ID: %s" % instance)
    logger.info("Notification Metadata: %s" % metadata)

    for attachment in json.loads(metadata):
        volume = attachment['VolumeId']
        device = attachment['Device']
        if attach_volume(volume, instance, device) == 1:
            logger.info("Abandoning lifecycle hook")
            complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "ABANDON")
            return

    logger.info("Completing lifecycle hook")
    complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "CONTINUE")
