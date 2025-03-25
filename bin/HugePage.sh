#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


YesNo $(basename $0) || exit 1 && export RunOneTime=YES


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
## Usage: HugePage.sh  [SID] [FUNCTION]
##
##
## Paremeter:
##
## SID:	
##   Name of the database
##
## FUNCTION:
##   Info	(Show all info)
##   Conf	(Config HUGEPAGEi on the DB)
##   Check      (Check kernel parameter and resources)		
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
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

#---------------------------------------------
GetGlobalInfo ()
#---------------------------------------------
{
sqlplus -s "/as sysdba" << __EOF > $SqlLog
col parameter_name form a30
col value form a30
col sga_component form a30
col DESCRIPTION form a100

set linesize 200
set echo off;
set feedback off;
set timing off;

prompt 
prompt ---------------------------------------------------- Init parameter ($DbSid) ----------------------------------------------------

select 
name as parameter_name, 
display_value as value, 
DESCRIPTION from v\$parameter 
where name in ('sga_target','db_cache_size','shared_pool_size','large_pool_size','java_pool_size','streams_pool_size');


select 
name as parameter_name, 
display_value as value, 
DESCRIPTION from v\$parameter 
where name in ('memory_max_target','pga_aggregate_target','use_large_pages','memory_target');


prompt 
prompt ---------------------------------------------------- Current Allocation ($DbSid) -----------------------------------------------------

select 
component as sga_component, 
parameter as parameter_name,
INITIAL_SIZE/1024/1024 as INITIAL_SIZE_MB,
final_size/1024/1024 as current_allocatio_MB 
from V\$SGA_RESIZE_OPS 
where parameter in ('sga_target','db_cache_size','shared_pool_size','large_pool_size','java_pool_size','streams_pool_size');


__EOF

SqlError=$(grep "ORA-" $SqlLog | head -1)
if [[ ! -z $SqlError ]]
then
        LogError "Error getting Info $SqlError"
	LogError "Logfile: $SqlLog"
#        exit 1
fi

cat $SqlLog
echo ""
echo "---------------------------------------------------- Kernal parameter ($(hostname | head -1)) ----------------------------------------------------"

grep Huge /proc/meminfo | grep -v Anon

echo ""
echo "---------------------------------------------------- grub parameter ($(hostname | head -1)) ----------------------------------------------------"
Grub=$(grep "transparent_hugepage=never" /etc/default/grub)
if [[ -z $Grub ]]
then
	echo "Disableing of transparent_hugepage is NOT done in /etc/default/grub"
else
	echo $Grub
fi
echo ""
echo "---------------------------------------------------- Server Info ($(hostname | head -1)) ----------------------------------------------------"
MemSizeGb=$(free -g | grep Mem | awk '{print $2}')
echo "Memory size: $MemSizeGb GB"
echo ""
echo "---------------------------------------------------- Monitoring ($(hostname | head -1)) ----------------------------------------------------"

echo "Monitor AnonHugePages should always be 0 or less than 1% of total memory."

grep  AnonHugePages  /proc/meminfo

echo ""
echo "All should be zero:"
egrep 'trans|thp' /proc/vmstat
echo ""

}
#---------------------------------------------
YesNo ()
#---------------------------------------------
{
while true;
do
    LogCons "Continue [Yes/No]? : "
    read response
    if [[ $response = Yes ]]
    then
        LogCons "You chose: $response"
        return 0
    elif [[ $response = No ]]
    then
        LogCons "You chose: $response"
	exit 1
    else
	LogError "wrong input...."
    fi
done
}
#---------------------------------------------
ConfDbHugepage ()
#---------------------------------------------
{
LogCons "Config DB: $DbSid with HUGEPAGE"

# UnixConfCheck

SgaSize=$(DoSqlQ "SELECT round(sum(value)/1024,0) as TOTAL_SGA_KB FROM v\$sga;")
PgaSize=$(DoSqlQ "SELECT round((round(sum(value)/1024,0)/100)*15,0) as TOTAL_SGA_KB FROM v\$sga;")
# LogCons "Database will be restarted....."
# YesNo

LogCons "Changing init parameters "
sqlplus -s "/as sysdba" << __EOF > $SqlLog 
set echo off;
set feedback off;
set timing off;

alter system reset MEMORY_TARGET scope=spfile;
alter system reset MEMORY_MAX_TARGET scope=spfile;
alter system reset PGA_AGGREGATE_TARGET scope=spfile;
__EOF

SqlError=$(grep "ORA-" $SqlLog | grep -v "ORA-32010" | head -1)
if [[ ! -z $SqlError ]]
then
        LogError "Error setting parameters $SqlError"
        LogError "Logfile: $SqlLog"
        exit 1
fi


sqlplus -s "/as sysdba" << __EOF > $SqlLog
alter system set pga_aggregate_target=${PgaSize}K scope=spfile;
alter system set sga_target=${SgaSize}K scope=spfile;
alter system set use_large_pages=ONLY scope=spfile;
__EOF

SqlError=$(grep "ORA-" $SqlLog | head -1)
if [[ ! -z $SqlError ]]
then
        LogError "Error setting parameters $SqlError"
        LogError "Logfile: $SqlLog"
        exit 1
fi

# $OFA_BIN/DbStartStop.sh stop $DbSid
# $OFA_BIN/DbStartStop.sh start $DbSid

LogCons "After config need to restart the DB, be sure the UNIX kernel is config before restart !!!!!"

}
#---------------------------------------------
UnixConfCheck ()
#---------------------------------------------
{
LogCons "Checking resources on the server: ($(hostname | head -1))"
Error=0
MemSize=$(free -k | grep Mem | awk '{print $2}')
MemLockH=$(ulimit -l -H)
MemLockS=$(ulimit -l -S)
TotHugePage=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
FreeHugePage=$(grep HugePages_Free /proc/meminfo | awk '{print $2}')
PageSizeHugePage=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')

if [[ TotHugePage -eq 0 ]]
then
	LogError "HUGEPAGE is NOT configured on the server"
	Error=1
fi 

# check ulimit
MemSize90=$(($MemSize/100*89))
if [[ $MemLockH -lt $MemSize90 ]] || [[ $MemLockH -lt $MemSize90 ]] 
then
	LogError "ulimli -l -H or ulimit -l -S are small than 90% of the total memory ($MemSize90) (ulimli -l -H: $MemLockH, ulimit -l -S: $MemLockS)"
	Error=1
else 
	LogCons "memlock soft/hard (ulimit -l) ok!, min 90% of total memory"
fi

# Check Free pages
SgaSize=$(DoSqlQ "SELECT round(sum(value)/1024,0) as TOTAL_SGA_KB FROM v\$sga;")
# PgaSize=$(DoSqlQ "SELECT round((round(sum(value)/1024,0)/100)*15,0) as TOTAL_SGA_KB FROM v\$sga;")
HugePageNeeded=$((($SgaSize/$PageSizeHugePage)/100*105))

LogCons "SGA Size: $SgaSize KB"
# LogCons "PGA Size: $PgaSize KB"
LogCons "HugePageNeeded: $HugePageNeeded"


if [[ $FreeHugePage -lt $HugePageNeeded ]]
then
	LogError "NOT free HUGEPAGE enough... (Free: $FreeHugePage, Needed: $HugePageNeeded)"
	Error=1
else
	LogCons "Free HUGEPAGE ok! (Free: $FreeHugePage, Needed: $HugePageNeeded)"
fi 

if [[ $Error -gt 0 ]]
then
	LogError "Error in the HUGEPAGE configuration for DB: $DbSid "
	exit 1
fi


}
#---------------------------------------------
# Main
#---------------------------------------------

MemSize=$(free -k | grep Mem | awk '{print $2}')
MemLockH=$(ulimit -l -H)
MemLockS=$(ulimit -l -S)
TotHugePage=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
FreeHugePage=$(grep HugePages_Free /proc/meminfo | awk '{print $2}')
PageSizeHugePage=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')

if [[ "$FuncToDo" == "Info" ]]
then
	GetGlobalInfo
elif [[ "$FuncToDo" == "Conf" ]]
then
	ConfDbHugepage
elif [[ "$FuncToDo" == "Check" ]]
then
        UnixConfCheck
else
	usage
fi

