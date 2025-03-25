#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -vx
##
## Usage: "blackout_target.sh [TARGET_TYPE] [TARGET_ID] [FUNCTION] <IND>
##
## Parameter:
##	TARGET_TYPE:	listener, database.
##		Which target type to blackout.
##   
##	TARGET_ID:	
##              The database or name of listener (Without LISTENER_).
##
##	FUNCTION:	start, stop, status.
##
##      INDEFINITE:     IND
##              Set blackout to indefinite, default blackout is 6 hours.
##

OFA_MAIL_RCP_BAD=""

TargetType=$1
TargetSID=$2
Blackout=$3
Indefinite=$4

if [ "$Indefinite" != "IND" ]; then
	BlackoutTime="-d 06:00"
fi

DbType=$(ListOraDbs | grep ${TargetSID}_PDB)

if [ -z "$DbType" ]; then
	DbType=SDB
else
	DbType=CDB
fi

if [ -z "$TargetType" ] || [ -z "$TargetSID" ] || [ -z "$Blackout" ]; then
        LogError "blackout_target.sh [TARGET_TYPE] [TARGET_SID] [FUNCTION]"
	LogInfo "Target Type: ${TargetType}"
	LogInfo "Target SID: ${TargetSID}"
	LogInfo "Blackout: ${Blackout}"
        exit 1
fi


# OraEnv OEMAGENT 2>&1 >/dev/null

LogCons "Set env."

if [ $(ListOraDbs | grep -w OEMAGENT) ] ; then
	LogCons "Set ENV for OEMAGENT"
	OraEnv OEMAGENT
	LogCons "ORACLE_HOME: $ORACLE_HOME"
elif [ $(ListOraDbs -w OEMAGENT_${TargetSID}) ] ; then
	LogCons "Set ENV for OEMAGENT_${TargetSID}"
	OraEnv OEMAGENT_${TargetSID}
	LogCons "ORACLE_HOME: $ORACLE_HOME"
else
        LogWarning "Can't find OEMAGENT or OEMAGENT_${TargetSID} in the oratab file...."
	exit 1
fi


# echo "ORACLE_HOME: $ORACLE_HOME"

AgentExec=$(find $ORACLE_HOME/* -name emctl 2>/dev/null)

if [ ! -x "$AgentExec" ]; then
	LogError "Can't find emctl or missing rights"
	exit 1
fi

LogCons "Target Type: ${TargetType}"
LogCons "Target SID: ${TargetSID}"
LogCons "Blackout: ${Blackout}"
LogCons "Database Type: ${DbType}"


#----------------------------------------------------
BlackoutList()
#----------------------------------------------------
{
ListenerList=$($AgentExec config agent listtargets | grep oracle_listener | grep -i ${TargetSID} | awk '{print $1}' | sed -e 's/\[//' -e 's/,//' | tr '\n' ',')
LogCons "Listener list: $ListenerList"


	if [ "$Blackout" = "start" ]; then
		ListenerName=$($AgentExec status agent scheduler | grep listener | grep ${TargetSID} | grep Load | awk '{print $NF}' | sed 's/:Load//g'| sed 's/oracle_listener://g')
               
		if [ -z "$ListenerName" ]; then
	                LogWarning "No listener(s) acktiv in the GRID....."
        	        exit 1
                fi

		for i in $ListenerName
		do
			LogInfo "Listener Name: $i"
			if [ -z "$i" ]; then
				LogWarning "No listener(s) acktiv on GRID"
			#	exit 1
			fi
			LogCons "Start blackout of $i"
			$AgentExec start blackout ofa_$i $i:oracle_listener $BlackoutTime
			ErrorCode=$?
		done
	elif [ "$Blackout" = "stop" ]; then
		ListenerBlackoutName=$($AgentExec status blackout | grep "Blackoutname =" | awk -F "=" '{print $2}' | grep -i ${TargetSID} | grep LISTENER)
                if [ -z "$ListenerBlackoutName" ]; then
                        LogWarning "No listener(s) in blackout...."
                        exit 1
                fi

		for i in $ListenerBlackoutName
		do
                	LogCons "Stop blackout of $i"
			$AgentExec  stop blackout $i 
			ErrorCode=$?
		done
	else
		LogError "Wrong parameters"
	fi
}
#----------------------------------------------------
BlackoutDatabase()
#----------------------------------------------------
{
	if [ "$Blackout" = "start" ]; then
	DatabaseName=$($AgentExec status agent scheduler | grep oracle_database | grep ${TargetSID})
                if [ -z $DatabaseName ]; then
                        LogWarning "Target are not acktiv"
                        exit 1
                fi
                $AgentExec start blackout ofa_oracle_database_${TargetSID} ${TargetSID}:oracle_database $BlackoutTime
                # $AgentExec start blackout ofa_oracle_database_${TargetSID} ${TargetSID}:oracle_database -d 06:00
		ErrorCode=$?
        elif [ "$Blackout" = "stop" ]; then

		DatabaseBlackoutName=$($AgentExec status blackout | grep "Blackoutname =" | awk -F "=" '{print $2}' | grep -i ${TargetSID} | grep ofa_oracle_database)
                if [ -z $DatabaseBlackoutName ]; then
                        LogWarning "Target are not acktiv"
                        exit 1
                fi

                $AgentExec  stop blackout $DatabaseBlackoutName 
		ErrorCode=$?
        else
                LogError "Wrong parameters"

        fi
}
#----------------------------------------------------
BlackoutDatabasePdb()
#----------------------------------------------------
{
# set -xv
        if [ "$Blackout" = "start" ]; then
#        DatabaseName=$($AgentExec status agent scheduler | grep oracle_database | grep ${TargetSID})
#                if [ -z $DatabaseName ]; then
#                        LogWarning "Target are not acktiv"
#                        exit 1
#                fi

# LogCons "Starting: $AgentExec start blackout ${TargetSID}_CDBROOT_auto_database ${TargetSID}_CDBROOT:oracle_pdb -d 06:00"

                $AgentExec start blackout ${TargetSID}_CDBROOT_auto_database ${TargetSID}_CDBROOT:oracle_pdb $BlackoutTime 2>&1
                $AgentExec start blackout ${TargetSID}_${TargetSID}_PDB_auto_database ${TargetSID}_${TargetSID}_PDB:oracle_pdb $BlackoutTime 2>&1
                ErrorCode=$?
        elif [ "$Blackout" = "stop" ]; then
                $AgentExec  stop blackout ${TargetSID}_CDBROOT_auto_database
                $AgentExec  stop blackout ${TargetSID}_${TargetSID}_PDB_auto_database
                ErrorCode=$?
        else
                LogError "Wrong parameters"

        fi
}

#----------------------------------------------------
# Main
#----------------------------------------------------
if [ "$Blackout" = "status" ]; then
	$AgentExec status blackout
	exit 0
elif [ "$TargetType" = "listener" ]; then
	BlackoutList
elif [ "$TargetType" = "database" ]; then
	BlackoutDatabase
	if [ "$DbType" = "CDB" ]; then
		BlackoutDatabasePdb
	fi
else
	LogError "Wrong parameters"
fi

if [ $ErrorCode -ne 0 ]; then
	LogWarning "Error running emctl"
	exit 1
fi
