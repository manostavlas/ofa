#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"



DbSid=$1

TimeStamp=$(date +"%H%M%S")
OutPutLog=$OFA_LOG/tmp/ResetMgw.Output.log.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/ResetMgw.SqlLog.$$.$PPID.$TimeStamp.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ResetMgw.sh  [SID]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##
## Resetting connect MQ connect string..... 
##
#
__EOF
exit 1
}
#---------------------------------------------
ForceShutDownMGW ()
#---------------------------------------------
{
LogCons "Force Shutdown MGW"
LogCons "Sql log file: $SqlLog"
echo "Force Shutdown MGW" >> $SqlLog
sleep 120
sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET echo off;
SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set timing off;
select agent_status,agent_ping from mgw_gateway;
exec DBMS_MGWADM.CLEANUP_GATEWAY(DBMS_MGWADM.CLEAN_STARTUP_STATE);
___EOF

sed -i 's/ORA/ora/g' $SqlLog


ResetSettings

}
#---------------------------------------------
ResetSettings ()
#---------------------------------------------
{
LogCons "Resetting MGW config..."
LogCons "Sql log file: $SqlLog"
sleep 60
sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLog 2>&1
SET echo off;
SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set timing off;

DECLARE
   v_obj_name varchar(64);
   v_agent_status varchar(64);
   v_sql_str varchar(256);
   v_status_str varchar(256);
   v_shutdown varchar(64) := 'BEGIN DBMS_MGWADM.SHUTDOWN; END;';
   v_reconfig_str varchar(512);
   v_host varchar(64);
   v_port varchar(64);
   v_linkname varchar(64);
   v_channel varchar(64);
   v_mgw_linkname varchar(64);
  v_options sys.mgw_properties;
  v_prop sys.mgw_mqseries_properties;


BEGIN
select object_name into v_obj_name from dba_objects where object_name = upper('MGW_GATEWAY') and rownum =1;
        IF v_obj_name = 'MGW_GATEWAY' THEN
                DBMS_OUTPUT.put_line ('MGW are installed....');
                v_sql_str := 'select agent_status from MGW_GATEWAY';
                EXECUTE IMMEDIATE v_sql_str into v_agent_status;
                IF v_agent_status != 'NOT_STARTED' THEN
                	DBMS_LOCK.SLEEP(60);
                        EXECUTE IMMEDIATE v_shutdown;
                        DBMS_OUTPUT.put_line ('Stopping MGW ');
                        DBMS_OUTPUT.put_line ('Status MGW: '|| v_agent_status);
                END IF;
-- START Reconfig MGW
                        for xx in (select LINK_NAME as v_mgw_linkname from MGW_MQSERIES_LINKS)
                        LOOP
                                v_prop := sys.mgw_mqseries_properties.alter_construct();
                                v_prop.hostname := 'DUMMY';
                                v_prop.channel  := 9991;
                                v_prop.port  := 9991;
                                v_reconfig_str  := 'BEGIN DBMS_MGWADM.ALTER_MSGSYSTEM_LINK(linkname => xx.v_mgw_linkname, properties => v_prop); END;';
                                DBMS_MGWADM.ALTER_MSGSYSTEM_LINK(linkname => xx.v_mgw_linkname, properties => v_prop);
                                -- EXECUTE IMMEDIATE v_reconfig_str;
                                v_status_str := 'select LINK_NAME,HOSTNAME,PORT,CHANNEL from MGW_MQSERIES_LINKS order by 1';
                                EXECUTE IMMEDIATE v_status_str into v_linkname,v_host,v_port,v_channel;
                                DBMS_OUTPUT.put_line ('Link name: '||v_linkname||' Host: '||v_host||' Port: '|| v_port||' Channel: '|| v_channel);
                        END LOOP;
-- END reconfig MGW
                DBMS_LOCK.SLEEP(10);
                EXECUTE IMMEDIATE v_sql_str into v_agent_status;
                DBMS_OUTPUT.put_line ('Status MGW: '|| v_agent_status);
        END IF;
 exception
        when no_data_found then
         DBMS_OUTPUT.put_line (chr(10)|| 'MGW NOT installed...... '|| chr(10));
END;
/
___EOF


ErrorCode=$(grep "ORA-" $SqlLog)


if [[ ! -z $ErrorCode ]]
then
	if [[ $Retry -ne 1 ]]
	then
		LogCons "Issue resetting MGW. Logfile: $SqlLog"
        	LogCons "Retry with force shutdown"
		>$SqlLog
		Retry=1
		ForceShutDownMGW
	else
		LogError "Error by resetting MGW, after one retry (shutdow force)"
		exit 1
	fi
fi

# cat $SqlLog | LogStdInEcho 
}

#---------------------------------------------
# Main 
#---------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbSid >/dev/null 2>&1
        ExitCode=$?
        if [[ $ExitCode -ne 0 ]]
        then
                VolUp 3
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

MgwInstalled=$(DoSqlQ "select object_name from dba_objects where object_name = upper('MGW_GATEWAY') and rownum =1;" | grep MGW_GATEWAY)

if [[ -z $MgwInstalled ]]
then
	LogCons "MGW NOT installed"
else 
	LogCons "MGW installed."
	ResetSettings
fi
