#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


DbSid=$1
NumberOfHours=$2
MAIL_LIST=$3

ScriptName=$(basename $0)
SqlLog=$OFA_LOG/tmp/$ScriptName.SqlLog.$DbSid.$$.$PPID.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: $ScriptName [SID] [NUMBER_HOURS] [MAIL_LIST]
##
##
## Paremeter:
##
## SID: Name of the database
## NUMBER_HOUR: Number of hour back from script time of the start time of the report....
## MAIL_LIST: Mailing list for the report
##
#
__EOF
exit 1
}



    CheckVar          \
        NumberOfHours  \
    || BailOut "Missings parameter: NUMBER_HOUR: Number of hour back from script time of the start time of the report.... "

    CheckVar          \
        MAIL_LIST  \
    || BailOut "Missings parameter: MAIL_LIST: Who to mail the report to (e.g. "asg@ext.ubp,SPOC_DBA_MiddleWare@ubp.ch")"


    CheckVar          \
        DbSid  \
    || BailOut "Missings parameter: DbSid: Database name"


OraEnv $DbSid
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                usage
        fi



LogCons "SQL log file:$SqlLog"




sqlplus -s "/as sysdba" << ___EOF >> $SqlLog 
--REM
--REM Usage: DoSqlQ awr_report_hourly.sql [NUMBER_HOUR]
--REM
--REM Description:
--REM
--REM Paramete(s)
--REM      NUMBER_HOUR: Number of hour back from script time of the start time of the report....
--REM
--REM      Create AWR report.
--REM
--REM      Start snap id: "Start time of script" - NUMBER_HOUR
--REM      End snap id: Start time of script.
--REM
--REM      Create the AWR report in $OFA_LOG/tmp
--REM



SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;

column END_DATE new_val END_DATE;
column START_DATE new_val START_DATE;
column INSTANCE_NAME new_val INSTANCE_NAME;

-- END_DATE.
prompt ****** Snapshut END time ******
select
to_char(min(end_interval_time),'DD-MM-YYYY_HH24MI') END_DATE
  FROM
  (
  select to_char(max(end_interval_time),'DDMMYYYY_HH24MI') MAX_DATE
  from dba_hist_snapshot
-- WHERE TO_CHAR(end_interval_time, 'DY') = 'MON'
  ) a,
  dba_hist_snapshot
  WHERE
  TO_CHAR(end_interval_time,'DDMMYYYY_HH24MI' ) = a.MAX_DATE;

-- START_DATE
prompt ****** Snapshut START time ******
select
to_char(min(end_interval_time),'DD-MM-YYYY_HH24MI') START_DATE
  FROM
  (
  select to_char(max(end_interval_time)-$NumberOfHours/24,'DDMMYYYY_HH24MI') MAX_DATE
  from dba_hist_snapshot
-- WHERE TO_CHAR(end_interval_time, 'DY') = 'MON'
  ) a,
  dba_hist_snapshot
  WHERE
  TO_CHAR(end_interval_time,'DDMMYYYY_HH24MI' ) = a.MAX_DATE;

-- INSTANCE_NAME
prompt ****** Instance Name *****
select
instance_name
from v\$instance;


set term off;
spool $OFA_LOG/tmp/awr_report.&INSTANCE_NAME..&START_DATE..&END_DATE..html
-- spool /tmp/awr_report.&INSTANCE_NAME..&START_DATE..&END_DATE..html

declare
database_id  number;
database_instance  number;
begin_snap  number;
end_snap  number;

BEGIN
select instance_number into database_instance from v\$instance;
select dbid into database_id from v\$database;

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



FOR c1_rec IN
      (SELECT output
         FROM TABLE (DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(database_id,  database_instance, begin_snap, end_snap)))
         -- FROM TABLE (DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(dbid, inst_id, bid, eid, 8 )))
   LOOP
      DBMS_OUTPUT.put_line(c1_rec.output);
   END LOOP;
END;
/
spool off
set term on;

prompt ****** Report name: ******
prompt   $OFA_LOG/tmp/awr_report.&INSTANCE_NAME..&START_DATE..&END_DATE..html
___EOF


FILE_NAME=$(ls -1rt $OFA_LOG/tmp/awr_report.$ORACLE_SID* | tail -1)



# Set mail command
MailError=$(mail -V >/dev/null 2>&1  ; echo $?)

if [[ $MailError -eq 0 ]]
then
	FILE_NAME=$(ls -1rt $OFA_LOG/tmp/awr_report.$ORACLE_SID* | tail -1) ; (echo "This are a automatic genereted Performance Report from Server $(uname -n). " ; echo "Job started via GRID controli, If any question contact SPOC_DBA@ubp.ch") | mail -a $FILE_NAME -s "Performance report (AWR) for $ORACLE_SID" ${MAIL_LIST};

else

	FILE_NAME=$(ls -1rt $OFA_LOG/tmp/awr_report.$ORACLE_SID* | tail -1) ; (echo "This are a automatic genereted Performance Report from Server $(uname -n). " ; echo "Job started via GRID controli, If any question contact SPOC_DBA@ubp.ch" ; uuencode $FILE_NAME $FILE_NAME) | mail -s "Performance report (AWR) for $ORACLE_SID" ${MAIL_LIST}

fi
#








