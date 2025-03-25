#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"

DbSid=$1
DdStatusRequest=$2
TnsNames=$3

TimeStamp=$(date +%Y%m%d_%H%M%S)
SqlLog=$OFA_LOG/tmp/DdConnTest.SqlLog.$$.$PPID.$TimeStamp.log
ConnInfoLog=$OFA_LOG/tmp/DdConnTest.ConnInfoLog.$$.$PPID.$TimeStamp.log
#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DbConnCheck.sh  [SID], <DB_STATUS> or TNS, TNS
##
##
## Paremeter:
##
## Parameter 1:
## SID:
##      Name of the database
##
## Parameter 2:
## DB_STATUS or TNS:
## Parameter can be "database status" (e.g. OPEN, MOUNTED) or TNS
## If TNS, tnsnames will be uaed.
##
## Parameter 3:
## 	Is parameter TNS the tnsnames will be used.
##      
##
## Connect to the DB via SQL*Net 
##
#
__EOF
exit 1
}
#---------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
     && LogIt "Variables complete" \
     || usage



if [[ "$DdStatusRequest" == "TNS" ]] || [[ "$TnsNames" == "TNS" ]]
then
		LogCons "Using tnsname.ora"
		ConnectInfo=$DbSid
else	
	Ldaping $DbSid > $ConnInfoLog
	ConnectError=$(grep "TNS-" $ConnInfoLog)
	
	if [[ ! -z $ConnectError ]]
	then
		LogError "Error getting Connect string, logfile: $ConnInfoLog"
		exit 1
	fi
	ConnectInfo=$(grep "Attempting to contact" $ConnInfoLog | sed 's/Attempting to contact //g')
fi 

LogCons "Connect string: ${ConnectInfo}"

RunMmDp
# sqlplus system/$MmDp@$DbSid << __EOF > $SqlLog
sqlplus system/$MmDp@$ConnectInfo << __EOF > $SqlLog
select status from v\$instance;
__EOF

ErrorInfo=$(grep "ORA-" $SqlLog | grep -v "ORA-01017")


if [[ ! -z $ErrorInfo ]]
then
	LogError "Error connect to $DbSid, logfile: $SqlLog"
	echo "Log file:"
	cat $SqlLog
	exit 1
fi


if [[ "$DdStatusRequest" != "TNS" ]]
then
	StatusInfo=$(grep -A2 STATUS $SqlLog | tail -1)
	
	if [[ ! -z $DdStatusRequest ]]
	then 
		if [[ "$StatusInfo" != "$DdStatusRequest" ]]
		then
			LogError "Database is not $DdStatusRequest, Status:$StatusInfo"
			exit 1
		else
			LogCons "Database status: $StatusInfo"
		fi
	fi
fi
