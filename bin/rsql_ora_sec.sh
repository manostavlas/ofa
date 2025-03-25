#!/bin/ksh
#                                                     
## Name: rsql_ora_sec.sh
##                                                    
## In:  sql script
## Out: n.a.
## Ret: 0/1
##                                                    
## Synopsis: run script against one or several targets (SECURS ZONE reading).
##           READIND the conection string from GRID server. ($OFA_GRID_SEC_DB)
##                                                    
## Usage: rsql_ora_sec.sh <script (in_line or file))> [<filter>]
## 
## Parameter:
##	filter are the where clause for the GRID DB group.
##	e.g. 
##	  "=PRD_DB" or "like 'EV%'" or "not like 'PRD%" or "in ('PRD_DB','PRD_DB_PIQUET')"                                                    
##
## Description:                                       
##                                                    
##  - Runs sql script or command supplied in arg1 against DBs in defined in the GRID DB, filtered by <filter>
##  - Takes default oracle environment (often last in oratab) unless ORACLE_SID is exported. 
## 
## Note:
##    Interactive only
##    
## Workings:                                          
##                                                    
##  - Uses DoSqlLoggedVerbose
##  - TWO_TASK to appended to connection string.
##    I.e. this script always uses SQL*Net, even locally.
##   
#  ------------------------------------------------------------------------------                                                   
# set -xv
UserId=$(id -u)
OraDbTestCnxOutputTmpFile=/tmp/OraDbTestCnxOutput_${UserId}.log
ZoneIn=$1
ConnInfo=/tmp/ConnInfo.lst
ConnInfoErr=/tmp/ConnInfo.err
#--------------------------------------------------------------------
function OraDbTestCnxOutput 
#--------------------------------------------------------------------
  #
  # Name: OraDbTestCnx
  #
  # In:  n.a.
  # Out: n.a.
  # Ret: 0/1
  #
  # Synopsis: attempts a connection with select at an instance.
  #
  # Usage: OraDbTestCnx
  #
  # Description:
  #
  #   - Disables any login.sql path by pointing to a path that does nothing.
  #   - runs "sqlplus -S" against the current instance
  #     - Sets WHENEVER SQLERROR EXIT FAILURE pragma.
  #     - Performs a "select 1 from dual".
  #     - Returns return code from sqlplus session.
  #

{
    typeset _SQLPATH=$SQLPATH
    typeset SQLPATH=$OFA_SQL/ofa/login/nothing
    sqlplus -S $OFA_DBCNX_STRING  << EOF > $OraDbTestCnxOutputTmpFile 2>&1
       WHENEVER SQLERROR EXIT FAILURE
       SELECT 1 FROM DUAL;
EOF
    typeset _RV=$?
    SQLPATH=$_SQLPATH
 	ErrorTextSql=$(grep -e ORA- -e SP $OraDbTestCnxOutputTmpFile | head -1 )
	if [ ! -z $ErrorTextSql ] ; then
		echo "Error:  ${ErrorTextSql} Connecting to : $InIts@$sid"
	fi 
    return $_RV
}
#--------------------------------------------------------------------
function help_cmd
#--------------------------------------------------------------------
{
         VolSet 1
         echo '
             ## -- ============================
             ## -- Interactive Controls Summary
             ## -- ============================
             ## ""    - (nothing) => default command
             ## "Y"   - Proceed with task
             ## "Q"   - Abort
             ## "L"   - List Records
             ## ">"   - Skip task, prompts at next [SsNn]
             ## "<"   - Previous task, prompts again
             ## "#"   - Jump to Task (# being a task number)
             ## "!"   - Force through nonstop
             ## "?" - Help
             ##
         ' | CartRidge
         VolPrv
    }
#--------------------------------------------------------------------
    function GoNoGo
#--------------------------------------------------------------------
{
      #
      # recursive loop
      #
        Prompt GO "run \"$_TO_RUN\" against $InIts@$sid ? [$CONT_DFLT] => "
        if [[ "$GO" = "?" ]]
        then
            help_cmd
            GoNoGo
        elif [[ "$GO" = "!" ]]
        then
            FORCE=1
            GO="Y"
            LogIt "Switch to FORCE THROUGH NON-STOP"
        elif [[ "$GO" != [\<\>0123456789YyNniSsQqLl]* ]] 
        then
            LogCons "Unknown Action : \"$GO\""
            GoNoGo
        fi
        echo "" 1>&2
    }
#--------------------------------------------------------------------
    function GenTnsNames
#--------------------------------------------------------------------
{
# set -xv
LogCons "Running BuildTnsNames.sql connecting to $OFA_GRID_SEC_DB."
sqlplus -S $GrinConn@$OFA_GRID_SEC_DB << __EOF > $ConnInfoErr 2>&1
set feedback off;
spool /tmp/tnsnames.ora
@$OFA_SQL/BuildTnsNames.sql
spool off
__EOF

OraError=$(grep -e "ORA-" -e "SP2-" $ConnInfoErr)

if [[ ! -z "$OraError" ]]
then
        LogError "Error generate TNSNAMES Log: $ConnInfoErr"
        exit 1
fi
cat $OFA_TNS_ADMIN/sqlnet.ora > /tmp/sqlnet.ora
# set +xv
}
#--------------------------------------------------------------------
    function GetConnString
#--------------------------------------------------------------------
{
set -vx
-- unset TNS_ADMIN
-- Ldaping $OFA_GRID_SEC_DB

echo "GridConnectString: $GridConnectString"

sqlplus -S $GrinConn@$OFA_GRID_SEC_DB << __EOF > $ConnInfoErr 2>&1
set heading off;
set feedback off;
set echo off;
set timing off;
set linesize 1000;
set trimspool on;
set trimout on;
set pagesize 1000;
set trim on;
spool $ConnInfo
/*
  select 
    t.host_name as    "Server Src"
   , port.property_value "Port Src"
   , SID.property_value "DB"
    -- , decode ( t.type_qualifier4 , ' ' , 'Normal' , t.type_qualifier4 ) as     type
    -- , dbv.property_value as     version
    --, ip.property_value IP
    -- , logmode.property_value as     "Log Mode"
    --, oh.property_value as     "Oracle Home"
from mgmt\$target t
    , ( select 
        p.target_guid
    , p.property_value
        from mgmt\$target_properties p
    where p.property_name = 'DBVersion' ) dbv
        , ( select p.target_guid
        , p.property_value
        from mgmt\$target_properties p
        where p.property_name = 'Port' ) port
        , ( select p.target_guid
        , p.property_value
        from mgmt\$target_properties p
        where p.property_name = 'SID' ) sid
        , ( select p.target_guid
        , p.property_value
        from mgmt\$target_properties p
        where p.property_name = 'log_archive_mode' ) logmode
        , ( select p.target_guid
        , p.property_value
        from mgmt\$target_properties p
        where p.property_name = 'OracleHome' ) oh
        , ( select tp.target_name
        as     host_name
        , tp.property_value
        from mgmt\$target_properties tp
        where tp.target_type = 'host'
        and tp.property_name = 'IP_address' ) ip
        where t.target_guid = port.target_guid
        and port.target_guid = sid.target_guid
        and sid.target_guid = dbv.target_guid
        and dbv.target_guid = logmode.target_guid
        and logmode.target_guid = oh.target_guid
        and t.host_name = ip.host_name
        and SID.property_value='$sid'
-- order by 1, 3
;
*/
select
-- a.target_GUID,
listagg(prop.PROPERTY_VALUE,' ') within group (order by prop.PROPERTY_VALUE) as LIST_INFO FROM
mgmt_target_properties prop,
mgmt_targets tgt,
(select distinct target_GUID,PROPERTY_VALUE from mgmt_target_properties 
where PROPERTY_VALUE='$sid'
) a
WHERE 
--  a.PROPERTY_VALUE=prop.PROPERTY_VALUE
a.target_GUID=prop.target_GUID
AND tgt.target_guid = prop.target_guid
AND prop.property_name IN ('MachineName','Port','SID')
group by a.target_GUID
;      

spool off
__EOF

OraError=$(grep -e "ORA-" -e "SP2-" $ConnInfoErr)

if [[ ! -z "$OraError" ]]
then
        LogError "Error getting the Connection info from the GRID. Log: $ConnInfoErr"
        exit 1
fi

HostPort=$(cat $ConnInfo)

Host=$(echo $HostPort | awk '{print $3}')
Port=$(echo $HostPort | awk '{print $1}')

# ConnString="\"(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = $Host)(PORT = $Port)) (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = $sid)))\""
ConnStringTns="(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = $Host)(PORT = $Port)) (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = $sid)))"

echo "${sid} = ${ConnStringTns}" > /tmp/tnsnames.ora
cat $OFA_TNS_ADMIN/sqlnet.ora > /tmp/sqlnet.ora

LogCons "Connect String for $sid: ${ConnStringTns}"

set +xv

}
#--------------------------------------------------------------------
# Main
#--------------------------------------------------------------------
  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22
  #
  # Check Oracle Environment
  #
    ! OraEnv && LogError "Need Oracle Environment"

  #
  # Check Interactive
  #
    # asg ! IsInterActive && "BailOut -- interactive only"

  #
  # syntax
  #
    [[ $# -lt 1 ]] && Usage "args, pls."

if [[ -z "$InIts" ]]
then
echo "Enter User name and Password for the Remote connections................ " | LogCartRidge
        LogCons "Please, Enter the user name !!!!!"
          printf "
Username:      => "
	read InIts
fi


if [[ -z "$MmDp" ]]
then
	LogCons "Please, Enter the password for the user: $InIts !!!!!"
          printf "
Password:      => "
	stty -echo
	read MmDp
	stty echo
	echo ""
fi 


  #
  # input file
  #
    typeset _TO_RUN="$1"
    VolSet 1
    if [[ ! -r "$_TO_RUN" ]] && [[ "$_TO_RUN" != *" "* ]]
    then
        Usage "first arg. must be sql input (file or inline)"
    else
        if [[ -r "$_TO_RUN" ]] 
        then
            ls -l "$_TO_RUN" | LogCartRidge
        else
            echo "$_TO_RUN" | LogCartRidge
        fi
        shift 1
    fi
    VolPrv
    Prompt GO "Correct Input ? [Y] => "
    [[ "$GO" != [Yy]* ]] && ExitGently "Canceled by $USER"

  #
  # connection string
  #
    OFA_DBCNX_STRING=$InIts/$MmDp


# Zone query
if [[ ! -z "$1" ]] 
then
	ZoneQuery="b.group_name $1 and"
fi

# Exclude query ($EXCLUDE_DB defined in ../etc/rsql_ora)
if [[ ! -z "$EXCLUDE_DB" ]]
then
        ExcludeDb="a.target_name not in ($EXCLUDE_DB) and"
fi






if [[ "$InIts" != "system" ]]
then

        LogCons "Please, Enter the password for DB: $OFA_GRID_SEC_DB User: system !!!!!"
          printf "
Password:      => "
        stty -echo
        read GridPw
        stty echo
        echo ""
	GrinConn="system/$GridPw"
echo $GrinConn
else
	GrinConn=$OFA_DBCNX_STRING
fi


#
# Check connection to GRID
#



CheckGrid=$(tnsping $OFA_GRID_SEC_DB | grep TNS-)


if [[ ! -z "$CheckGrid" ]]
then
	LogError "Can't connect to GRID database."
	LogError "ERROR: $CheckGrid"
	exit 1
else 
	LogCons "Tnsping to $OFA_GRID_SEC_DB ok!"
fi 


#
# Create database list.
#

export DatabaseList=/tmp/DbList.log
> $DatabaseList

sqlplus -s  $GrinConn@$OFA_GRID_SEC_DB << __EOF > /tmp/DatabaseList.err 2>&1
spool $DatabaseList
set heading off
set feedback off
set echo off;
set timing off;
set linesize 1000;
-- set serveroutput on;
set trimspool on;
set trimout on;
set pagesize 1000;
set trim on;
col t_name form a15;
col g_name form a45;

prompt # Record format: sid : zone 

select 
  concat(a.target_name,' : ') t_name,  
  replace(b.group_name, chr(32), '') g_name 
from 
MGMT\$TARGET a, 
MGMT\$GROUP_MEMBERS b, 
(select distinct regexp_substr(target_name, '[^_]*') target_name from MGMT\$TARGET) c
where 
$ZoneQuery
$ExcludeDb
a.target_type in ('oracle_database','rac_database') and
a.target_guid=b.target_guid and
a.target_name=c.target_name and
a.target_name not in (select distinct target_name from MGMT\$BLACKOUT_HISTORY a,MGMT\$BLACKOUTS b  
where
a.target_type in ('oracle_database','rac_database') and
a.blackout_guid=b.blackout_guid and
b.status='Started') and 
group_type = 'composite'
order by 2,1;
spool off
__EOF

OraError=$(grep "ORA-" /tmp/DatabaseList.err)


# set -xv

if [[ ! -z "$OraError" ]]
then
	LogError "Error connecting to GRID DB: $OFA_GRID_SEC_DB, Log file:/tmp/DatabaseList.err"
	exit 1	
fi


 
  # 
  # initialize iterator "BOB"
  #
#    ! IterInit BOB  $DatabaseList $@ \
    ! IterInit BOB  $DatabaseList  \
        && ExitGently "Not targets found (args \"$@\")" \
    ;

    Prompt GO "Good to GO ? [Y] => "
    [[ "$GO" != [Yy] ]] && VolSet 1 && ExitGently "Canceled by $USER"


    echo "Start Work" | LogCartRidge

GenTnsNames

export TNS_ADMIN=/tmp

#     RECORD_FORMAT=" sid version startup_flag user host env zone created creator active application comments"
    RECORD_FORMAT=" sid zone"
    typeset CARRION=1 
    typeset FORCE=0 
    while IterFetch BOB
    do
        [[ ! -n "$sid" ]] && LogError "No SID -- skip on" && IterNext && continue
        OFFSET=$(LogLineCount)   
        [[ $CARRION -eq 1 ]] && CONT_DFLT="Y" || CONT_DFLT="?"
        [[ $FORCE -ne 1 ]] && GoNoGo || GO="Y"
        if [[ "$GO" = [SsNn\>] ]] 
        then
            echo "" 1>&2
            LogWarning "(skip $sid)" 
            IterNext BOB
            CARRION=1
            continue
        elif [[ "$GO" = [Ll] ]]
        then
            echo "" 1>&2
            LogInfo "List Records"
            IterList BOB
            continue
        elif IsInteger $GO
        then
            echo "" 1>&2
            LogWarning "Jump to step $GO"
            IterJump BOB $GO
            CARRION=1
            continue
        elif [[ "$GO" = "<" ]]
        then
            echo "" 1>&2
            LogInfo "Go back one step"
            IterBack BOB
        elif [[ "$GO" = [Qq] ]] 
        then
            echo "" 1>&2
            ExitGently "User Abort"
        elif [[ "$GO" = [Yy] ]] 
        then

# GetConnString

            TWO_TASK="$sid"
            OFA_DBCNX_STRING="$InIts/$MmDp@$sid"

	if [[ "$InIts" == "sys" ]] || [[ "$InIts" == "SYS" ]]
	then
		OFA_DBCNX_STRING="$InIts/$MmDp@$sid as sysdba" 
	fi


# asg       if  OraDbTestCnx 
	    if OraDbTestCnxOutput
            then
                DoSqlLoggedVerbose "$_TO_RUN"
                echo "" 1>&2
                LogCons "\"$_TO_RUN\" @ $sid - checking log ...)"
                VolSet 1
                if Probe4Error $OFFSET 
                then
                    LogError "Target \"$sid\" failed" 2>&1 | CartRidge
                    CARRION=0
                else
                    LogInfo  "Target \"$sid\" succeeded" 2>&1 | CartRidge
                    CARRION=1 
                fi
                VolPrv
            else
                echo "" 1>&2
                LogError "Check connection $InIts@$sid failed - skipping on !"
		LogError "Error message: ${ErrorTextSql}"
                CARRION=1
            fi
            IterNext BOB
        else
            ExitGently "Unknown Action: \"$GO\""
        fi
    done
