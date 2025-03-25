#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# VolMin

DbSid=$1
FuncToDo=$2
Log=$OFA_LOG/tmp/OpatchCheck.$DbSid.$FuncToDo.$$.$PPID.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: OpatchCheck.sh  [SID] [FUNCTION]
##
## Paremeter:
##
## SID: Name of the database
##
## FUNCTION:
##      Info    (Show status of ORACLE and DB patch level)
##      Patch   (Run patch of the DB if not update.)
##
#
__EOF
exit 1
}
#---------------------------------------------
GetInfo ()
#---------------------------------------------
{
LogCons "Checking ORACLE_HOME and DB patch level"

HomePatchLevel=$(OraDbGetVerOPatch)
HomePatchLevelMain=$(echo $HomePatchLevel | awk -F "." '{print $1}')
LogCons "Oracle HOME Main version:     $HomePatchLevelMain"
LogCons "Oracle HOME Patch level:      $HomePatchLevel"
if [[ "$HomePatchLevelMain" == "19" ]]
then
	# DbPatchLevel=$(DoSqlQ "select substr(a.description,instr(a.description,19),15) from (select description from dba_registry_sqlpatch order by ACTION_TIME desc) a where rownum =1;")
        DbPatchLevelRaw=$(DoSqlQ "select a.description from (select description from dba_registry_sqlpatch order by ACTION_TIME desc) a where rownum =1;")
        DbPatchLevel=$(echo $DbPatchLevelRaw | sed 's/Revision//g' | awk '{print $5}')
elif [[ "$HomePatchLevelMain" == "12" ]]
then
        DbPatchLevel=$(DoSqlQ "select substr(a.description,instr(a.description,12),15) from (select description from dba_registry_sqlpatch order by ACTION_TIME desc) a where rownum =1;")
elif [[ "$HomePatchLevelMain" == "11" ]]
then
	DbPatchLevelRaw=$(DoSqlQ "select COMMENTS, action from sys.registry\$history where COMMENTS like 'PSU%' and rownum=1 order by ACTION_TIME desc;")
	DbPatchLevel=$(echo $DbPatchLevelRaw | awk '{print $2}')
	DbPatchLevelAction=$(echo $DbPatchLevelRaw | awk '{print $3}')
	if [[ "$DbPatchLevelAction" != "APPLY" ]]
	then
		LogError "The last patch action are NOT "APPLY" Action: $DbPatchLevelAction"
		exit 1
	fi	

else
	LogError "Wrong main Oracle version: $HomePatchLevelMain"
	exit 1
fi

LogCons "Oracle Database Patch level:  $DbPatchLevel"


LogCons "Database pacth and ORACLE_HOME"

if [[ "$HomePatchLevel" == "$DbPatchLevel" ]]
then
	PatchStatus="OK"
	LogCons "Status: $PatchStatus"
else
	PatchStatus="FAILED"
        LogCons "Status: $PatchStatus"
fi
}
#---------------------------------------------
PatchDb ()
#---------------------------------------------
{
GetInfo
LogCons "Patching the Database"
if [[ "$PatchStatus" == "FAILED" ]]
then
	LogCons "Database patching DB: $DbSid"
	if [[ $HomePatchLevelMain -ge 12 ]]
	then
		LogCons "Running "./datapatch -verbose" on DB:$DbSid"
		unset ORACLE_PATH
		unset SQLPATH
		$ORACLE_HOME/OPatch/datapatch -verbose | LogStdInEcho
	else
		LogCons "Running "@catbundle.sql psu apply" on DB:$DbSid"
		DoSqlV $ORACLE_HOME/rdbms/admin/catbundle.sql psu apply > $Log 2>&1 
		# cat $Log | LogStdIn
		LogCons "Check the following log file for errors: $Log"
	fi
else
	LogCons "Not patching needed."
fi

}
#---------------------------------------------
# Main 
#---------------------------------------------
# Check
    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
        FuncToDo                   \
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbSid
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                VolUp 1
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

# Check DB OPEN

DbStat=$(OraDbStatus)

if [[ "OPEN" != "$DbStat" ]]
then
	LogError "Database: $DbSid are NOT "OPEN" Status: $DbStat"
	exit 1 
fi

# Menu

if [[ "$FuncToDo" == "Info" ]]
then
        GetInfo
elif [[ "$FuncToDo" == "Patch" ]]
then
        PatchDb
else
        usage
fi

VolMin
