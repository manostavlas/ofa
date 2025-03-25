#!/bin/ksh

# set -xv

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

SourceDB=$1
TargetDB=$2
WorkDB=$3

TimeStampLong=$(date +"%y%m%d_%H%M%S")
TimeStamp=$(date +"%H%M%S")

TnsLog=$OFA_LOG/tmp/TnsLog.$SourceDB.$TargetDB.${WorkDB}.$$.$PPID.log
SqlLog=$OFA_LOG/tmp/SqlLog.$SourceDB.$TargetDB.${WorkDB}.$$.$PPID.log
DiffFile=$OFA_LOG/tmp/DiffFile.$SourceDB.$TargetDB.${WorkDB}.$TimeStampLong.log
RunMmDp

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DiffCheckCol.sh [DB_1] [DB_2] [WORK_SID]
##
##
## Parameter file directory:  $OFA_SCR/refresh/[TARGET_SID]/
##
## Paremeter:
##
## DB_1:          SID of database to compare with. 
## DB_2:          SID of database to compare with. 
## WORK_SID:      Work database, 
##                Have to be on the server from where the script are running.
##
## Function:
## 
## Script will compare all none system tables.
## 
## Compare column name and column definition. 
## Generating an diff report:
##          $OFA_LOG/tmp/DiffFile.[SOURCE_SID].[TARGET_SID].[WORK_SID].YYMMDD_HHMMSS.log
##
#
__EOF
exit 1
}
#---------------------------------------------------------
CreateTab ()
#---------------------------------------------------------
{
TabType=$1
TabName=OFA_${TabType}_TAB_COL

LogCons "Creation of table: $TabName in DB:$WorkDB"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
Create or replace directory EXT_TAB_DIR as '$OFA_DB_DATA/${WorkDB}';
__EOF

Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Creation oracle directory entry EXT_TAB_DIR as '$OFA_DB_DATA/${WorkDB}'"
	LogCons "Log file: $SqlLog"
        exit 1
    fi

    LogCons "Table $TabName in DB: created"
    LogCons "Log file: $SqlLog"



sqlplus -s "/as sysdba" << __EOF > /dev/null 2>&1
DROP TABLE ${TabName} CASCADE CONSTRAINTS;
__EOF

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
CREATE TABLE ${TabName}
(
  INSTANCE_NAME VARCHAR2(16),
  OWNER        VARCHAR2(128),
  TABLE_NAME   VARCHAR2(128),
  COLUMN_NAME  VARCHAR2(128),
  DATA_TYPE    VARCHAR2(128),
  CHAR_LENGTH  NUMBER
)
ORGANIZATION EXTERNAL
  (  TYPE ORACLE_LOADER
     DEFAULT DIRECTORY EXT_TAB_DIR
     ACCESS PARAMETERS 
       ( FIELDS TERMINATED BY ',' )
     LOCATION (EXT_TAB_DIR:'OFA_${TabType}_TAB_COL.dbf')

  )
REJECT LIMIT 0;
__EOF


Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Creation Table: $TabName in DB: Logfile: $SqlLog"
        exit 1
    fi

    LogCons "Table $TabName in DB: created"
    LogCons "Log file: $SqlLog"

echo ""
}
#---------------------------------------------------------
GetData ()
#---------------------------------------------------------
{
DbToConn=$1
TabType=$2
DataFile=$OFA_DB_DATA/${WorkDB}/OFA_${TabType}_TAB_COL.dbf

LogCons "Get data from DB: $DbToConn Type: ${TabType} Datafile: ${DataFile}"

sqlplus -s $CONNECT__STRING@$DbToConn << __EOF > $SqlLog 2>&1
SET pagesize 0;
SET trimspool ON;
SET linesize 2000;
SET heading off;
SET feedback off;
SET echo off;
SET timing off;
spool ${DataFile}
select c.INSTANCE_NAME||','||a.OWNER||','||a.TABLE_NAME||','||a.COLUMN_NAME||','||a.DATA_TYPE||','||a.CHAR_LENGTH||',' from DBA_TAB_COLUMNS a, dba_objects b, V\$INSTANCE c
where a.OWNER not in 
(
'ANONYMOUS',
'ANTDBO',
'ANTDBO_READ',
'APPQOSSYS',
'ASG',
'AUDSYS',
'CMI',
'DBSFWUSER',
'DBSNMP',
'DIP',
'GGSYS',
'GSMADMIN_INTERNAL',
'GSMCATUSER',
'GSMUSER',
'JHA',
'JHU',
'MGW_ADMIN',
'MGW_AGENT',
'OJVMSYS',
'ORACLE_OCM',
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

    LogCons "Loaded data from  DB: $DbToConn Type: ${TabType} Datafile: ${DataFile}"
    LogCons "Log file: $SqlLog"

echo ""
}
#---------------------------------------------------------
CheckData ()
#---------------------------------------------------------
{
TabType=$1
TabName=OFA_${TabType}_TAB_COL

LogCons "Check loaded data Table: ${TabName}"
sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
SET pagesize 0;
SET trimspool ON;
SET linesize 2000;
SET heading off;
SET feedback off;
SET echo off;
SET timing off;

select count(*) from $TabName;
__EOF

Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Getting data from table: $TabName"
        LogCons "Log file: $SqlLog"
        exit 1
    fi
	
NumberOfRows=$(cat $SqlLog)
    LogCons "Number of rows: $NumberOfRows"
    LogCons "Log file: $SqlLog"
echo ""
}
#---------------------------------------------------------
DiffData ()
#---------------------------------------------------------
{
LogCons "Diff data between $SourceDB and $TargetDB"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1

SET feedback off;
SET echo off;
SET timing off;
SET trimspool ON;
SET linesize 2000;



col DATA_TYPE form a32
col OWNER form a32
col TABLE_NAME form a32
col COLUMN_NAME form a32
col INSTANCE_NAME form a16

spool $DiffFile



-- select * from OFA_Source_${SourceDB}_TAB_COL
-- minus 
-- select * from OFA_Target_${TargetDB}_TAB_COL order by 1,2;

-- select * from OFA_Target_${TargetDB}_TAB_COL
-- minus 
-- select * from OFA_Source_${SourceDB}_TAB_COL order by 1,2;

TTITLE CENTER -
'****************************************** Tables and columns only in ${SourceDB} ******************************************'
-- Only in OFA_Source_${SourceDB}_TAB_COL;
select a.* from 
OFA_Source_${SourceDB}_TAB_COL a,
(select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from OFA_Source_${SourceDB}_TAB_COL
minus
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from OFA_Target_${TargetDB}_TAB_COL order by 1,2) b
where 
a.owner=b.owner and a.table_name = b.table_name and a.column_name = b.column_name
order by a.instance_name,a.owner,a.table_name,a.COLUMN_NAME;

TTITLE CENTER -
'****************************************** Tables and columns only in ${TargetDB} ******************************************'

-- Only in OFA_Target_${TargetDB}_TAB_COL;
select a.* from 
OFA_Target_${TargetDB}_TAB_COL a,
(select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from OFA_Target_${TargetDB}_TAB_COL
minus
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from OFA_Source_${SourceDB}_TAB_COL order by 1,2) b
where 
a.owner=b.owner and a.table_name = b.table_name and a.column_name = b.column_name
order by a.instance_name,a.owner,a.table_name,a.COLUMN_NAME;

-- Diff on columns
TTITLE CENTER -
'****************************************** Diff on columns ${TargetDB} and ${SourceDB} ******************************************'

col CHAR_LENGTH form a32
select 
    a.instance_name    || ' | ' || b.instance_name as INSTANCE_NAME,
    a.owner,
    a.table_name,
    a.column_name    || ' | ' || b.column_name as COLUMN_NAME, 
    a.data_type      || ' | ' || b.data_type as DATA_TYPE, 
    a.char_length    || ' | ' || b.char_length as CHAR_LENGTH
      from 
     OFA_Source_${SourceDB}_TAB_COL a,
     OFA_Target_${TargetDB}_TAB_COL b
where 
     a.table_name =  b.table_name 
and  a.OWNER = b.OWNER     
and  a.INSTANCE_NAME <> b.INSTANCE_NAME
and  ( 
       a.data_type      <> b.data_type   or 
       a.char_length    <> b.char_length or
       a.COLUMN_NAME    <> b.COLUMN_NAME 
       -- a.data_scale     <> b.data_scale    or 
       -- a.data_precision <> b.data_precision
     )
and a.column_name = b.column_name;


spool off
__EOF

Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Diff between $SourceDB and $TargetDB"
        LogCons "Log file: $SqlLog"
        exit 1
    fi
    
    LogCons "Diff file: $DiffFile"
    LogCons "Log file: $SqlLog"


echo ""
}
#---------------------------------------------------------
CleanUp ()
#---------------------------------------------------------
{
LogCons "Clean up table and files"
LogCons "drop tables: OFA_Target_${TargetDB}_TAB_COL, OFA_Source_${SourceDB}_TAB_COL"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
DROP TABLE OFA_Target_${TargetDB}_TAB_COL CASCADE CONSTRAINTS;
DROP TABLE OFA_Source_${SourceDB}_TAB_COL CASCADE CONSTRAINTS;
__EOF

LogCons "Log file: $SqlLog"

MvDataFile=$(ls -lrt $OFA_DB_DATA/${WorkDB}/OFA_*_${SourceDB}_TAB_COL*.log $OFA_DB_DATA/${WorkDB}/OFA_*_${TargetDB}_TAB_COL*.log | awk '{print $9}')
RmDataFile=$(ls -lrt $OFA_DB_DATA/${WorkDB}/OFA_*_${SourceDB}_TAB_COL*.dbf $OFA_DB_DATA/${WorkDB}/OFA_*_${TargetDB}_TAB_COL*.dbf | awk '{print $9}')

LogCons "Files moved to $OFA_LOG/tmp/: ${MvDataFile}" 
mv $OFA_DB_DATA/${WorkDB}/OFA_*_${SourceDB}_TAB_COL*.log $OFA_LOG/tmp/ > /dev/null 2>&1
mv $OFA_DB_DATA/${WorkDB}/OFA_*_${TargetDB}_TAB_COL*.log $OFA_LOG/tmp/ > /dev/null 2>&1

LogCons "Files deleted: ${RmDataFile}" 
rm $RmDataFile > /dev/null 2>&1
}
#---------------------------------------------------------
SetConnection ()
#---------------------------------------------------------
{

ConnectDB=$1

LogCons "Getting/Testing connect string to $ConnectDB database.."

LogCons "Tnsping .............. ($ConnectDB)"
tnsping $ConnectDB > $TnsLog 2>&1
# tnsping $ConnectDB 
    if [[ $? -ne 0 ]]
    then
        LogCons "Didn't Connection to $ConnectDB tnsping (TNSNAMES)"
        LogCons "log file: $TnsLog"
        LogCons "Trying via Ldap now"
        LogCons "Connecting to LDAP"
        Ldaping $ConnectDB > $TnsLog 2>&1 
        if [[ $? -ne 0 ]]
        then
                LogCons "ERROR: Connection to $ConnectDB via LDAP"
		LogCons "Log file: $TnsLog"
                exit 1
        else
                ConnectionString=$(Ldaping $ConnectDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
                if [[ ! -z "$ConnectionString" ]]
                then
			LogCons "Connect via Ldap. "$ConnectionString""
                        export TNS_ADMIN=/tmp
			tnsping "$ConnectionString"  > $TnsLog 2>&1
			# tnsping "$ConnectionString" 
        		if [[ $? -ne 0 ]]
			        then
                		LogCons "ERROR: Connection to $ConnectDB via LDAP..........."
				LogCons "Log file: $TnsLog"
                		exit 1
			else
				LogCons "Connection to $ConnectDB OK!"
			fi
                else
                        LogError "ERROR: Connection string to $ConnectDB"
			LogCons "Log file: $TnsLog"
                        unset TNS_ADMIN
                        exit 1
                fi
        fi
    else
        ConnectionString=$(tnsping $ConnectDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
	LogCons "Connection to $ConnectDB OK!"
    fi
echo ""
}
#---------------------------------------------------------
# Main
#---------------------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        SourceDB                   \
        TargetDB                   \
        WorkDB                     \
     && LogIt "Variables complete" \
     || usage

OraEnv $WorkDB || BailOut "Failed OraEnv \"$WorkDB\""

CONNECT__STRING=$InIts/$MmDp

SetConnection $SourceDB
SetConnection $TargetDB
# SetConnection ${WorkDB}

CreateTab Source_${SourceDB}
CreateTab Target_${TargetDB}

GetData $SourceDB Source_${SourceDB}
CheckData Source_${SourceDB}

GetData $TargetDB Target_${TargetDB}
CheckData Target_${TargetDB}

DiffData

CleanUp
