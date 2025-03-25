#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


#!/bin/ksh
# set -xv

MongoHost=$1
MongoAdminUser=$2
#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: mongodump_dump_bkp.sh  [HOST_NAME] [MONGO_ADMIN_USER]
##
##
## Paremeter:
##
## HOST_NAME:
##      Name of the HOST_NAME the mongodb are using
##
## MONGO_ADMIN_USER:
##      Name of the Mongodb admin user.
##
## Backup all Mongodb's on HOST_NAME, PORT: 27017
##
#
__EOF
return 0
}

#-----------------------------------------------------------
# function DbList
#-----------------------------------------------------------
# {
# mongo --username $MongoAdminUser -p 'DkMdFrGr1207$' --authenticationDatabase admin --host ${MongoHost} --port ${MongoPort} << __EOF | grep name | awk -F ":" '{print $2}' | sed 's/,//g'
# db.adminCommand( { listDatabases: 1 } )
# __EOF
# }
#-----------------------------------------------------------
# Main
#-----------------------------------------------------------

if [[ -z $MongoHost ]]
then
	usage
	LogError "Missing parameters"
	exit 1
fi

MongoPort="27017"

TimeStamp=$(date +%Y%m%d_%H%M%S)
DatabaseList=$(DbList | sed 's/"//g' | tr '\n' ' ')
PassWd="DkMdFrGr1207$"
MongoHostIp=$(nslookup $MongoHost | grep Address | tail -1 | awk '{print $2}')
IpOnServer=$(ifconfig -a | grep inet | grep -v "inet 127.0.0.1" | awk '{print $2}'| tr '\n' ' ')

LogCons "Start Time: ${TimeStamp}"
LogCons "Host name: $MongoHost IP: $MongoHostIp, IP'(s) on server: $IpOnServer"

	LocalIp=$(echo $IpOnServer | grep $MongoHostIp)
	if [[ -z $LocalIp ]]
	then
		LogError "ERROR: Host name are NOT the local server. Host Name: $MongoHost IP: $MongoHostIp, IP'(s) on server: $IpOnServer"	
		exit 1
	fi


LogCons "Databases to backup: $DatabaseList(Server: $MongoHost Port: $MongoPort)"

#Backup commands
if [[ -z $DatabaseList ]]
then
	LogError "ERROR: Getting database list...."
	exit 1
fi


RunMmDp
for i in $DatabaseList
do
	DbName=$i
	BackupDir="/backup/${DbName}/mongodump"
	BackupDirOld="/backup/${DbName}/mongodump/old_backup"
	DumpFile=${BackupDir}/${DbName}_${TimeStamp}.gz
	LogFile=${BackupDir}/${DbName}_${TimeStamp}.log
        mkdir -p $BackupDir
	mkdir -p $BackupDirOld
	echo "Delete old backups:"
	ls -lrt $BackupDirOld/* | LogStdInEcho
	rm -f $BackupDirOld/*
        LogCons "Move old backup from $BackupDir/* to $BackupDirOld"
	mv $BackupDir/*.* $BackupDirOld
	LogCons "Backup Database: $DbName"

	mongodump -h $MongoHost:$MongoPort -d $DbName -u $InIts -p $MmDp --authenticationDatabase admin --gzip --archive=$DumpFile > $LogFile 2>&1
	ExitCode=$?


	if [[ $ExitCode -ne 0 ]]
	then
		LogError "Error: Running mongodump -h $MongoHost:$MongoPort -d $DbName -u $MongoAdminUser -p xxxxxxx --authenticationDatabase $DbName --gzip --archive=$DumpFile"
		LogError "Log file: $LogFile"
		exit 127
	else 
		LogCons "Dump file: $DumpFile"
		LogCons "Log file: $LogFile"
	fi
done

# Backup conf file
MongoConfFile=$(ps -ef | grep mongod | grep -v grep | awk -F "-f" '{print $2}')
if [[ -z $MongoConfFile ]]
then
	LogError"ERROR: Can't find mongodb conf file........"
	exit 1
else
	MongoConfFileName=$(echo $MongoConfFile | awk -F "/" '{print $NF}')
	ConfBackupDir=/backup/conf_file
	ConfBackupDirOld=/backup/conf_file/old
	LogCons "Backup conf file: ${MongoConfFile} to $ConfBackupDir/${MongoConfFileName}_${TimeStamp}"
	mkdir -p ${ConfBackupDirOld}
        rm ${ConfBackupDirOld}/*
	mv ${ConfBackupDir}/*_* ${ConfBackupDirOld}
	cp $MongoConfFile $ConfBackupDir/${MongoConfFileName}_${TimeStamp}
fi
