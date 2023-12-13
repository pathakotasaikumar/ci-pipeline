from __future__ import print_function
import boto3, logging, os

os.environ["HTTP_PROXY"] = "http://proxy.qcpaws.qantas.com.au:3128"
os.environ["HTTPS_PROXY"] = "https://proxy.qcpaws.qantas.com.au:3128"
os.environ["NO_PROXY"] = "s3-ap-southeast-2.amazonaws.com,.s3-ap-southeast-2.amazonaws.com,.s3.amazonaws.com,.qcpaws.qantas.com.au,.aws.qcp"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.client('dynamodb')

def handler(event, context):
    logger.info(event)