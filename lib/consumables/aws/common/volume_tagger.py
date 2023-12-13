import boto3, json, logging, time
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

def add_tags(instance, tags):
    logger.info("Applying tags %s to %s", tags, instance)

    myTags = []
    secVolumes = []
    for tag in tags:
        if str(tag[u'key']) == "volumeIds":
            for volume in tag[u'value']:
                secVolumes.append(volume['VolumeId'])
            tags.remove(tag)
        else:
            logger.info({'Key' : str(tag[u'key']), 'Value' : str(tag[u'value'])})
            myTags.append({'Key' : str(tag[u'key']), 'Value' : str(tag[u'value'])})

    try:
        ec2 = boto3.client('ec2')
        resp = ec2.describe_instance_attribute(InstanceId=instance, Attribute='blockDeviceMapping')
        volumes = (resp[u'BlockDeviceMappings'])
        for volume in volumes:
            volume = volume[u'Ebs'][u'VolumeId']
            applyTag = True
            if secVolumes:
                for vol in secVolumes:
                    if volume == vol:
                        logger.info("Not applying the tags for secondary volume %s", vol)
                        applyTag = False
            if applyTag:
                logger.info("Applying tags %s to volume %s", tags, volume)
                resp = ec2.create_tags(Resources=[volume], Tags=myTags)

    except Exception as e:
        logger.error(e)

def handler(event, context):
    message = json.loads(event[u'Records'][0][u'Sns'][u'Message'])
    logger.info(message)

    instance = message['EC2InstanceId']
    metadata = message['NotificationMetadata']
    asgname = message['AutoScalingGroupName']
    actiontoken = message['LifecycleActionToken']
    lifecyclehookname = message['LifecycleHookName']

    add_tags(instance, json.loads(metadata))

    # Complete Lifecycle hook, irrelevant of success or failure
    logger.info("Completing lifecycle hook")
    complete_asg_lifecycle(lifecyclehookname, asgname, actiontoken, instance, "CONTINUE")