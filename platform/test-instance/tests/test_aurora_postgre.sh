#!/bin/bash
set -e

SQL_RESULT=`PASS=$(kms_decrypt "$aurora_postgre_MyDBClusterMasterUserPassword")  PGPASSWORD="$PASS" psql --host="$aurora_postgre_MyDBClusterDeployDnsName"  --username="$aurora_postgre_MyDBClusterMasterUsername"  --no-align --tuples-only --dbname=db_name  --command="select inet_server_port();"`
echo "SQL RESULT is : $SQL_RESULT"

[ "$SQL_RESULT" = "$aurora_postgre_MyDBClusterEndpointPort" ] || exit 1

exit 0