#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

SourceDB=$1

TimeStampLong=$(date +"%y%m%d_%H%M%S")
TimeStamp=$(date +"%H%M%S")

SqlLog=$OFA_LOG/tmp/SqlLog.ExtColInfoOra.$SourceDB.$$.$PPID.log
DataFile=$OFA_LOG/tmp/${SourceDB}_TAB_COL_${TimeStampLong}.dat

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ExtColInfoOra.sh [DB_SID]
##
## Paremeter:
##	DB_SID of database
##
## Function:
## 
## Generating a file wiht all none system tables col info.
##
## File:
##	$OFA_LOG/tmp/[DATABASE_NAME]_TAB_COL_YYYYMMDD_HH24MMSS.dat
## 
#
__EOF
exit 1
}
#---------------------------------------------------------
GetData ()
#---------------------------------------------------------
{

LogCons "Get data from DB: ${SourceDB}" 
LogCons "Datafile: ${DataFile}"
LogCons "Log file: ${SqlLog}"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
SET pagesize 0;
SET trimspool ON;
SET linesize 2000;
SET heading off;
SET feedback off;
SET echo off;
SET timing off;
spool ${DataFile}
select c.INSTANCE_NAME||','||a.OWNER||','||a.TABLE_NAME||','||a.COLUMN_NAME||','||a.DATA_TYPE||','||a.CHAR_LENGTH||',$TimeStampLong,' 
from DBA_TAB_COLUMNS a, dba_objects b, V\$INSTANCE c
where a.OWNER not in 
(
'ANONYMOUS',
'ANTDBO',
'ANTDBO_READ',
'APPQOSSYS',
'ASG',
'AUDSYS',
'CMI',
'CTXSYS',
'DBSFWUSER',
'DBSNMP',
'DIP',
'DVSYS',
'GGSYS',
'GSMADMIN_INTERNAL',
'GSMCATUSER',
'GSMUSER',
'IMADVISOR',
'JHA',
'JHU',
'LBACSYS',
'MDSYS',
'MGW_ADMIN',
'MGW_AGENT',
'OJVMSYS',
'ORACLE_OCM',
'ORDDATA',
'ORDSYS',
'OUTLN',
'REMOTE_SCHEDULER_AGENT',
'SUPDBO',
'SUPDBO_READ',
'SYS$UMF',
'SYS',
'SYSBACKUP',
'SYSDG',
'SYSKM',
'SYSRAC',
'SYSTEM',
'TMS',
'UBP_ADMIN',
'UTL_ADMIN',
'WMSYS',
'XDB',
'XS$NULL'
)
and b.object_type='TABLE'
and a.owner=b.owner
and a.table_name=b.object_name
order by a.owner, a.table_name 
;
spool off
__EOF

Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Getting data........"
	LogCons "Log file: $SqlLog"
        exit 1
    fi

echo ""
}
#---------------------------------------------------------
CheckData ()
#---------------------------------------------------------
{
NumberOfRows=$(wc -l ${DataFile})
LogCons "Number of rows: $NumberOfRows"
echo ""
}
#---------------------------------------------------------
# Main
#---------------------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        SourceDB                   \
     && LogIt "Variables complete" \
     || usage

OraEnv $SourceDB || BailOut "Failed OraEnv \"$WorkDB\""

GetData $SourceDB
CheckData 

