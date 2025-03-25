#!/bin/ksh
#
##
##  Usage: RunSqlAllDb.sh [SQL_SCRIPT]
##
##  Run SQL_SCRIPT as SYS on all database there are up running on the server.
##
#

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

  #
  # Pattern for CheckConcurrentTask
  #

    OFA_MAIL_RCP_DFLT="no mail"
    OFA_MAIL_RCP_GOOD="no mail"
    OFA_MAIL_RCP_BAD="no mail"

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
##  Usage: RunSqlAllDb.sh [SQL_SCRIPT] [TYPE_DOSQL] <OUTPUT>
##
##  Run SQL_SCRIPT as SYS on all database there are up running on the server.
##
##  Parameters:
##  SQL_SCRIPT: Script name or query
##  TYPE_DOSQL: Type of DoSql to run DoSqlD, DoSqlS, DoSqlV, DoSqlQ
##
##  e.g.
##  RunSqlAllDb.sh $OFA_SQL/Set_PASSWORD_REUSE_MAX.sql
##
##  or
##
##  RunSqlAllDb.sh "select profile, limit from dba_profiles;"
##
#
__EOF
LogError "Missing or wrong parameter"
exit 1
}
#---------------------------------------------

TimeStamp=$(date +"%y%m%d_%H%M%S")
MainLog=$OFA_LOG/tmp/$(basename $0).MainLog.$$.$PPID.$TimeStamp.log
ScriptName=$1
TypeDoSql=$2

    LogCons "Check variable completeness"
    CheckVar                        \
        ScriptName                  \
        TypeDoSql                   \
     || usage

type $TypeDoSql
Error=$?
if  [[ $Error -ne 0 ]]
then
        LogError "DoSql(x) don't exist: $TypeDoSql"
        exit 1
fi

# Check if a query or a file
if [[ -z $(echo $ScriptName | grep ";") ]]
then
        if [[ ! -r $ScriptName ]]
        then
                LogError "File DON'T exist: $ScriptName"
                exit 1
        fi
fi

        # DbList=$(ListOraDbsUp | grep -v NLS | tr "\n" " ")
	DbList=$(ListOraDbsUp | grep -v NLS | awk -v x="" '{ s=s sprintf(x "%s" x " ", $0) } END { sub(",$", "", s); print(s) }')
        LogCons "Running: $ScriptName on $DbList"

if [[ -z $DbList ]]
then
        LogError "No database are OPEN on this server"
        exit 1
fi


for i in $DbList
do
ORACLE_SID=$i
  #
  # set Oracle environment
  #
    LogCons "Setting enviroment for $ORACLE_SID"

    OraEnv $ORACLE_SID || BailOut "Failed OraEnv \"$ORACLE_SID\"" | grep -v NLS

  if [ "$(OraDbStatus)" != "OPEN" ] ; then
          if [ "$(OraStartupFlag)" == "D" ] ; then
                LogCons "$ORACLE_SID is a DUMMY database"
          else
                LogWarning "Database ($ORACLE_SID) NOT in OPEN state"
          fi
  else
    SqlLogFile=$OFA_LOG/tmp/$(basename $0).$(echo $ORACLE_SID).SqlLogFile.$$.$PPID.$TimeStamp.log
    LogCons "Running on $ORACLE_SID Logfile: $SqlLogFile"
    $TypeDoSql "$ScriptName" > $SqlLogFile
    ErrorLog=$(grep "ORA-" $SqlLogFile)
    if [[ ! -z $ErrorLog ]]
    then
        LogError "Error running: $ScriptName Database: $ORACLE_SID Logfile: $SqlLogFile"
    fi
    echo ""
    echo "-----------------------------------------------------------------------------------------------------------------------------------------" >>  $MainLog
    echo "Database: $ORACLE_SID Job: $ScriptName" >>  $MainLog
    echo "-----------------------------------------------------------------------------------------------------------------------------------------" >>  $MainLog
    cat $SqlLogFile >> $MainLog
  fi
done
cat $MainLog
LogCons "Main output log: $MainLog"
echo  "Output file: $MainLog"
