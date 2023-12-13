#/usr/bin/env bash

set -xe

if [ "$1" = "local" ]; then
  echo "Building local package"
  COMPONENT_DIR=$PWD
  PAYLOAD_DIR=${COMPONENT_DIR}/tmp_payload
  mkdir -p ${PAYLOAD_DIR}
fi

echo "Building in ${COMPONENT_DIR}"
staging_dir=${COMPONENT_DIR}/staging
mkdir -p ${staging_dir}

cp ${COMPONENT_DIR}/*.py ${staging_dir}

cd ${staging_dir}
zip -r ${PAYLOAD_DIR}/package.zip *
cd ${COMPONENT_DIR}

rm -rf ${staging_dir}