#!/usr/bin/env bash
set -e

function error_exit {
  echo "$1" 1>&2
  exit 1
}

configure_s3_versioning enable || error_exit "Unable to enable versioning on ${pipeline_AppBucketName}"
sleep 1

configure_s3_versioning status || error_exit "Unable to check versioning on ${pipeline_AppBucketName}"
sleep 1

configure_s3_versioning suspend || error_exit "Unable to suspend versioning on ${pipeline_AppBucketName}"