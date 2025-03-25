#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

FuncToDo=$1
DbSid=$2
DbSid01=${DbSid}_01
DbSid02=${DbSid}_02
DbSidEnv=OBSERVER_${DbSid}
ObserverLogDir=${OFA_DB_VAR}/${DbSidEnv}/log
ObserverLogFile=${ObserverLogDir}/${DbSidEnv}.log
ObserverLogNoHup=${ObserverLogDir}/${DbSidEnv}.nohup.log

TimeStamp=$(date +"%H%M%S")
OutPutLog=$OFA_LOG/tmp/DgObs.Output.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp01=$OFA_LOG/tmp/DgObs.OutputTmp01.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp02=$OFA_LOG/tmp/DgObs.OutputTmp02.log.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/DgAdm.SqlLog.$FuncToDo.$$.$PPID.$TimeStamp.log
DgmgrlLog=$OFA_LOG/tmp/DgAdm.DgmgrlLog.$FuncToDo.$$.$PPID.$TimeStamp.log
# set -xv
#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DgObs.sh [FUNCTION] [FUNCTION_PARAMETERS] 
##
## Function:            Parameters:
##
## Start		[UniSid] (DB_UNIQUE_NAME, Unique database name)
##			Start Observer on server
##
## Stop			[UniSid] (DB_UNIQUE_NAME, Unique database name)
##			Stop Observer on server
##
##
#
__EOF
exit 1
}
#---------------------------------------------
CheckLogDir ()
#---------------------------------------------
{
if [[ ! -d "${OFA_DB_VAR}/${DbSidEnv}"  ]]
then
	LogError "Directory $OFA_DB_VAR/${DbSidEnv} missing"
	exit 1
else
	if [[ ! -d "$ObserverLogDir"  ]]
	then
		mkdir $ObserverLogDir
	fi 
fi
}
#---------------------------------------------
GetStatus ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage

RunMmDp
dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
show configuration;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog | grep -v "Warning:")

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
fi
}
#---------------------------------------------
Stop ()
#---------------------------------------------
{
LogCons "Running function: $FuncToDo"
RunMmDp
# dgmgrl -logfile ${ObserverLogFile} sys/$MmDp@DBAPOC1_01 "stop observer" &
}
#---------------------------------------------
StartStop ()
#---------------------------------------------
{
LogCons "Running function: $FuncToDo"
GetStatus
PrimDb=$(grep "Primary database" $DgmgrlLog | awk '{print $1}')
StanbyDb=$(grep "Physical standby database" $DgmgrlLog | awk '{print $1}')
FastStartFailover=$(grep "Fast-Start Failover:" $DgmgrlLog | awk '{print $3}')

LogCons "Primary database: $PrimDb"
LogCons "Standby database: $StanbyDb"
LogCons "Fast-Start Failover: $FastStartFailover"

RunMmDp



if [[ $RunParaM == Stop ]]
then
	EnAble_DisAble=disable
else 
	EnAble_DisAble=enable
fi
	
# Enable fast_start failover.
LogCons "$EnAble_DisAble fast_start failover, on $PrimDb"
dgmgrl -silent sys/${MmDp}@${PrimDb} << __EOF > $DgmgrlLog
$EnAble_DisAble fast_start failover;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running: "enable/disable fast_start failover" ,Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
fi

# Start OBSERVER
LogCons "$RunParaM OBSERVER. logfile: ${ObserverLogFile}"
LogCons "Observer configuration file: ${BrokerDir}/fsfo_${DbSid}.dat"
LogCons "logfile: ${ObserverLogFile}"
LogCons "logfile: ${ObserverLogNoHup}"

if [[ $RunParaM == Start ]]
then
	nohup dgmgrl -logfile ${ObserverLogFile} sys/$MmDp@$PrimDb "$RunParaM observer file='${BrokerDir}/fsfo_${DbSid}.dat'" > ${ObserverLogNoHup} 2>&1 &
	ProcessId=$!
        echo "ProcessId:$ProcessId"
	PWait 30
else
	nohup dgmgrl -logfile ${ObserverLogFile} sys/$MmDp@$PrimDb "$RunParaM observer" > ${ObserverLogNoHup} 2>&1 &
	rm -f ${BrokerDir}/fsfo_${DbSid}.dat
fi


DgmgrlErr=$(grep -e "ORA-" -e Failed -e error ${ObserverLogNoHup})

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running: "Start Observer" ,Error: $DgmgrlErr"
        LogError "Log: $ObserverLogNoHup"
        # cat $ObserverLogNoHup
        exit 1
fi

if [[ $RunParaM == Start ]]
then
	echo ""
	ProcessInfo=$(ps -ef | grep ${ProcessId} | grep -v grep )
	LogCons "Observer Process: ${ProcessInfo}"
	ShowFastSw	
	cat $DgmgrlLog
fi
}
#---------------------------------------------
ShowFastSw ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage

RunMmDp
dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
show fast_start failover;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
fi
}
#---------------------------------------------
PWait ()
#---------------------------------------------
{
i=$1
while [[ $i -gt 0 ]];do
echo -n -e "\rPlease wait.... |"
sleep 0.15
echo -n -e "\rPlease wait.... /"
sleep 0.15
echo -n -e "\rPlease wait.... -"
sleep 0.15
echo -n -e "\rPlease wait.... \\"
sleep 0.15
echo -n -e "\rPlease wait.... |"
sleep 0.15
echo -n -e "\rPlease wait.... -"
sleep 0.15
let i-=1
done
}
#---------------------------------------------
# Main 
#---------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
        FuncToDo                   \
     && LogIt "Variables complete" \
     || usage

FuncToDo=$(echo "$(echo "$1" | tr "[A-Z]" "[a-z]" | sed 's/.*/\u&/')")

# Create broker dir.
BrokerDir="$OFA_BRO_ADMIN/${DbSidEnv}"
[[ ! -d  $BrokerDir ]] && mkdir -p $BrokerDir >/dev/null 2>&1

LogCons "broker dir.:$BrokerDir"

OraEnv $DbSidEnv > /dev/null || BailOut "Failed OraEnv \"$DbSidEnv\""

CheckLogDir

if [[ "$FuncToDo" == "Start" ]]
then
        UniSid=$DbSid
	RunParaM=Start
        StartStop
elif [[ "$FuncToDo" == "Stop" ]]
then
        UniSid=$DbSid
	RunParaM=Stop
        StartStop 
else
        usage
fi
