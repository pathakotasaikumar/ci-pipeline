from __future__ import print_function
import boto3, logging, time, os

os.environ["HTTP_PROXY"] = "http://proxy.qcpaws.qantas.com.au:3128"
os.environ["HTTPS_PROXY"] = "https://proxy.qcpaws.qantas.com.au:3128"
os.environ["NO_PROXY"] = "s3-ap-southeast-2.amazonaws.com,.s3-ap-southeast-2.amazonaws.com,.s3.amazonaws.com,.qcpaws.qantas.com.au,.aws.qcp"
logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('dynamodb')


def get_throughput(table_name):
    response = client.describe_table(TableName=table_name)

    throughput = {
        'read': response['Table']['ProvisionedThroughput']['ReadCapacityUnits'],
        'write': response['Table']['ProvisionedThroughput']['WriteCapacityUnits']
    }

    return throughput


def set_throughput(table_name, read_capacity, write_capacity):
    params = dict(TableName=table_name, ProvisionedThroughput=dict())

    if read_capacity is not None:
        params['ProvisionedThroughput']['ReadCapacityUnits'] = int(read_capacity)

    if write_capacity is not None:
        params['ProvisionedThroughput']['WriteCapacityUnits'] = int(write_capacity)

    try:
        client.update_table(**params)
    except Exception as e:
        if e.response['Error']['Code'] == 'ValidationException':
            logger.warn(e)
        else:
            logger.error(e)
            raise Exception(e)

    current_throughput = get_throughput(table_name)

    while int(read_capacity) != int(current_throughput['read']) or int(write_capacity) != int(current_throughput['write']):
        print('waiting for desired capacity' + read_capacity + " " + write_capacity)
        print('waiting for current capacity ' + str(current_throughput['read']) + " " + str(current_throughput['write']))
        current_throughput = get_throughput(table_name)
        time.sleep(5)

def handler(event, context):

    result = dict(event)
    table_name = result.get('TableName', None)
    read_capacity = result.get('SetReadCapacity', None)
    write_capacity = result.get('SetWriteCapacity', None)
    existing_capacity = result.get('ExistingCapacity', None)

    if existing_capacity is not None:
        logger.info('Resetting table to existing capacity')
        set_throughput(table_name, int(existing_capacity['read']), int(existing_capacity['write']))
    else:
        result['ExistingCapacity'] = get_throughput(table_name)

    try:
        if read_capacity is None:
            read_capacity = result['ExistingCapacity']['read']

        if write_capacity is None:
            write_capacity = result['ExistingCapacity']['write']

        set_throughput(table_name, read_capacity, write_capacity)

    except Exception as e:
        logger.error("Failed to set capacity on table " + table_name)
        raise Exception(e)

    return result