#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#  set -xv

 YesNo $(basename $0) || exit 1 && export RunOneTime=YES


OFA_MAIL_RCP_BAD="no mail"
WhatToDo=$1
DbList=$2
ParaM2=$2
TimeStamp=$(date +"%H%M%S")
SqlLog=$OFA_LOG/tmp/DbStartStop.SqlLog.$WhatToDo.$DbList.$$.$PPID.$TimeStamp.log

#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: DbStartStop.sh [ACTION] <SID>
##
## Start/stop of all databases configureted in /etc/oratab and 3th parameter=Y.  
## 
## If second parameter are NOT set, ALL database are started/stopped !!!!!!!!!.
##
## Parameters:
## 	start (start of all databases)
##      stop  (stop of all databases)
##     
##      SID   (SID of the database to start/stop)
##
#
_EOF
LogError "Wrong parameter....."
exit 1
}
#----------------------------------------------------------------------------------------
Start ()
#----------------------------------------------------------------------------------------
{

for i in $DbList
do
	DbName=$i

	OraEnv $DbName > /dev/null 2>&1
	
	Error=$?

	OsOwner=$(OraOsOwner)
	WhoAmI=$(whoami)

	if [ ! -z $ParaM2 ] ; then 
		OraStartupFlag=Y
	else
		OraStartupFlag=$(OraStartupFlag)
	fi


	if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the database: $DbName, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
		if [ $Error -ne 0 ] ; then
			LogCons "Error setting ENV for database: $DbName"
		else
			if [ $OraStartupFlag == "Y" ] ; then
				if [ "$(OraDbStatus)" == "OPEN" ] || [ "$(OraDbStatus)" == "MOUNTED" ] ; then
					LogWarning "Database: $DbName already running ($(OraDbStatus))!"
					LogCons "Database: $DbName already running ($(OraDbStatus))!"
					ClMan
				else 
					LogCons "$WhatToDo Database: $DbName"
					LogCons "Startup mount !"
					DoSqlQ "startup mount;" > $SqlLog
#					sqlplus -s "/as sysdba" << ____EOF >> $SqlLog
#					whenever sqlerror exit 1
#					whenever oserror exit 1
#					startup
#____EOF
					DB_Role=$(DoSqlQ "select database_role from v\$database;")
					echo "Database role: $DB_Role" >> $SqlLog
					LogCons "Database role: $DB_Role"	
					if [[ "$DB_Role" != "PHYSICAL STANDBY" ]]
					then
						LogCons "OPEN database."
						DoSqlQ "alter database open;" >> $SqlLog
					fi

					ErrorLs=$(grep "ORA-" $SqlLog)
        			        if [ ! -z "$ErrorLs"  ] ; then
              			          LogError "Error $WhatToDo Database: $DbName Error: $ErrorLs Log file: $SqlLog"
			                else
                                                ClMan
			                        LogCons "OK !"
			                fi

				fi
			fi
		fi

	fi
done
}
#----------------------------------------------------------------------------------------
Stop ()
#----------------------------------------------------------------------------------------
{
for i in $DbList
do
        DbName=$i

        OraEnv $DbName  > /dev/null 2>&1

        Error=$?

        OsOwner=$(OraOsOwner)
        WhoAmI=$(whoami)

	if [ ! -z $ParaM2 ] ; then 
		OraStartupFlag=Y
	else
		OraStartupFlag=$(OraStartupFlag)
	fi

        if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the database: $DbName, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
                if [ $Error -ne 0 ] ; then
                        LogCons "Error setting ENV for database: $DbName"
                else

			if [ $OraStartupFlag == "Y" ]||[ $OraStartupFlag == "N" ] ; then
					
				DbStatus=$(OraDbStatus | sed 's/MOUNTED/RUNNING/g' |sed 's/OPEN/RUNNING/g')
				LogCons "Database status: $DbStatus, Mode: $(OraDbStatus)"
				ClUnMan
				if [ "$DbStatus" != "RUNNING" ] ; then
					if [ "$(OraDbStatus)" != "DOWN" ] ; then
						LogWarning "Database: $DbName status are NOT OPEN ! (shutdown abort)"
						LogCons "Database: $DbName status are NOT OPEN !"
						LogCons "Shutdown abort Database: $DbName"
                                        	sqlplus -s "/as sysdba" << ____EOF >> $SqlLog
                                        	-- whenever sqlerror exit 1
                                        	-- whenever oserror exit 1
                                        	shutdown abort;
____EOF
					else
						LogCons "Database: $DbName NOT running! "
					fi

				else
                                        LogCons "$WhatToDo Database: $DbName"
                                        sqlplus -s "/as sysdba" << ____EOF >> $SqlLog
                                        -- whenever sqlerror exit 1
                                        -- whenever oserror exit 1
                                        shutdown immediate;
____EOF
                                        SqlError=$(grep "ORA-" $SqlLog | grep -v ORA-01109)
			                if [ ! -z $SqlError ] ; then
			                        LogError "Error $WhatToDo Database: $DbName Error: $SqlError Log file: $SqlLog"
					else
                                                ClStatGrp
						LogCons "OK ! "
			                fi
				fi
			fi
                fi

        fi
done
}
#----------------------------------------------------------------------------------------
ClUnMan ()
#----------------------------------------------------------------------------------------
{
ClExist
if [[ $? -eq 0 ]]
then
	LogCons "Set RESOURCE to Unmanaged" 
	ClUnManDb
fi
}
#----------------------------------------------------------------------------------------
ClMan ()
#----------------------------------------------------------------------------------------
{
ClExist
if [[ $? -eq 0 ]]
then
        LogCons "Set RESOURCE to managed"
        ClManDb
fi
}

#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [ -z "$DbList" ] ; then
	DbList=$(ListOraDbs)
fi

if [ $WhatToDo == start ] ; then
	Start
elif [ $WhatToDo == stop ] ; then
	Stop
else
	Usage
fi
