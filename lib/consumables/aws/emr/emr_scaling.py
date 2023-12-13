from __future__ import print_function

import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
emr = boto3.client('emr')

def set_instance_group_count(instance_group, instance_count):
    params = [
        {
            'InstanceGroupId': instance_group,
            'InstanceCount': int(instance_count)
        }
    ]

    try:
        emr.modify_instance_groups(InstanceGroups=params)

    except Exception as e:
        logger.error(e)

def get_core_group(cluster):
    try:
        resp = emr.list_instance_groups(ClusterId=cluster)
        for group in resp.get('InstanceGroups'):
            if group.get('InstanceGroupType') == "CORE":
                return group.get('Id')

    except Exception as e:
        logger.error(e)

def handler(event, context):
    logger.info(json.dumps(event))

    instance_group = event['instance_group']
    instance_count = event['instance_count']

    if instance_group.lower() == "core":
        group_id = get_core_group(event['cluster'])
    else:
        group_id = instance_group

    if group_id is not None:
        print('Setting group {} to {}'.format(group_id, instance_count))
        set_instance_group_count(group_id, instance_count)
