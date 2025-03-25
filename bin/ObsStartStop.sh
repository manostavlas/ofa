#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

YesNo $(basename $0) || exit 1 && export RunOneTime=YES


OFA_MAIL_RCP_BAD="no mail"
WhatToDo=$1
DbList=$2
ParaM2=$2
TimeStamp=$(date +"%H%M%S")
SqlLog=$OFA_LOG/tmp/ObsStartStop.SqlLog.$WhatToDo.$DbList.$$.$PPID.$TimeStamp.log

#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: ObsStartStop.sh [ACTION] <SID>
##
## Start/stop of all observer configureted in /etc/oratab and 3th parameter=Y.  
## 
## If second parameter are NOT set, ALL database are started/stopped !!!!!!!!!.
##
## Parameters:
## 	start (start of all databases)
##      stop  (stop of all databases)
##     
##      SID   (SID of the database to start Observer on.)
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

	if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the database: $DbName, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
		if [ $Error -ne 0 ] ; then
			LogCons "Error setting ENV for database: $DbName"
		else
			LogCons "Start Observer: $DbName "
			DbNameObserver=$(echo $DbName | awk -F "_" '{print $2}')
			DgObs.sh start ${DbNameObserver}
			ErrorCode=$?
			if [[ -z $ErrorCode  ]]
			then
				LogError "Error starting Observer: $DbName"
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

        OraEnv $DbName > /dev/null 2>&1

        Error=$?

        OsOwner=$(OraOsOwner)
        WhoAmI=$(whoami)

        if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the database: $DbName, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
                if [ $Error -ne 0 ] ; then
                        LogCons "Error setting ENV for database: $DbName"
                else
                        LogCons "Stop Observer: $DbName "
                        DbNameObserver=$(echo $DbName | awk -F "_" '{print $2}')
                        DgObs.sh stop ${DbNameObserver}
                        ErrorCode=$?
                        if [[ -z $ErrorCode  ]]
                        then
                                LogError "Error stop Observer: $DbName"
                        fi

                fi

        fi
done

}

#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [ -z "$DbList" ] ; then
	DbList=$(ListOraDbs | grep OBSERVER)
fi

if [ $WhatToDo == start ] ; then
	Start
elif [ $WhatToDo == stop ] ; then
	Stop
else
	Usage
fi
