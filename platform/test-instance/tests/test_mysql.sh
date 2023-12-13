#!/bin/bash
set -e

source /root/context
source /root/bamboo-vars.conf

function error_exit {
  echo "$1" 1>&2
  exit 1
}

db_host=${mysql_DatabaseDeployDnsName}
db_name="testdatabase"
if [ "$mysql_BuildNumber" -gt "$autoheal_eni_BuildNumber" ]; then
    echo "The current mysql rds instance build number($mysql_BuildNumber) is  greater than the persisted build component autoheal eni($autoheal_eni_BuildNumber)."
    echo "Verify the table and rows are exist or not."
    db_root_user="admin"
    db_root_password=$(kms_decrypt "AQECAHjVEOqvSfCPI5NXjju1itIbcWZyX1RTOhkv8xn3SOhiPwAAAGkwZwYJKoZIhvcNAQcGoFowWAIBADBTBgkqhkiG9w0BBwEwHgYJYIZIAWUDBAEuMBEEDOhe71kK9wuftzRYOwIBEIAm3RSpM1yYla64efva+N6QyRMLgiqgscDSm0ZEClUULT8FsS/IZzY=")

    SQL_RESULT=`mysql -h $db_host -u $db_root_user --password=$db_root_password  --execute="status;" | grep "TCP port:" | cut -d ':' -f2 | xargs`

    echo "SQL RESULT is : $SQL_RESULT"

    [ "$SQL_RESULT" = "$mysql_DatabaseEndpointPort" ] || exit 1

    old_data_exist=$(mysql -h ${db_host} -u ${db_root_user} --password=${db_root_password} -e "select * from ${db_name}.buildtable;")

    [[ -z $old_data_exist ]] && error_exit "Cannot access the table from the database ${db_name} on host ${db_host}"

    echo -e "Previous build data exist and the value is : \\n $old_data_exist"

    echo "Verify the Password for the RDS is  reset or not for the restored DB"

    DB_PASSWORD=`kms_decrypt $mysql_DatabaseMasterUserPassword`
    root_user="root"

    SQL_RESULT=`mysql -h "$mysql_DatabaseDeployDnsName" --user="$root_user" --password=$DB_PASSWORD  --execute="status;" | grep "TCP port:" | cut -d ':' -f2 | xargs`

    echo "SQL RESULT is : $SQL_RESULT"

    [ "$SQL_RESULT" = "$mysql_DatabaseEndpointPort" ] || exit 1

else
    echo "The mysql rds instance build number($mysql_BuildNumber) is  equal to the current deployed build number."

    echo "Creating admin user for database"
    db_root_user=${mysql_DatabaseMasterUsername}
    db_root_password=$(kms_decrypt $mysql_DatabaseMasterUserPassword)
    db_admin="admin"
    db_admin_password=$(kms_decrypt "AQECAHjVEOqvSfCPI5NXjju1itIbcWZyX1RTOhkv8xn3SOhiPwAAAGkwZwYJKoZIhvcNAQcGoFowWAIBADBTBgkqhkiG9w0BBwEwHgYJYIZIAWUDBAEuMBEEDOhe71kK9wuftzRYOwIBEIAm3RSpM1yYla64efva+N6QyRMLgiqgscDSm0ZEClUULT8FsS/IZzY=")
    # CHECK IF USER EXISTS and SET RIGHTS
    cat > /tmp/admin.sql <<EOL
        CREATE USER '$db_admin' IDENTIFIED BY '$db_admin_password';
        GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION CLIENT, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, CREATE USER, EVENT, TRIGGER ON *.*  TO '$db_admin' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
EOL

      admin_user_exist=$(mysql -h ${db_host} -u ${db_root_user} --password=${db_root_password} -e "SELECT user FROM mysql.user WHERE user='${db_admin}'")
      echo $admin_user_exist
      [[ -z ${admin_user_exist} ]] && $(mysql -h ${db_host} -u ${db_root_user} --password=${db_root_password} < /tmp/admin.sql) || \
      error_exit "Cannot create user ${db_admin} on  host ${db_host}"

      db_root_user=${db_admin}
      db_root_password=${db_admin_password}

      SQL_RESULT=`mysql -h $db_host -u $db_root_user --password=$db_root_password  --execute="status;" | grep "TCP port:" | cut -d ':' -f2 | xargs`

      echo "SQL RESULT is : $SQL_RESULT"

      [ "$SQL_RESULT" = "$mysql_DatabaseEndpointPort" ] || exit 1

      echo "################ Create database testdatabase  ################"
      # CHECK IF DATABASE EXISTS and CREATE IF NOT
      db_exist=$(mysql -h ${db_host} -u ${db_root_user} --password=${db_root_password} -e "SHOW DATABASES LIKE '${db_name}'")
      echo "CREATE DATABASE ${db_name};" > /tmp/database.sql

      [[ -z $db_exist ]] && mysql -h $db_host -u $db_root_user --password=$db_root_password < /tmp/database.sql || \
          error_exit "Cannot create database ${db_name} on host ${db_host}"

      rm -f /tmp/database.sql

      echo "################ Create table and insert data into database  ################"
      cat > /tmp/table.sql <<EOL
          use '$db_name';
          create table buildtable(id int, vorta text);
          insert into buildtable values('$mysql_BuildNumber', '$db_host');
EOL
      mysql -h $db_host -u $db_root_user --password=$db_root_password < /tmp/table.sql || \
        error_exit "Cannot create table ${db_name} on host ${db_host}"




fi


exit 0
