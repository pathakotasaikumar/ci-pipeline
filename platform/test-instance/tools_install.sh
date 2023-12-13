function validate_exit_code()
{
    CODE=$1
    MGS=$2
 
    [ $CODE -eq 0 ] && echo "Exit code is 0, continue..."
    [ $CODE -ne 0 ] && echo "Exising with non-zero code [$CODE] - $MGS" && exit $CODE
}

echo "Installing postgresql package..."
yum clean all
yum makecache
yum install mysql nc nfs-utils -y
validate_exit_code $? "Cannot install postgresql package"

yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install -y postgresql12-server
yum install postgresql12 postgresql12-server postgresql12-contrib postgresql12-libs -y
/usr/pgsql-12/bin/postgresql-12-setup initdb
systemctl enable postgresql-12.service
systemctl start postgresql-12

exit 0