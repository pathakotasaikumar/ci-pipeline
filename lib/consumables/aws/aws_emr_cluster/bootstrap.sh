#!/bin/bash
set -e

S3_BASEPATH="$1"

function s3_get {
  S3_FILENAME=$1
  DEST_FILENAME=$2
  echo "Downloading S3 object $S3_FILENAME to file $DEST_FILENAME"
  mkdir -p `dirname $DEST_FILENAME`
  aws s3 cp "$S3_FILENAME" "$DEST_FILENAME"
}

# Download and unpack app payload
s3_get "$S3_BASEPATH/app.tar.gz" "/tmp/app.tar.gz"
DEST_DIR="/home/hadoop/payload/"
echo "Unpacking /tmp/app.tar.gz to $DEST_DIR"
mkdir -p "$DEST_DIR"
tar -xzvf "/tmp/app.tar.gz" -C "$DEST_DIR"

# Download context and bamboo vars
s3_get "$S3_BASEPATH/bamboo-vars.conf" "/home/hadoop/bamboo-vars.conf"
chmod 440 /home/hadoop/bamboo-vars.conf

# Add proxy to /etc/profile.d/ scripts
s3_get "$S3_BASEPATH/set_qcp_proxy.sh" "/home/hadoop/set_qcp_proxy.sh"
sudo chown root:root /home/hadoop/set_qcp_proxy.sh
sudo chmod 555 /home/hadoop/set_qcp_proxy.sh
sudo mv /home/hadoop/set_qcp_proxy.sh /etc/profile.d/set_qcp_proxy.sh

s3_get "$S3_BASEPATH/context" "/home/hadoop/context.sh"
sudo chown root:hadoop /home/hadoop/context.sh
sudo chmod 750 /home/hadoop/context.sh
sudo mv /home/hadoop/context.sh /etc/profile.d/context.sh

# link context file to home for backward compatibility
sudo ln -s /etc/profile.d/context.sh /home/hadoop/context

s3_get "$S3_BASEPATH/kms_encrypt.sh" "/home/hadoop/kms_encrypt"
s3_get "$S3_BASEPATH/kms_decrypt.sh" "/home/hadoop/kms_decrypt"
s3_get "$S3_BASEPATH/kms_decrypt_file.sh" "/home/hadoop/kms_decrypt_file"
s3_get "$S3_BASEPATH/kms_encrypt_file.sh" "/home/hadoop/kms_encrypt_file"
sudo chown root:root /home/hadoop/kms_*
sudo chmod 755 /home/hadoop/kms_*
sudo mv /home/hadoop/kms_* /usr/local/sbin/

# link aws tools to support helper scripts
sudo ln -s /usr/bin/aws /usr/local/bin/aws

exit 0