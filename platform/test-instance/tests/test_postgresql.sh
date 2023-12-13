#!/bin/bash
set -e

export PGPASSWORD=`kms_decrypt $app_pipeline_postgresql_password`

echo "Below are connection details:"

echo "postgresql_DatabaseDeployDnsName: $postgresql_DatabaseDeployDnsName"
echo "postgresql_DatabaseMasterUsername: $postgresql_DatabaseMasterUsername"
echo "postgresql_DatabaseEndpointPort: $postgresql_DatabaseEndpointPort"

echo "Firing SQL query"

SQL_RESULT=`psql -h "$postgresql_DatabaseDeployDnsName" -U "$postgresql_DatabaseMasterUsername" -d pgdb -c "select 'port',setting from pg_settings where name = 'port'" | grep 'port' | cut -d '|' -f2`

echo "SQL RESULT is : $SQL_RESULT"

SQL_RESULT="$(echo -e "${SQL_RESULT}" | tr -d '[[:space:]]')"

[ "$SQL_RESULT" = "$postgresql_DatabaseEndpointPort" ] || exit 1
