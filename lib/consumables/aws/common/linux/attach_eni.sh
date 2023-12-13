#!/bin/bash
#
# Attach an Eni to this instance
# Obtain Private ip address and configure routing
#

if [ $# -eq 2 ]; then
  ENI_ID=$1
  DEVICE_INDEX=$2
elif [ $# -eq 1 ]; then
  ENI_ID=$1
  DEVICE_INDEX=1
else
  (>&2 echo "Usage: attach_eni <eni-id> [<device-index>]")
  exit 1
fi

# Determine the path to the aws cli tools
if [[ -f /usr/local/bin/aws ]]; then
  AWS="/usr/local/bin/aws"
elif [[ -f /usr/bin/aws ]]; then
  AWS="/usr/bin/aws"
else
  fail "Unable to locate AWS CLI tools. Cannot continue."
fi

MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
INSTANCE_ID=$(/usr/bin/curl -s -m 3 -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id)



ETH0MAC=$(/sbin/ifconfig -a | grep eth0 | perl -ne 'm|HWaddr\ (\S+)| and print lc $1')
ETH0SUBNET=$(/usr/bin/curl -s -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/${ETH0MAC}/subnet-ipv4-cidr-block)
ETH0GATEWAY=$(/sbin/ip r | grep default | awk '{print $3}')
ETH0NETMASK=$(echo ${ETH0SUBNET} | perl -ne 'm|\/(\d+)| and print $1')
ETH0BCAST=$(ifconfig eth0 | grep Bcast | perl -ne 'm|Bcast:(\S+)\ | and print $1')

$AWS ec2 attach-network-interface --network-interface-id $ENI_ID --region $REGION --instance-id $INSTANCE_ID --device-index $DEVICE_INDEX

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "Network Interface '$ENI_ID' was attached successfully"
else
  echo "ERROR: Error during attachment of Network Interface '$ENI_ID'"
  exit $EXIT_CODE
fi

ENI_IP=$($AWS ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region $REGION --query "NetworkInterfaces[0].PrivateIpAddresses[0].PrivateIpAddress" --output text)

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "Obtained private IP for $ENI_ID : $ENI_IP"
else
  echo "ERROR: Error obtaining IP address for '$ENI_ID'"
  exit $EXIT_CODE
fi


# Wait for the network interface attachment to show up
echo "Waiting for attached network interface to appear on instance"

for ATTEMPT in `seq 1 20`; do
  /sbin/ip link show "eth${DEVICE_INDEX}"
  [ $? -eq 0 ] && break;
  [ $ATTEMPT -eq 20 ] && echo "ERROR: Timed out waiting for network interface to appear on instance" && exit 1
  sleep 5
done

# Plumb the ENI interface (add policy based routes)
echo "Adding policy-based routes for the attached network interface"
/sbin/ip link set eth${DEVICE_INDEX} up
/sbin/ip addr add ${ENI_IP}/${ETH0NETMASK} broadcast ${ETH0BCAST} dev eth${DEVICE_INDEX}
/sbin/ip route add ${ETH0SUBNET} dev eth${DEVICE_INDEX} proto kernel scope link src ${ENI_IP} table 1
/sbin/ip route add default via ${ETH0GATEWAY} dev eth1 table 1
/sbin/ip rule add from ${ENI_IP} lookup 1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  (>&2 echo "Network Interface '$ENI_ID' was attached successfully")
  exit 0
else
  (>&2 echo "ERROR: Error during attachment of Network Interface '$ENI_ID'")
  exit $EXIT_CODE
fi
