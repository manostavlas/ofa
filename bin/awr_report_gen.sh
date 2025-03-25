#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


DbSid=$1
StartSnapId=$2
EndSnapId=$3
MAIL_LIST=$4

ScriptNameShort=$(basename $0 .sh)
ScriptName=$(basename $0)
SqlLog=$OFA_LOG/$ScriptNameShort/$ScriptName.SqlLog.$DbSid.$$.$PPID.log

#--------------------------------------------------------------------------
function MailReport
#--------------------------------------------------------------------------
{
# Set mail command
LogCons "Sending mail to: $MAIL_LIST"
MailError=$(mail -V >/dev/null 2>&1  ; echo $?)

if [[ $MailError -eq 0 ]]
then
LogCons "* Sending mail to: $MAIL_LIST"
	(echo "This are a automatic genereted Performance Report from Server $(uname -n). " ; echo "Job started via GRID controli, If any question contact SPOC_DBA@ubp.ch") | mail -a $FILE_NAME -s "Performance report (AWR) for $ORACLE_SID" ${MAIL_LIST};

else
LogCons "** Sending mail to: $MAIL_LIST"
	(echo "This are a automatic genereted Performance Report from Server $(uname -n). " ; echo "Job started via GRID controli, If any question contact SPOC_DBA@ubp.ch" ; uuencode $FILE_NAME $FILE_NAME) | mail -s "Performance report (AWR) for $ORACLE_SID" ${MAIL_LIST}

fi
}
#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
## Run AWR report:
## Usage: $ScriptName [SID] [START_SNAPID] [END_SNAPID] [MAIL_LIST]
##
## List all snapshut ID's
## Usage: $ScriptName [SID] Info
##
##
## Paremeter:
##
## SID: Name of the database
## START_SNAPID: [Start snap id] 
## START_SNAPID: [Info]  list all snapshuts 
## START_SNAPID: [Snap]  Create a snapshut 
##
## END_SNAPID: End Start snap id. 
## MAIL_LIST: Mailing list for the report
## e.g. asg@ubp.ch,jean.hary@ubp.ch
##
#
__EOF
exit 1
}
#---------------------------------------------
Info ()
#---------------------------------------------
{

OraEnv $DbSid
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                usage
        fi

sqlplus -s "/as sysdba" << ___EOF >> $SqlLog
set feedback off;
set timing off;
select SNAP_ID as "Snapshut ID:", to_char(END_INTERVAL_TIME,'DD-MM-YYYY HH24:MI:SS') as "Snapshut Time:" from dba_hist_snapshot order by 1 DESC;
___EOF

ErrorMess=$(grep ORA- $SqlLog)

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLog"
        exit 1
fi

more $SqlLog
exit
}
#---------------------------------------------
Snap ()
#---------------------------------------------
{
LogCons "Create a snapshot" 
DoSql "EXEC DBMS_WORKLOAD_REPOSITORY.create_snapshot;"
exit
}
#---------------------------------------------
# MAIN
#---------------------------------------------
LogCons "Log: $OFA_LOG"
if [[ "$StartSnapId" == "Info" ]] 
then
	Info
fi

if [[ "$StartSnapId" == "Snap" ]]
then
        Snap
fi


    CheckVar          \
        StartSnapId  \
        && LogCons "Variables OK!"    \
        || usage

    CheckVar          \
        EndSnapId  \
        && LogCons "Variables OK!"    \
        || usage

    CheckVar          \
        DbSid  \
        && LogCons "Variables OK!"    \
        || usage


OraEnv $DbSid
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                usage
        fi




LogCons "SQL log file:$SqlLog"

sqlplus -s "/as sysdba" << ___EOF >> $SqlLog 
SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set timing off;

column END_DATE new_val END_DATE;
column START_DATE new_val START_DATE;
column INSTANCE_NAME new_val INSTANCE_NAME;

-- END_DATE.
prompt ****** Snapshut END time ******
select
to_char(end_interval_time,'DDMMYYYY_HH24MI') END_DATE
  FROM dba_hist_snapshot
  where snap_id = $EndSnapId;

-- START_DATE
prompt ****** Snapshut START time ******
select
to_char(end_interval_time,'DDMMYYYY_HH24MI') START_DATE
  FROM dba_hist_snapshot
  where snap_id = $StartSnapId;

-- INSTANCE_NAME
prompt ****** Instance Name *****
select
INSTANCE_NAME
from v\$instance;

set term off;
prompt ****** Report name: ******
prompt   $OFA_LOG/$ScriptNameShort/awr_report.&INSTANCE_NAME..&START_DATE.-.&END_DATE..html
spool $OFA_LOG/$ScriptNameShort/awr_report.&INSTANCE_NAME..&START_DATE-&END_DATE..$StartSnapId-$EndSnapId.html

declare
database_id  number;
database_instance  number;
begin_snap  number;
end_snap  number;
sqlstring varchar2(1024);

BEGIN
select instance_number into database_instance from v\$instance;
select dbid into database_id from v\$database;

/*
-- Get snap_id "END" MONDAY but MIN time.
select min(snap_id) into end_snap
  FROM
  (
  select to_char(max(begin_interval_time),'DDMMYYYY_HH24MI') MAX_DATE
  from dba_hist_snapshot -- WHERE TO_CHAR(end_interval_time, 'DY') = 'MON'
  ) a,
  dba_hist_snapshot
  WHERE
  TO_CHAR(begin_interval_time,'DDMMYYYY_HH24MI' ) = a.MAX_DATE;

-- Get snap_id "BEGIN" MONDAY minus 7 days but MIN time
select min(snap_id) into begin_snap
  FROM
  (
  select to_char(max(begin_interval_time)-$NumberOfHours/24,'DDMMYYYY_HH24MI') MAX_DATE
  from dba_hist_snapshot -- WHERE TO_CHAR(end_interval_time, 'DY') = 'MON'
  ) a,
  dba_hist_snapshot
  WHERE
  TO_CHAR(begin_interval_time,'DDMMYYYY_HH24MI' ) = a.MAX_DATE;
*/

-- sqlstring := 'SELECT output FROM TABLE (DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(database_id, database_instance, $StartSnapId, $EndSnapId))';
-- dbms_output.put_line('SQL:'||sqlstring);

-- EXECUTE IMMEDIATE sqlstring;


FOR c1_rec IN
      (SELECT output
          FROM TABLE (DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(database_id,  database_instance, $StartSnapId, $EndSnapId)))
    LOOP
       DBMS_OUTPUT.put_line(c1_rec.output);
    END LOOP;
END;
/

spool off
set term on;

prompt ****** Report name: ******
prompt  $OFA_LOG/$ScriptNameShort/awr_report.&INSTANCE_NAME..&START_DATE-&END_DATE..$StartSnapId-$EndSnapId.html 
___EOF

FILE_NAME=$( tail -1 $SqlLog)

LogCons "AWR Report name: $FILE_NAME"

# ErrorMess=$(grep ORA- $SqlLog)
# if [[ ! -z "$ErrorMess" ]]
# then
# 	LogError "Log file: $SqlLog"
#         exit 1
# fi


if [[ ! -z "$MAIL_LIST"  ]]
then
        MailReport
fi

