#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv


YesNo $(basename $0) || exit 1 && export RunOneTime=YES

OFA_MAIL_RCP_BAD="no mail"

TimeStampLong=$(date +"%y%m%d_%H%M%S")
WhatToDo=$1
ParaM2=$2
ListenerFile=$OFA_TNS_ADMIN/listener.ora
ListLog=$OFA_LOG/tmp/ListStartStop.$$.$PPID.$TimeStampLong.log


# set -xv

#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: ListStartStop.sh [ACTION] <SID>
##
## Start/stop of all listeners configureted in $OFA_TNS_ADMIN/listener.ora and the DB exist in the oratab.  
##
## Parameters:
## 	start (start of all listeners)
##      stop  (stop of all listeners)
##      port  (Show all ports used by listeners)
##      status (Show status of all listeners)
##
##      SID:
##      Database SID, start all listerner configured for the database (SID_NAME, SERVICE_NAME)
##
#
_EOF
LogError "Wrong parameter....."
exit 1
}
#----------------------------------------------------------------------------------------
FindListenerNames ()
#----------------------------------------------------------------------------------------
{
# LogCons "All listerner configured in $ListenerFile "
# LogCons "Listener name,	Port number, Database"
unset ListListenerDatabase

LogCons "Find listener Names."
LogCons "Please wait..."

# echo "ListenerInfo: $ListenerInfo"


for i in $ListenerInfo
do
	ListenerName=$(echo $i | grep ^LISTENER_)
	DatabaseNameLabel=$(echo $i | egrep  'SID_NAME|SERVICE_NAME')
        LastValuePortNumber=$(echo $LastValue | grep PORT)

# echo "DatabaseNameLabel: $DatabaseNameLabel"
# echo "i:$i"
	if [ ! -z "$NextDBName" ] ; then
		DatabaseName=$i
		InfoList="$InfoList $DatabaseName"
		# LogCons "Database name: $DatabaseName"
#		LogCons "$InfoList"
		unset InfoList
		ListListenerDatabase="$ListListenerDatabase $DatabaseName:"
		unset NextDBName
	fi

	if [ ! -z "$DatabaseNameLabel" ] ; then
		NextDBName=1
	fi

	if [ ! -z "$ListenerName" ] ; then 
		# LogCons "Listener name: $ListenerName"
		ListListenerDatabase="$ListListenerDatabase $ListenerName"
		InfoList="$InfoList $ListenerName,"
	fi

        if [ ! -z "$LastValuePortNumber" ] ; then
                # LogCons "Port Number: $i"
		InfoList="$InfoList $i,"
		unset PortNumber
        fi
	LastValue=$i
done
}
#----------------------------------------------------------------------------------------
StartStop ()
#----------------------------------------------------------------------------------------
{


# set -xv

IFS=":"
# echo "ListListenerDatabase: $ListListenerDatabase"

# -- sort ListListenerDatabase 

unset LsnNameMgw
for i in $ListListenerDatabase
do 
        if [[ ! -z $ParaM2 ]]
	then
		LsnMgw=$(echo $i | grep -i mgw | grep $ParaM2) 
	else 
		LsnMgw=$(echo $i | grep -i mgw)
	fi

	if [[ ! -z $LsnMgw ]]
	then
		LsnNameMgw="$LsnNameMgw: $LsnMgw"
	fi
done 


unset LsnNameNoMgw
for i in $ListListenerDatabase
do
	if [[ ! -z $ParaM2 ]]
	then
		LsnNoMgw=$(echo $i | grep -v -i mgw | grep $ParaM2)
	else
        	LsnNoMgw=$(echo $i | grep -v -i mgw)
	fi

        if [[ ! -z $LsnNoMgw ]]
        then
                LsnNameNoMgw="$LsnNameNoMgw: $LsnNoMgw"
        fi
done



if [[ "$WhatToDo" == "stop" ]]
then 
	ListListenerDatabase=$(echo "$LsnNameMgw $LsnNameNoMgw" | sed 's/://')
fi

if [[ "$WhatToDo" == "start" ]]
then
        ListListenerDatabase=$(echo "$LsnNameNoMgw $LsnNameMgw" | sed 's/://')
fi


# echo "LsnNameMgw: $LsnNameMgw"
# echo "LsnNameNoMgw: $LsnNameNoMgw"
echo "ListListenerDatabase: $ListListenerDatabase"




# set -xv
for j in $ListListenerDatabase 
do 
	IFS=" "
	DbName=$(echo $j | awk '{print $2}' | sed 's/MGW//g' | sed 's/mgw//g')
	LsName=$(echo $j | awk '{print $1}')


# echo "LsName: $LsName"


# if [[ "$DbName" == "$ParaM2" ]] || [[ $WhatToDo == stop ]] || [[ $WhatToDo == start ]] 
# then 
LogCons "$WhatToDo LISTENER(S) for DB: $DbName"
	DbExist

	DbNameInOratab=$(ListOraDbs | grep -w $DbName)


if [[ ! -z "$DbNameInOratab" ]]
        then
                OraEnv $DbName > /dev/null 2>&1
                Error=$?
	

#	OraEnv $DbName > /dev/null 2>&1
#	Error=$?

	OsOwner=$(OraOsOwner)
	WhoAmI=$(whoami)

	# echo "DbName: $DbName, LsName: $LsName OsOwner: $OsOwner WhoAmI: $WhoAmI"

	if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the database: $DbName, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
		if [ $Error -ne 0 ] ; then
			LogCons "Error setting ENV for database: $DbName"
		else
			if [ ! -z $ParaM2 ] ; then
				if [ "$ParaM2" == "$DbName" ] ; then
					sleep 5	
					TimeStampLong=$(date +"%y%m%d_%H%M%S")
					ListLog=$OFA_LOG/tmp/ListStartStop.$$.$PPID.$TimeStampLong.log
					LogCons "$WhatToDo Listener: $LsName"
					ClUnMan
					lsnrctl $WhatToDo $LsName  | tee -a $ListLog

                                        ErrorLsStartStop=$(grep "TNS-" $ListLog | tail -1)
					ErrorLsNoListener=$(grep "TNS-00511: No listener" $ListLog)
                                        # echo "ErrorLsStartStop: $ErrorLsStartStop"

                                          
                                        if [ ! -z $ErrorLsStartStop ] && [ -z $ErrorLsNoListener ] && [ "$WhatToDo" == "start" ]; then
                                                LogError "Error $WhatToDo Listener: $LsName Log: $ListLog"
                                        fi
					
					if [ ! -z $ErrorLsNoListener ]; then
						LogCons " Warning! Listener was not running, Listener Name: $LsName"	
					fi

 
					ClMan
					ErrorLs=$?
		
					# echo "ErrorLs: $ErrorLs"
					if [ "$ErrorLs" -ne "0" ] ; then
						LogError "Error $WhatToDo Listener: $LsName"
					fi 
				fi
			else

				sleep 5	
				TimeStampLong=$(date +"%y%m%d_%H%M%S")
				ListLog=$OFA_LOG/tmp/ListStartStop.$$.$PPID.$TimeStampLong.log
				LogCons "Action: $WhatToDo Listener: $LsName"
				LogCons "Logfile: $ListLog"
				# ClUnMan
				lsnrctl $WhatToDo $LsName > $ListLog 2>&1 ;  export ErrorLs=$? 
				# ClMan
				# ErrorLs=$?

				echo "ErrorLs: $ErrorLs"

				NoListener=$(grep "TNS-12541: TNS:no listener" $ListLog)
				if [ ! -z $NoListener ] ; then
					LogCons "Listener: $LsName are not running.."

				else
					if [ "$ErrorLs" -ne "0" ] ; then
						LogError "Error $WhatToDo Listener: $LsName"
					fi 
				fi
			fi
	fi 
      fi
else
        LogCons " Warning! Database: $DbName DON'T exist! Listener Name: $LsName"
fi
# fi
done
unset IFS
}
#----------------------------------------------------------------------------------------
ClStat ()
#----------------------------------------------------------------------------------------
{
if [[ $WhatToDo = stop ]]
then
	ClStatGrp
fi
}

#----------------------------------------------------------------------------------------
ClUnMan ()
#----------------------------------------------------------------------------------------
{
if [[ $WhatToDo = stop ]]
then
	ClExist
	if [[ $? -eq 0 ]]
	then
        	LogCons "Set RESOURCE to Unmanaged"
        	ClUnManLsn $LsName
	fi
fi
}
#----------------------------------------------------------------------------------------
ClMan ()
#----------------------------------------------------------------------------------------
{
if [[ $WhatToDo = start ]]
then
        ClExist
        if [[ $? -eq 0 ]]
        then
                LogCons "Set RESOURCE to managed"
                ClManLsn $LsName
        fi
fi
}

#----------------------------------------------------------------------------------------
DbExist ()
#----------------------------------------------------------------------------------------
{
DbList=$(ListOraDbs | tr '\n' ' ')

for i in $DbList
do
	DbExist=$(echo $DbName | grep -w $i)

	if [[ ! -z "$DbExist" ]]
	then
		DbName=$(echo $i)
	fi 

done
}
#
#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [[ ! -z $ParaM2 ]]
then
	DbNameInOratab=$(ListOraDbs | grep $ParaM2)
	if [[ -z "$DbNameInOratab" ]]
	then
		LogError "Database: $ParaM2 DON'T exist"
		Usage
	fi 
fi

if [ "$WhatToDo" == start ] || [ "$WhatToDo" == stop ] || [ "$WhatToDo" == status ] || [ "$WhatToDo" == port ] ; then

	if [ -r $ListenerFile ] ; then 
		ListenerInfo=$(egrep 'SID_NAME|SERVICE_NAME|LISTENER_|PORT' $ListenerFile |\
        	     egrep -v "^ *#" | egrep -v PLSExtProc | sed s/=/" "/g | sed s/\(//g | sed s/\)//g ) 
	else
		LogError "Listener file: $ListenerFile don't exist"
	fi


	if [ $WhatToDo == port ] ; then
		FindListenerNames
	else
		FindListenerNames
                # ClUnMan
		StartStop
		# ClStat
		# ClMan
	fi
else
	Usage
fi
