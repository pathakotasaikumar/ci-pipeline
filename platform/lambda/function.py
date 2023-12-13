from __future__ import print_function
import json, urllib, boto3, os

s3 = boto3.client('s3')

def handler(event, context):

    # Get the object from the event and show its content type
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.unquote_plus(event['Records'][0]['s3']['object']['key'].encode('utf8'))

    try:
        new_key_seq = key.split("/")

        object = new_key_seq.pop()
        new_key_seq.pop()
        new_key_seq.append('output')
        new_key_seq.append(object)
        new_key = "/".join(new_key_seq)

        copy_source = bucket + "/" + key
        s3.copy_object(CopySource=copy_source, Bucket=bucket, Key=new_key,  ServerSideEncryption='AES256')
        print('Successfully copied object from: {} to: {}'.format(copy_source, bucket + "/" + new_key))

    except Exception as e:
        print(e)
        print('Failed to copy object from: {} to: {}'.format(copy_source, bucket + "/" + new_key))
        raise e