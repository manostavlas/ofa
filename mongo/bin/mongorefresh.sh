#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


#!/bin/ksh
# set -xv

server=$1
database=$2
host=$3
port=$4


#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: mongorefresh.sh  [SERVER] [DATABASE] [HOSTNAME] [PORT]
##
##
## Paremeter:
##
## SERVER:
##          Name of the instance,eq FCSEV2
## DATABASE
##          Name of database, eg DataHub
##
## HOST_NAME:
##      Name of the HOST_NAME the mongodb are using
##
## PORT:
##      Number of the port
##
## refresh a specific database, 
##
#
__EOF
return 0
}

LogCons "Start  refresh Time: ${TimeStamp}"
LogCons "Host name: $host IP: $MongoHostIp, IP'(s) on server: $IpOnServer,server: $server,port: $port,host:$host,DATABASE: $database"


myfiles=$(ls -ltr /backup/$database/mongodump/$database*.gz 2> /dev/null | awk '{print substr($9,'${#database}'-10)}' )



mongorestore --drop -d $database --host $host  --port $port  -u dba --authenticationDatabase "admin"  --gzip  --archive=$myfiles -p $MmDp 
