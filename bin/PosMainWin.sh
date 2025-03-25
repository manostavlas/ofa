#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

DbSid=$1
NumberOfDays=$3
FuncToDo=$2

TimeStamp=$(date +"%H%M%S")

OutPutLog=$OFA_LOG/tmp/PosMainWin.Output.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp01=$OFA_LOG/tmp/PosMainWin.OutputTmp01.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp02=$OFA_LOG/tmp/PosMainWin.OutputTmp02.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp03=$OFA_LOG/tmp/PosMainWin.OutputTmp03.log.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/PosMainWin.SqlLog.$$.$PPID.$TimeStamp.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: PosMainWin.sh  [SID] [Function]
##
##
## Paremeter:
##
## SID:
##      Name of the database
## 
## FUNCTION:
## 	Postpone: Postpone the maintenance window of the day to the next run.
## 		  e.g.
## 		  Today friday:
## 		  The FRIDAY maintenance window will moved to next FRIDAY.
##
##      Info:     Shows details for the maintenance windows
##
#
__EOF
LogError "Parameter error/missing..."
exit 1
}
#---------------------------------------------
InfoWindows ()
#---------------------------------------------
{
echo ""
LogCons "Get info of the maintenance windows database: $DbSid"
sqlplus -s "/as sysdba" << __EOF >> $SqlLog 2>&1

col WINDOW_NAME form a30;
col ENABLED form a15;
col ACTIVE form a15;
col 'Next Start Date' form a25;
col 'Last Start Date' form a25;

set linesize 1000
set trimout on;
set trim on;
set timing off;
set feedback off;

select 
    WINDOW_NAME, 
    to_char(NEXT_START_DATE,'DD-MM-RR HH24.MI.SS') as "Next Start Date",
    to_char(LAST_START_DATE,'DD-MM-RR HH24.MI.SS') as "Last Start Date",
    ENABLED,
    ACTIVE 
from 
    DBA_SCHEDULER_WINDOWS;
__EOF

SqlError=$(grep ORA- $SqlLog)

if [[ ! -z $SqlError ]]
then
        LogError "Error getting info. Log file: $SqlLog"
else
	cat $SqlLog
fi
echo ""
}
#---------------------------------------------
Postpone ()
#---------------------------------------------
{
LogCons "Postpone the maintenance windows for ${NumberOfDays} on database: $DbSid"
sqlplus -s "/as sysdba" << __EOF >> $SqlLog 2>&1
SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set timing off;

-- alter session set NLS_TIMESTAMP_TZ_FORMAT = 'DD-MM-RR HH24.MI.SSXFF TZR';
alter session set NLS_TIMESTAMP_TZ_FORMAT = 'DD-MM-RR HH24.MI.SSXFF TZH:TZM';

DECLARE
   v_window_name		VARCHAR2 (100);
   v_full_window_name		VARCHAR2 (100);
   v_start_date			VARCHAR2 (100);
   v_next_start_date		VARCHAR2 (100);

   v_window_name_new		VARCHAR2 (100);
   v_full_window_name_new	VARCHAR2 (100);
   v_start_date_new		VARCHAR2 (100);
   v_next_start_date_new	VARCHAR2 (100);

   v_extent_date		VARCHAR2 (100);
   v_extent_date_new		VARCHAR2 (100);

BEGIN
	SELECT
		a.window_name, 
		'SYS.'||a.window_name as full_window_name, 
		a.start_date, 
		a.next_start_date, 
		a.next_start_date + INTERVAL '7' DAY as extent_date
	INTO 
		v_window_name,
		v_full_window_name,
		v_start_date,
		v_next_start_date,
		v_extent_date
	FROM
		DBA_SCHEDULER_WINDOWS a,
	(select replace(to_char(sysdate,'DAY')||'_WINDOW',' ','') as window_name from dual) b
	where a.window_name = b.window_name;

	dbms_output.put_line('Current: Window name: '||v_full_window_name||' Start date: '||v_start_date||' Next start date: ' || v_next_start_date);
        dbms_output.put_line('Extent_date: '||v_extent_date);

	DBMS_SCHEDULER.SET_ATTRIBUTE (
	name => v_full_window_name,
	attribute => 'START_DATE',
	value => v_extent_date);

        SELECT 
		a.window_name, 
		'SYS.'||a.window_name as full_window_name, 
		a.start_date, 
		a.next_start_date, 
		a.next_start_date + INTERVAL '7' DAY as extent_date
        INTO
                v_window_name_new,
                v_full_window_name_new,
                v_start_date_new,
                v_next_start_date_new,
                v_extent_date_new
        FROM
                DBA_SCHEDULER_WINDOWS a,
        (select replace(to_char(sysdate,'DAY')||'_WINDOW',' ','') as window_name from dual) b
        where a.window_name = b.window_name;

	dbms_output.put_line('New:     Window name: '||v_full_window_name_new||' Start date: '||v_start_date_new||' Next start date: ' || v_next_start_date_new);

        
END;
/

__EOF

SqlError=$(grep ORA- $SqlLog)
if [[ ! -z $SqlError ]]
then
	LogError "Error setting new schedule time. Log file: $SqlLog"
else
	cat $SqlLog
fi

}
#---------------------------------------------
# Main 
#---------------------------------------------
if [[ -z $NumberOfDays ]]
then
	NumberOfDays=1
fi



    LogIt "Check variable completeness"
    CheckVar                       \
    DbSid                          \
    FuncToDo			   \
    NumberOfDays                   \
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbSid >/dev/null 2>&1
        ExitCode=$?
        if [[ $ExitCode -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

if [[ "$FuncToDo" == "Info" ]]
then
        InfoWindows
elif [[ "$FuncToDo" == "Postpone" ]]
then
        Postpone
else
        usage
	exit 1
fi



