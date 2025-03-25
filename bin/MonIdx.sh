#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

MAIL_LIST=$4

# FuncToDo=$(echo "$(echo "$1" | tr "[A-Z]" "[a-z]" | sed 's/.*/\u&/')")

FuncToDo=$1

FuncToDo1=$(echo "$FuncToDo" | sed 's/\(.\).*/\1/' | tr "[a-z]" "[A-Z]")
FuncToDo2=$(echo "$FuncToDo" | sed 's/.\(.*\)/\1/' | tr "[A-Z]" "[a-z]")
FuncToDo=${FuncToDo1}${FuncToDo2}

echo ""
LogCons "Running function: $FuncToDo"

TimeStamp=$(date +"%H%M%S")
MonIdxLog=$OFA_LOG/tmp/MonIdx.MonIdxLog.$FuncToDo.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/MonIdx.SqlLog.$FuncToDo.$$.$PPID.$TimeStamp.log
SqlScr=$OFA_LOG/tmp/MonIdx.SqlScr.$FuncToDo.$$.$PPID.$TimeStamp.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: MonIdx.sh  [FUNCTION] [FUNCTION_PARAMETERS]
##
## Function:            Parameters:
##
## List			[SID] [SCHEMA_NAME] <MAIL_LIST>
##			List all indexes with Monitoring ON
## 			MAIL_LIST: Mailing list for the report e.g. asg@ubp.ch,jha@ubp.ch
##
## Enable		[SID] [SCHEMA_NAME] 
##                      Enable monitoring
##                      if [SCHEMA_NAME] = All monitoring will be enabled on all application schemas 
##
## Disable		[SID] [SCHEMA_NAME] 
##                      DisEnable monitoring
##                      if [SCHEMA_NAME] = All monitoring will be Disenabled on all application schemas 
##
## Report		[SID] [SCHEMA_NAME] <MAIL_LIST>
##                   	Create report of unused/used indexes 
##                      if [SCHEMA_NAME] = All, The Report will run for all schemas 
## 			MAIL_LIST: Mailing list for the report e.g. asg@ubp.ch,jha@ubp.ch
#
__EOF
}
#---------------------------------------------
CheckErr ()
#---------------------------------------------
{
OraError=$(grep "ORA-" ${SqlLog})

if [[ ! -z $OraError ]]
then
	LogError "Error during execution......"
	LogError "Log file: ${SqlLog}"
	exit 1
fi
}
#---------------------------------------------
List ()
#---------------------------------------------
{
  CheckVar DbSid  \
  SchemaName      \
  || Usage

LogCons "List indexes with Monitoring....Database: $DbSid Schema: $SchemaName"
LogCons "Script file: $SqlScr"
LogCons "Log file   : $SqlLog"

OraEnv $DbSid

if [[ "$SchemaName" == "All" ]]
then
        SchemaName=$(ApplUser)
else
        SchemaName=$(echo "'${SchemaName}'" | tr a-z A-Z)
fi



LogCons "List monitoring for Schema(s): $SchemaName"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET PAGESIZE 10000
-- SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING OFF
SET HEADING ON
SET LINESIZE 500
SET TRIMSPOOL ON

col MONITORING format a12
col USED format a5
col OWNER format a20
col TABLE_NAME format a40
col INDEX_NAME format a40



SPOOL $SqlScr

SELECT OWNER,TABLE_NAME,INDEX_NAME,USED,MONITORING,START_MONITORING,END_MONITORING  
FROM   dba_object_usage i
WHERE  owner in ($SchemaName) and MONITORING='YES'
order by 1,2,3
;

spool off
___EOF

CheckErr

cat $SqlScr
echo ""
LogCons "List file: $SqlScr"
echo ""

}
#---------------------------------------------
Enable ()
#---------------------------------------------
{
  CheckVar DbSid  \
  SchemaName      \
  || Usage

LogCons "Enable index Monitoring. Database: $DbSid Schema: $SchemaName"
LogCons "Script file: $SqlScr"
LogCons "Log file   : $SqlLog"

OraEnv $DbSid

if [[ "$SchemaName" == "All" ]]
then
	SchemaName=$(ApplUser)
else 
	SchemaName=$(echo "'${SchemaName}'" | tr a-z A-Z)
fi



LogCons "Enabling monitoring for Schema(s): $SchemaName"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING OFF

SPOOL $SqlScr 

SELECT 'ALTER INDEX "' || i.owner || '"."' || i.index_name || '" MONITORING USAGE;'
FROM   dba_indexes i
WHERE  
owner in ($SchemaName)
and INDEX_TYPE <> 'IOT - TOP'
and INDEX_TYPE <> 'LOB'
order by 1
;

SPOOL OFF

-- SET PAGESIZE 18
SET FEEDBACK ON

@${SqlScr}

___EOF

CheckErr

}
#---------------------------------------------
Disable ()
#---------------------------------------------
{
  CheckVar DbSid  \
  SchemaName      \
  || Usage
LogCons "Disable index Monitoring. Database: $DbSid Schema: $SchemaName"
LogCons "Script file: $SqlScr"
LogCons "Log file   : $SqlLog"

OraEnv $DbSid

if [[ "$SchemaName" == "All" ]]
then
        SchemaName=$(ApplUser)
else
        SchemaName=$(echo "'${SchemaName}'" | tr a-z A-Z)
fi



LogCons "Enabling monitoring for Schema(s): $SchemaName"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING OFF

SPOOL $SqlScr

SELECT 'ALTER INDEX "' || i.owner || '"."' || i.index_name || '" NOMONITORING USAGE;'
FROM   dba_indexes i
WHERE  
owner in ($SchemaName) 
and INDEX_TYPE <> 'IOT - TOP'
and INDEX_TYPE <> 'LOB'
order by 1
;

SPOOL OFF

SET PAGESIZE 18
SET FEEDBACK ON

@${SqlScr}

___EOF

CheckErr

}
#---------------------------------------------
Report ()
#---------------------------------------------
{
  CheckVar DbSid  \
  SchemaName      \
  || Usage

LogCons "Report for index Monitoring. Database: $DbSid Schema: $SchemaName"

LogCons "List indexes with Monitoring....Database: $DbSid Schema: $SchemaName"
LogCons "Script file: $SqlScr"
LogCons "Log file   : $SqlLog"

OraEnv $DbSid

if [[ "$SchemaName" == "All" ]]
then
        SchemaName=$(ApplUser)
else
        SchemaName=$(echo "'${SchemaName}'" | tr a-z A-Z)
fi



LogCons "List monitoring for Schema(s): $SchemaName"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET PAGESIZE 10000
SET VERIFY OFF
SET TIMING OFF
SET HEADING ON
SET LINESIZE 500
SET TRIMSPOOL ON

col MONITORING format a12
col USED format a5
col OWNER format a20
col TABLE_NAME format a40
col INDEX_NAME format a40

SPOOL $SqlScr

SELECT OWNER,TABLE_NAME,INDEX_NAME,USED,MONITORING,START_MONITORING,END_MONITORING
FROM   dba_object_usage i
WHERE  owner in ($SchemaName)
order by USED,OWNER,TABLE_NAME,INDEX_NAME
;

spool off
___EOF

CheckErr

cat $SqlScr

echo ""
LogCons "Report file: $SqlScr"
echo ""

# if [[ ! -z "$MAIL_LIST"  ]]
# then
#         MailReport
# fi


}
#--------------------------------------------------------------------------
function MailReport
#--------------------------------------------------------------------------
{
FILE_NAME=$SqlScr
# Set mail command
LogCons "Sending mail to: $MAIL_LIST"
MailError=$(mail -V >/dev/null 2>&1  ; echo $?)

if [[ $MailError -eq 0 ]]
then
LogCons "* Sending mail to: $MAIL_LIST"
        (echo "This are a genereted Report from Server $(uname -n). " ; echo "Started from MonIdx.sh, If any question contact SPOC_DBA@ubp.ch") | mail -a $FILE_NAME -s "Index Report for $DbSid" ${MAIL_LIST};

else
LogCons "** Sending mail to: $MAIL_LIST"
        (echo "This are a genereted Report from Server $(uname -n). " ; echo "Started from MonIdx.sh, If any question contact SPOC_DBA@ubp.ch" ; uuencode $FILE_NAME $FILE_NAME) | mail -s "Index Report for $DbSid" ${MAIL_LIST}

fi
}

#---------------------------------------------
# Main
#---------------------------------------------
# set -xv
if [[ "$FuncToDo" == "List" ]]
then
        DbSid=$2
        SchemaName=$3
        LogCons "Database Name: $DbSid"
        LogCons "Schema Name: $DbSid"
        List
elif [[ "$FuncToDo" == "Enable" ]]
then
        DbSid=$2
        SchemaName=$3
        LogCons "Database Name: $DbSid"
        LogCons "Schema Name: $DbSid"
        Enable 
elif [[ "$FuncToDo" == "Disable" ]]
then
        DbSid=$2
        SchemaName=$3
        LogCons "Database Name: $DbSid"
        LogCons "Schema Name: $DbSid"
        Disable
elif [[ "$FuncToDo" == "Report" ]]
then
        DbSid=$2
        SchemaName=$3
        LogCons "Database Name: $DbSid"
        LogCons "Schema Name: $DbSid"
        Report
else
        usage
fi

VolMin

if [[ ! -z "$MAIL_LIST"  ]]
then
        MailReport
fi
