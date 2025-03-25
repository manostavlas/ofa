#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


YesNo $(basename $0) || exit 1 && export RunOneTime=YES

VolMin

DbSid=$1
FuncToDo=$2



OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

SqlLog=$OFA_LOG/tmp/SqlLog.$DbSid.$$.$PPID.log
StatusFile=$OFA_LOG/tmp/StatusFile.$DbSid.$$.$PPID.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: MgwCheck.sh  [SID] [FUNCTION]
##
##
## Paremeter:
##
## SID:		        Name of the database
##	Name of the database
##
## FUNCTION:
##	Info	(Show status of MGW and Queues)
##	Queue	(Show the last 10 message in the queues)
##	Start	(Start the MGW)
##	Stop	(Stop the MGW)
##	Status	(Status the MGW)
##		
## Get status of MGW (Messaging Gateway) 
##
#
__EOF
exit 1
}
#---------------------------------------------

    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
	FuncToDo		   \
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

#---------------------------------------------
GetGlobalInfo ()
#---------------------------------------------
{
# Gateway info

MGWInitFile=$(DoSqlQ "select INITFILE from MGW_GATEWAY;")
MGWStatus=$(DoSqlQ "select agent_status from MGW_GATEWAY;")
MGWConnect=$(DoSqlQ "select host from dba_db_links where db_link='MGW_AGENT';")
MGWLogDirectory=$(grep log_directory $MGWInitFile | sed s/log_directory=//g)
MGWLogFile=$(ls -1rt $MGWLogDirectory | tail -1)
MGWLastLogFile=${MGWLogDirectory}/${MGWLogFile}
MGWLastError=$(DoSqlQ "select nvl(LAST_ERROR_MSG,'No error') from MGW_GATEWAY;")

echo "" > $StatusFile
echo "******************************************************************************** Messaging Gatway Configuration ********************************************************************************" >> $StatusFile 
echo "" >> $StatusFile
echo "MGW Init file:		$MGWInitFile" >> $StatusFile
echo "MGW Log directory:	$MGWLogDirectory" >> $StatusFile
echo "MGW Last log file:	$MGWLastLogFile" >> $StatusFile
echo "MGW Connect string:	$MGWConnect" >> $StatusFile
echo "MGW Status:		$MGWStatus" >> $StatusFile
echo "MGW Error message:	$MGWLastError" >> $StatusFile
echo "" >> $StatusFile

sqlplus -s "/as sysdba" << __EOF >> $SqlLog 2>&1 
set timing off;
set feedback off;

col DB_LINK_NAME for a30;
col HOST_NAME for a30;

select DB_LINK as DB_LINK_NAME, HOST as HOST_NAME from DBA_DB_LINKS where db_link='MGW_AGENT' order by DB_LINK_NAME;


-- select * from MGW_GATEWAY;
col link_name for a30
col link_type for a30
col agent_name for a30
-- select link_name, agent_name from mgw\$_links;

select link_name, link_type, agent_name from mgw_links order by 1;

col HOSTNAME for a20;
col LINK_NAME for a20;
col INTERFACE_TYPE for a20;
col CHANNEL for a20;
col QUEUE_MANAGER for a20;
col INBOUND_LOG_QUEUE for a30;
col OUTBOUND_LOG_QUEUE for a30;

select 
LINK_NAME, QUEUE_MANAGER, HOSTNAME, PORT, CHANNEL, 
INTERFACE_TYPE, MAX_CONNections,INBOUND_LOG_QUEUE, OUTBOUND_LOG_QUEUE  
from MGW_MQSERIES_LINKS order by 1;

__EOF

# cat $SqlLog >> $StatusFile




# Queue info
sqlplus -s "/as sysdba" << __EOF >> $SqlLog 2>&1 
prompt
prompt ************************************************************************************** Queue Configuration **************************************************************************************
set timing off;
set feedback off;

col status for a8;
col name for a30
col domain for a30
col provider_queue for a40
col link_name for a20;
select name as QUEUE_NAME, link_name, provider_queue, domain from mgw_foreign_queues order by 1;

col subscriber_id for a30
col PROPAGATION_TYPE for a20
col queue_name for a50
col destination for a50
select subscriber_id, propagation_type, queue_name, destination, status from mgw_subscribers order by 1;



col queue_name for a20;
col queue_table for a20;

select 
a.owner,
a.name as queue_name,
a.queue_table,
b.subscriber_id,
b.propagation_type,
-- b.queue_name,
b.destination,
b.status,
b.propagated_msgs
from dba_queues a, mgw_subscribers b where (owner||'.'||name = b.queue_name or owner||'.'||name =b.destination) order by 1,2;

prompt
prompt ************************************************************************************** Job Status/Configuration **************************************************************************************
col Job_name for a30;
col propagation_type for a20;
col source for a50;
col destination for a50;
col enabled for a8;
select Job_name, propagation_type, source, destination, enabled, link_name  from MGW_JOBS order by 1;

col status for a20;
col last_error_msg for a60;
select Job_name, status, failures, last_error_date, last_error_time, last_error_msg from MGW_JOBS order by 1;

prompt ************************************************************************************** Queue Subscriber Info **************************************************************************************

select owner, queue_name,a.queue_table, consumer_name from DBA_QUEUE_SUBSCRIBERS a,
(select
queue_table
from dba_queues a, mgw_subscribers b where (owner||'.'||name = b.queue_name or owner||'.'||name =b.destination)) b
where a.queue_table=b.queue_table
order by 1,2;


col SUBSCRIPTION_NAME for a50;
col LOCATION_NAME for a120;

select SUBSCRIPTION_NAME, LOCATION_NAME from 
(SELECT SUBSCRIPTION_NAME, LOCATION_NAME, replace(REGEXP_SUBSTR(SUBSCRIPTION_NAME,'[^.]+',1,1),'"') as owner_sub 
from 
DBA_SUBSCR_REGISTRATIONS) a,
(select
distinct owner
from dba_queues a, mgw_subscribers b where (owner||'.'||name = b.queue_name or owner||'.'||name =b.destination)) b
where 
a.owner_sub=b.owner
order by 1;

__EOF

ErrorMsg=$(grep ORA- $SqlLog)
if [[ ! -z "$ErrorMsg" ]]
then
	VolUp 1
	LogError "Error getting MGW info. Log: $SqlLog"
fi

cat $SqlLog >> $StatusFile

echo " " >> $StatusFile



cat $StatusFile
}
#---------------------------------------------
GetQueueInfo ()
#---------------------------------------------
{
echo ""
echo "Please wait..... (I'm sorting..)"
echo ""

sqlplus -s "/as sysdba" << __EOF > $SqlLog 
set echo off;
set feedback off;
set timing off;

create or replace function get_q_status
return sys_refcursor
as
   r sys_refcursor;
   stmt varchar2(32000);
cursor c_tables is
	select a.owner||'.AQ$'||a.queue_table as table_name from dba_queues a, mgw_subscribers b where (owner||'.'||name = b.queue_name or owner||'.'||name =b.destination) order by 1;						   
begin
   for x in c_tables loop
--           stmt := stmt || ' select queue, msg_state, enq_time, enq_user_id, deq_time, deq_user_id from (select * from ' || x.table_name ||' where rownum <10 order by queue, enq_time DESC, deq_time DESC) union all';
--           stmt := stmt || ' select queue, msg_state, enq_time, enq_user_id, deq_time, deq_user_id from (select * from ' || x.table_name ||' order by queue, enq_time DESC, deq_time DESC OFFSET 15 ROWS FETCH NEXT 15 ROWS ONLY) union all';
-- stmt := stmt || ' select queue, msg_state, enq_time, enq_user_id, deq_time, deq_user_id from (select * from ' || x.table_name ||' order by queue, enq_time DESC, deq_time DESC) where rownum <15 union all';
stmt := stmt || ' select queue, msg_state, enq_time, enq_user_id, deq_time, (deq_time-enq_time)*86400 as q_time_sec, deq_user_id from (select * from ' || x.table_name ||' order by queue, enq_time DESC, deq_time DESC) where rownum <15 union all';

   end loop;
     stmt := substr(stmt , 1 , length(stmt) - length('union all'));
--   dbms_output.put_line(stmt);
--   stmt := (stmt|| 'order by 1,3,5');
--   dbms_output.put_line(stmt);
   open r for stmt;
   return r;
end;
/
col queue form a40;
select get_q_status()  from dual;

------------------------------

set echo off;
set feedback off;
set timing off;

create or replace function get_q_avg_status
return sys_refcursor
as
   r sys_refcursor;
   stmt varchar2(32000);
cursor c_tables is
        select a.owner||'.AQ$'||a.queue_table as table_name from dba_queues a, mgw_subscribers b where (owner||'.'||name = b.queue_name or owner||'.'||name =b.destination) order by 1;
begin
   for x in c_tables loop
stmt := stmt || ' select queue, round(avg((deq_time-enq_time)*86400),1) as avg_q_time_sec from (select * from ' || x.table_name ||' order by queue, enq_time DESC, deq_time DESC) group by queue union all';
   end loop;
     stmt := substr(stmt , 1 , length(stmt) - length('union all'));
--   dbms_output.put_line(stmt);
--   stmt := (stmt|| 'order by 1,3,5');
--   dbms_output.put_line(stmt);
   open r for stmt;
   return r;
end;
/

col queue form a40;
select get_q_avg_status()  from dual;
__EOF

cat $SqlLog | awk '{if(NR>6)print}'
echo ""

}
#---------------------------------------------
MgwStart ()
#---------------------------------------------
{
OFA_CONS_VOL="-3"

LogCons "Starting MGW"
sqlplus -s "/as sysdba" << __EOF > $SqlLog
set echo off;
set feedback off;
set timing off;
exec DBMS_MGWADM.STARTUP;
exit
__EOF


SqlError=$(grep "ORA-" $SqlLog | head -1)
if [[ ! -z $SqlError ]]
then
        LogError "Error start MGW. Error: $SqlError"
	VolMin
	exit 1
fi

MgwStatus

}
#---------------------------------------------
MgwStop ()
#---------------------------------------------
{
OFA_CONS_VOL="-3"

LogCons "Stopping MGW"
sqlplus -s "/as sysdba" << __EOF > $SqlLog
set echo off;
set feedback off;
set timing off;
exec DBMS_MGWADM.SHUTDOWN;
exit
__EOF


SqlError=$(grep "ORA-" $SqlLog | head -1)
if [[ ! -z $SqlError ]]
then
        LogError "Error stopping MGW. Error: $SqlError"
        VolMin
        exit 1
fi

MgwStatus

}
#---------------------------------------------
MgwStartForce ()
#---------------------------------------------
{
        echo "Starting MGW (Force)"
}
#---------------------------------------------
MgwStopForce ()
#---------------------------------------------
{
        echo "Stopping MGW (Force)"
}
#---------------------------------------------
MgwStatus ()
#---------------------------------------------
{
OFA_CONS_VOL="-3"
        LogCons "Checking MGW status. Please wait......"
	sleep 10
        MgwStatus=$(DoSqlQ "select agent_status from MGW_GATEWAY;")
        LogCons "MGW status: $MgwStatus"
VolMin
}
#---------------------------------------------
# Main
#---------------------------------------------
MgwInstalled=$(DoSqlQ "select count(*) from dba_objectS where object_name = upper('MGW_GATEWAY');" | sed 's/[[:blank:]]//g' )
if [[ $MgwInstalled -eq 0 ]]
then
	 echo ""
	 echo "Oracle messaging gateway are NOT installed...."	
	 echo ""
	 exit 1
fi


if [[ "$FuncToDo" == "Info" ]]
then
	GetGlobalInfo
elif [[ "$FuncToDo" == "Queue" ]]
then
	GetQueueInfo
elif [[ "$FuncToDo" == "Start" ]]
then
        MgwStart
elif [[ "$FuncToDo" == "Stop" ]]
then
        MgwStop
elif [[ "$FuncToDo" == "StartForce" ]]
then
        MgwStartForce
elif [[ "$FuncToDo" == "StopForce" ]]
then
        MgwStopForce
elif [[ "$FuncToDo" == "Status" ]]
then
        MgwStatus
else
	usage
fi

VolMin
