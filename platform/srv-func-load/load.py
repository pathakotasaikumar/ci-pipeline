from __future__ import print_function
import boto3, botocore.config, json, logging, re, os, uuid

os.environ["HTTP_PROXY"] = "http://proxy.qcpaws.qantas.com.au:3128"
os.environ["HTTPS_PROXY"] = "https://proxy.qcpaws.qantas.com.au:3128"
os.environ["NO_PROXY"] = "s3-ap-southeast-2.amazonaws.com,.s3-ap-southeast-2.amazonaws.com,.s3.amazonaws.com,.qcpaws.qantas.com.au,.aws.qcp"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.client('dynamodb')

def batch_write_items(items, table_name):
    batch_item_list = {}

    batch_item_count = 0
    batch_item_list[table_name] = []

    for item in items:

        new_item = {'PutRequest': {'Item': item}}

        if len(batch_item_list) > 0 and batch_item_count == 25:
            dynamodb.batch_write_item(RequestItems=batch_item_list)
            batch_item_count = 0
            batch_item_list[table_name] = []
        else:
            batch_item_list[table_name].append(new_item)
            batch_item_count += 1

    if batch_item_count > 0:
        dynamodb.batch_write_item(RequestItems=batch_item_list)
        batch_item_list[table_name] = []

def handler(event, context):

    result = dict(event)

    table_name = event.get('TableName', None)
    attributes = event.get('Attributes', 10)
    item_count = event.get('ItemCount', 10000)
    batch_size = event.get('BatchSize', 1000)

    batch_item_list = []

    for x in range(1, batch_size):
        item = {'hashKey': {'S': str(uuid.uuid4())}}
        for i in range(1, int(attributes)):
            item['attr'+str(i)]={'S': str(uuid.uuid4())}

        batch_item_list.append(item)

    batch_write_items(batch_item_list, table_name)

    result['TableName'] = table_name
    result['Attributes'] = attributes
    result['ItemCount'] = item_count - batch_size

    return result