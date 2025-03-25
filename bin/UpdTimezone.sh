#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


DatabaseName=$1

TimeStamp=$(date +"%H%M%S")
TmpLogDir=$OFA_LOG/tmp/
RunSqlFile=UpdTimezone.RunSqlFile.$$.$PPID.$TimeStamp.sql


#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: UpdTimezone.sh  [SID]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##
## Update time zone of the Database.
##
#
__EOF
exit 1
}

#---------------------------------------------
PreChangeTimeZone ()
#---------------------------------------------
{
# OraEnv $DatabaseName || BailOut "Failed OraEnv \"$DatabaseName\""

# Restart DB
Action=ResUpgrade
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Restart the database to upgrade in mode"
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
shutdown immediate;
startup upgrade;
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi

# Check Time Zone.
Action=CheckTZ
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Checking timezone:"
LogCons "Log file: $SqlLog"

DoSqlS "SELECT * FROM v\$timezone_file;" > $SqlLog 2>&1

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
else
        cat $SqlLog 
fi

# Start the upgrade window 
Action=StartUpgWin
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Start the upgrade window."
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
alter session set "_with_subquery" = materialize;
SET SERVEROUTPUT ON
DECLARE
l_tz_version PLS_INTEGER;
BEGIN
	l_tz_version := DBMS_DST.get_latest_timezone_version;
	DBMS_OUTPUT.put_line('l_tz_version=' || l_tz_version);
	DBMS_DST.begin_upgrade(l_tz_version);
END;
/

___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi

# Restart DB
Action=ResDbNormal
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Restart the database to normal in mode"
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
shutdown immediate;
startup;
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi
}
#-------------------------------------------------
RunUpgradeTZSDB ()
#-------------------------------------------------
{
# Running upgrade
Action=RunUpgTZ
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Running the upgrade"
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
alter session set "_with_subquery" = materialize;

SET SERVEROUTPUT ON
DECLARE
  l_failures   PLS_INTEGER;
BEGIN
  DBMS_DST.upgrade_database(l_failures);
  DBMS_OUTPUT.put_line('DBMS_DST.upgrade_database : l_failures=' || l_failures);
  DBMS_DST.end_upgrade(l_failures);
  DBMS_OUTPUT.put_line('DBMS_DST.end_upgrade : l_failures=' || l_failures);
END;
/
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi

# Check Time Zone.
Action=ChkTZ
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log


LogCons "Checking timezone:"
LogCons "Log file: $SqlLog"

DoSqlS "SELECT * FROM v\$timezone_file;" > $SqlLog 2>&1

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
else
        cat $SqlLog
fi

}
#---------------------------------------------------
CheckIfUpdate ()
#---------------------------------------------------
{
Action=CheckIfUpdate
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log
> $SqlLog

LogCons "Check if updateing....."
LogCons "Log file: $SqlLog"

# echo "***** $NewLV ******"

 DoSqlV "SELECT * FROM v\$timezone_file where version <$NewLV;" > $SqlLog 2>&1

# sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
#  show pdbs;
#  show con_name;
#  SELECT * FROM v\$timezone_file where version < $NewLV;
# ___EOF

export Okay=$(grep "no rows selected" $SqlLog)


ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi
}
#---------------------------------------------------
ReStartDBNormal ()
#---------------------------------------------------
{
# Restart DB
Action=ResDbNormal
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Restart the database to normal in mode"
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
shutdown immediate;
startup;
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi
}
#----------------------------------------------------
ReStartDBUpgrade ()
#----------------------------------------------------
{
# Restart DB
Action=ResUpgrade
SqlLog=$OFA_LOG/tmp/UpdTimezone.$DbRunName.$Action.$$.$PPID.$TimeStamp.log

LogCons "Restart the database to upgrade in mode"
LogCons "Log file: $SqlLog"

sqlplus -s "/as sysdba"  << ___EOF > $SqlLog 2>&1
shutdown immediate;
startup upgrade;
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi
}
#----------------------------------------------------
# Main
#----------------------------------------------------
    LogCons "Check variable completeness"
    CheckVar                        \
        DatabaseName                  \
     || usage

DbList=$(ListOraDbsUp | grep ${DatabaseName} | tr '\n' ' ' )

LogCons "Database(s) for timezone update: $DbList"

OraEnv $DatabaseName || BailOut "Failed OraEnv \"$DatabaseName\""

export LatestVersion=$(DoSqlQ "SELECT DBMS_DST.get_latest_timezone_version from dual;" 2>&1 | sed 's/ //g' )

LogCons "Timezone file version: $LatestVersion"
NewLV=$(echo $LatestVersion | sed 's/ //g') 

for i in $DbList
do
	LogCons "Running timezone update on $i"
	DbRunName=$i
	OraEnv $i || BailOut "Failed OraEnv \"$DatabaseName\""
        CheckIfUpdate

	if [[ ! -z $Okay ]]
	then
       		 LogCons "No update needed....."
	else 
        	PreChangeTimeZone
        	RunUpgradeTZSDB
	fi
done
