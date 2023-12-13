#!/bin/bash
set -e

DB_PASSWORD=`kms_decrypt $aurora_MyDBClusterMasterUserPassword`

SQL_RESULT=`mysql -h "$aurora_MyDBClusterDeployDnsName" --user="$aurora_MyDBClusterMasterUsername" --password=$DB_PASSWORD  --execute="status;" | grep "TCP port:" | cut -d ':' -f2 | xargs`

echo "SQL RESULT is : $SQL_RESULT"

[ "$SQL_RESULT" = "$aurora_MyDBClusterEndpointPort" ] || exit 1

exit 0