#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

VolMin
RunMmDp

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

DbSid=$1
DbSid01=${DbSid}_01
DbSid02=${DbSid}_02
FuncToDo=DUMMY

TimeStamp=$(date +"%H%M%S")
OutPutLog=$OFA_LOG/tmp/DgCheck.Output.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp01=$OFA_LOG/tmp/DgCheck.OutputTmp01.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp02=$OFA_LOG/tmp/DgCheck.OutputTmp02.log.$$.$PPID.$TimeStamp.log
OutPutLogTmp03=$OFA_LOG/tmp/DgCheck.OutputTmp03.log.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/DgAdm.SqlLog.$FuncToDo.$$.$PPID.$TimeStamp.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DgCheck.sh  [SID]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##
## Get status of primary and standby DB's
##
#
__EOF
exit 1
}
#---------------------------------------------

echo "************************************************************************************* Data Guard status. *************************************************************************************" > $OutPutLog
echo "" >> $OutPutLog
#---------------------------------------------
GetInfoPrimary ()
#---------------------------------------------
{
FileName=$1
DatabaseName=$(grep "Database_Name:" $FileName | awk '{print $2}')
echo "###################################################################### Database Role: Primary, Database SID: $DatabaseName ######################################################################" >> $OutPutLog
# echo "Info file: $FileName" >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -e "Ready for Switchover:" -e "Ready for Failover" -e "Database Role" >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -A 3 "Standby Apply-Related Information:"  >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -A 1 "Transport-Related Information:"  >> $OutPutLog
echo "" >> $OutPutLog
GetArchiveInfo $DatabaseName
}
#---------------------------------------------
GetInfoStandby ()
#---------------------------------------------
{ 
FileName=$1
DatabaseName=$(grep "Database_Name:" $FileName | awk '{print $2}')
echo "###################################################################### Database Role: Standby, Database SID: $DatabaseName ######################################################################" >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -e "Ready for Switchover:" -e "Ready for Failover" -e "Database Role" >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -A 3 "Standby Apply-Related Information:"  >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -A 4 "Transport-Related Information:"  >> $OutPutLog
echo "" >> $OutPutLog
cat $FileName | grep -A 11 "Automatic Diagnostic Repository Errors:" >> $OutPutLog
echo "" >> $OutPutLog
GetArchiveInfo $DatabaseName
}
#---------------------------------------------
GetArchiveInfo ()
#---------------------------------------------
{
DbName=$1
echo "Connection to: $DbName" >> $OutPutLog
# echo "Output file: $OutPutLog"
sqlplus -s sys/$MmDp@${DbName} as sysdba<< __EOF >> $OutPutLog
set feedback off;
set echo off;
set linesize 500
set timing off;

col SYNCHRONIZATION_STATUS form a23
col STATUS form a10;
col ERROR form a50;
col DESTINATION form a20;
col DB_UNIQUE_NAME form a15;
col REMOTE_ARCHIVE form a16
col DEST_ID form 9999999 
col TARGET form a10 
col OPEN_MODE form a20
col DATABASE_ROLE form a20
col SWITCHOVER_STATUS form a20
col PROTECTION_MODE form a25
col PRIMARY_DB_UNIQUE_NAME form a25
col ERROR form a30
col DATAGUARD_BROKER form a20
col HOST_NAME form a20
prompt
prompt *** v\$database ***

select
         a.DB_UNIQUE_NAME
	,replace(c.HOST_NAME,'.corp.ubp.ch','') as HOST_NAME
        ,a.OPEN_MODE
        ,a.DATABASE_ROLE
        ,a.PROTECTION_MODE
        ,a.REMOTE_ARCHIVE
        ,a.SWITCHOVER_STATUS
        ,a.DATAGUARD_BROKER
        -- ,a.PRIMARY_DB_UNIQUE_NAME
from v\$database a, v\$instance c ;
prompt
prompt *** v\$archive_dest, v\$archive_dest_status ***

col GAP_STATUS form a20
col PROCESS form a20

select
        a.DEST_ID
        ,a.TARGET
        ,a.DB_UNIQUE_NAME
	-- ,replace(c.HOST_NAME,'.corp.ubp.ch','') as HOST_NAME
        ,a.DESTINATION
        -- ,DATABASE_MODE
        ,b.SYNCHRONIZATION_STATUS
        ,b.GAP_STATUS
        ,a.STATUS
        ,a.ERROR
        -- ,RECOVER_MODE
        ,a.SCHEDULE
        ,a.PROCESS
from
v\$archive_dest a, v\$archive_dest_status b, v\$instance c
where
a.DEST_ID < 3
and a.DEST_ID=b.DEST_ID
;
prompt
__EOF
}
#---------------------------------------------
GetObserverInfo ()
#---------------------------------------------
{
echo "######################################################################### Observer Info for Database SID: $DbSid #########################################################################" >> $OutPutLog
echo "" >> $OutPutLog
DgAdm.sh ShowFastSw $DbSid > $OutPutLogTmp03 2>&1
StatusObs=$(grep "Fast-Start Failover:" $OutPutLogTmp03 | awk '{print $3}')
if [[ $StatusObs == "DISABLED" ]]
then
	grep "Fast-Start Failover:" $OutPutLogTmp03  >> $OutPutLog
else
	cat $OutPutLogTmp03 | grep -v Running >> $OutPutLog
fi

}
#---------------------------------------------
# Main 
#---------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
        FuncToDo                   \
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

VolUp 3

# set -xv 

echo "Please wait ..............."

DgAdm.sh validate $DbSid01 2>/dev/null > $OutPutLogTmp01
echo "Database_Name: $DbSid01" >> $OutPutLogTmp01
DgAdm.sh validate $DbSid02 2>/dev/null > $OutPutLogTmp02
echo "Database_Name: $DbSid02" >> $OutPutLogTmp02

PrimaryDBFile=$(grep "Database Role:" $OutPutLogTmp01 $OutPutLogTmp02 | grep -i primary | awk -F ":" '{print $1}')
StandbyDBFile=$(grep "Database Role:" $OutPutLogTmp01 $OutPutLogTmp02 | grep -i standby | awk -F ":" '{print $1}')

if [[ -z $PrimaryDBFile ]]
then
	echo "###################################################################### Error get Primary info. ######################################################################" >> $OutPutLog
	echo "log files: $OutPutLogTmp01, $OutPutLogTmp02" >> $OutPutLog
else
	GetInfoPrimary $PrimaryDBFile
fi


if [[ -z $StandbyDBFile ]]
then
        echo "###################################################################### Error get Standby info. ######################################################################" >> $OutPutLog
	echo "log files: $OutPutLogTmp01, $OutPutLogTmp02" >> $OutPutLog
else
	GetInfoStandby $StandbyDBFile
fi

GetObserverInfo



echo ""
cat $OutPutLog
echo ""
