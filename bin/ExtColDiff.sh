#!/bin/ksh

# set -xv

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

DB_1=$1
DB_2=$2
WorkDB=$3
MAIL_LIST=$4

TimeStampLong=$(date +"%y%m%d_%H%M%S")
TimeStamp=$(date +"%H%M%S")

TableName=COLDIFF.T_COL_DIFF_DB

SqlLog=$OFA_LOG/tmp/SqlLog.$DB_1.$DB_2.${WorkDB}.$$.$PPID.log
DiffFile=$OFA_LOG/tmp/DiffFile.$DB_1.$DB_2.${WorkDB}.$TimeStampLong.log

RunMmDp

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ExtColDiff.sh [DB_1] [DB_2] [WORDK_DB] <MAIL_LIST>
##
## Paremeter:
##
## DB_1:          SID of database to compare with. 
## DB_2:          SID of database to compare with. 
## WORK_SID:      Work database, 
##                Have to be on the server from where the script are running.
## MAIL_LIST      Option, where to mail the report e.g.: "asg@ubp.ch,tms@ubp.ch"
##
## Function:
## 
## Script will compare all none system tables.
## 
## Compare column name and column definition. 
## Generating an diff report:
##          $OFA_LOG/tmp/DiffFile.[DB_1].[DB_2].[WORK_SID].YYMMDD_HHMMSS.log
##
#
__EOF
exit 1
}
#---------------------------------------------------------
CheckData ()
#---------------------------------------------------------
{
for i in $DB_1 $DB_2
do
LogCons "Check loaded data Database: $i, Table: ${TableName}"
sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
SET pagesize 0;
SET trimspool ON;
SET linesize 2000;
SET heading off;
SET feedback off;
SET echo off;
SET timing off;

select count(*) from $TableName where instance_name = '$i';
__EOF

Error=$(grep "ORA-" ${SqlLog})

    if [[ ! -z $Error ]]
    then
        LogError "ERROR: Getting data from table: $TabName"
        LogCons "Log file: $SqlLog"
        exit 1
    fi
	
NumberOfRows=$(cat $SqlLog)

if [[ $NumberOfRows -eq 0 ]]
then
	LogError "No data for database: $i"
 	LogCons "Log file: $SqlLog"
	exit 1
else
    	LogCons "Number of rows: $NumberOfRows"
    	LogCons "Log file: $SqlLog"
	echo ""
fi
done 
}
#---------------------------------------------------------
DiffData ()
#---------------------------------------------------------
{
LogCons "Diff data between $DB_1 and $DB_2"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1

SET feedback off;
SET echo off;
SET timing off;
SET trimspool ON;
SET linesize 2000;



col DATA_TYPE form a32
col OWNER form a20
col TABLE_NAME form a32
col COLUMN_NAME form a45
col INSTANCE_NAME form a21
col CHAR_LENGTH form a16 

spool $DiffFile


-- New
prompt
prompt ****************************************** Tables and columns only in ${DB_1} ******************************************
-- Only in ${DB_1}
select a.* from
$TableName a,
(
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from $TableName where INSTANCE_NAME = '${DB_1}'
minus
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from $TableName where INSTANCE_NAME = '${DB_2}' order by 1,2
) b
/*
,
(
select
    a.table_name
      from
     (select * from $TableName where INSTANCE_NAME = '${DB_1}') a,
     (select * from $TableName where INSTANCE_NAME = '${DB_2}') b
where
     a.table_name =  b.table_name
and  a.OWNER = b.OWNER
and  a.INSTANCE_NAME <> b.INSTANCE_NAME
and  (
       a.data_type      <> b.data_type   or
       a.char_length    <> b.char_length or
       a.COLUMN_NAME    <> b.COLUMN_NAME
     )
and a.column_name = b.column_name
) c
*/
where
a.owner=b.owner and
a.table_name = b.table_name and
a.column_name = b.column_name and
a.data_type = b.data_type and
a.char_length=b.char_length and
a.instance_name = '${DB_1}'
-- a.owner <> c.owner and
-- a.table_name <> c.table_name and
-- a.column_name <> c.column_name
order by a.instance_name,a.owner,a.table_name,a.COLUMN_NAME;



-- New end
prompt
prompt ****************************************** Tables and columns only in ${DB_2} ******************************************
-- Only in ${DB_2}
select a.* from 
$TableName a,
(
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from $TableName where INSTANCE_NAME = '${DB_2}' 
minus
select OWNER,TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHAR_LENGTH from $TableName where INSTANCE_NAME = '${DB_1}' order by 1,2
) b
/*
,
(
select
    a.table_name
      from
     (select * from $TableName where INSTANCE_NAME = '${DB_1}') a,
     (select * from $TableName where INSTANCE_NAME = '${DB_2}') b
where
     a.table_name =  b.table_name
and  a.OWNER = b.OWNER
and  a.INSTANCE_NAME <> b.INSTANCE_NAME
and  (
       a.data_type      <> b.data_type   or
       a.char_length    <> b.char_length or
       a.COLUMN_NAME    <> b.COLUMN_NAME
     )
and a.column_name = b.column_name
) c
*/
where 
a.owner=b.owner and
a.table_name = b.table_name and
a.column_name = b.column_name and
a.data_type = b.data_type and
a.char_length=b.char_length and
a.instance_name = '${DB_2}'
-- a.owner <> c.owner and
-- a.table_name <> c.table_name and
-- a.column_name <> c.column_name
order by a.instance_name,a.owner,a.table_name,a.COLUMN_NAME;


-- Diff on columns
prompt
prompt ****************************************** Diff on columns ${DB_2} and ${DB_1} ******************************************

col CHAR_LENGTH form a16
col COLUMN_NAME form a54

select 
    a.instance_name    || ' | ' || b.instance_name as INSTANCE_NAME,
    a.owner,
    a.table_name,
    a.column_name    || ' | ' || b.column_name as COLUMN_NAME, 
    a.data_type      || ' | ' || b.data_type as DATA_TYPE, 
    a.char_length    || ' | ' || b.char_length as CHAR_LENGTH
      from 
     (select * from $TableName where INSTANCE_NAME = '${DB_1}') a,
     (select * from $TableName where INSTANCE_NAME = '${DB_2}') b
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
        LogError "ERROR: Diff between $DB_1 and $DB_2"
        LogCons "Log file: $SqlLog"
        exit 1
    fi
    
    LogCons "Diff file: $DiffFile"
    LogCons "Log file: $SqlLog"


echo ""
}
#--------------------------------------------------------------------------
function MailReport
#--------------------------------------------------------------------------
{
if [[ ! -z $MAIL_LIST ]]
then
	# Set mail command
	LogCons "Sending mail to: $MAIL_LIST"
	MailError=$(mail -V >/dev/null 2>&1  ; echo $?)

	if [[ $MailError -eq 0 ]]
	then
	LogCons "* Sending mail to: $MAIL_LIST"
	        (echo "This are a automatic genereted Report from Server $(uname -n). " ; echo "If any question contact SPOC_DBA@ubp.ch") | mail -a $DiffFile -s "Database diff col report $DB_1 and $DB_2" ${MAIL_LIST};

	else
	LogCons "** Sending mail to: $MAIL_LIST"
        	(echo "This are a automatic genereted Report from Server $(uname -n). " ; echo "If any question contact SPOC_DBA@ubp.ch" ; uuencode $DiffFile $DiffFile) | mail -s "Database diff col report $DB_1 and $DB_2" ${MAIL_LIST}

	fi
fi
}

#---------------------------------------------------------
# Main
#---------------------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        DB_1                   \
        DB_2                   \
        WorkDB                     \
     && LogIt "Variables complete" \
     || usage

OraEnv $WorkDB || BailOut "Failed OraEnv \"$WorkDB\""

CheckData

DiffData

MailReport
