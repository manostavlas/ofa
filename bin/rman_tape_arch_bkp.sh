#!/bin/ksh -p 
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: rman_tape_arch_bkp.sh [SID]  <PARAMATERS>
##
## Paramaters:
## SID:         SID of the database to backup
##
## FUNCTION:
##
##
##              PARAMATERS:
##                     RETENTION: Backup retention  [eg: DAYS03 - DAYS21 - WEEK05 - MONT12 - YEAR10 ]
##
##                     TAG=(TAG NAME) The backup tag name(limit 11 characteres) e.g TAG=BNRNOV2024.
##
##                     CHANNELS=(NUMBER_OF CHANNELS) set the number of channels to use diffrent from default.
##
##                     SECTION_SIZE=(SIZE_OF_SECTION) Backup will use section size during backup, eg SIZE_OF_SECTION=40 .
##
##
##
#

  #
  # must be sysdba
  #
    ImaSysDba || BailOut "Backup of $ORACLE_SID requires sysdba"

  #
  # check that no other rman task is running on the same target from ofa
  #

    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  #
  # Set Var
  #

Database=$1
Function=$2

TimeStamp=$(date +"%H%M%S")
ExitCode=0
ControlFileLabel=CT
SpfileLabel=SP
ArchLabel=AR

RmanConfFile=$OFA_ETC/rman_tape_arch_bkp/rman_tape_arch_bkp.defaults
TmpLogFile=$OFA_LOG/tmp/rman_tape_arch_bkp.tmp.$$.$PPID.$TimeStamp.log
CheckConnRepoLogFile=$OFA_LOG/tmp/rman_tape_arch_bkp.CheckConnRepo.$$.$PPID.$TimeStamp.log
ChannelStart=$OFA_LOG/tmp/rman_tape_arch_bkp.ChannelStart.$$.$PPID.$TimeStamp.txt
ChannelStop=$OFA_LOG/tmp/rman_tape_arch_bkp.ChannelStop.$$.$PPID.$TimeStamp.txt
RmanExecFileCONT=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecFileCONT.$$.$PPID.$TimeStamp.rman
RmanExecFileValidate=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecFileValidate.$$.$PPID.$TimeStamp.rman
RmanExecFileObsolete=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecFileObsolete.$$.$PPID.$TimeStamp.rman
RmanExecFileArch=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecFileArch.$$.$PPID.$TimeStamp.rman
RmanExecFileList=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecFileList.$$.$PPID.$TimeStamp.rman
RmanExecCrossArch=$OFA_LOG/tmp/rman_tape_arch_bkp.RmanExecCrossArch.$$.$PPID.$TimeStamp.rman
TnsPingLog=$OFA_LOG/tmp/rman_tape_arch_bkp.TnsPingLog.$$.$PPID.$TimeStamp.log

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$TAPE_LIBRARY_PATH
RetentionPolicy="CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 356 DAYS;"

  #
  # Check var
  #
  LogCons "Checking variables."
  CheckVar                              \
        Database                        \
  && LogCons "Variables OK!"    \
  || Usage

#---------------------------------------------------------
CheckNBKSymlink ()
#---------------------------------------------------------
{

LogCons "Checking if the Oracle library symbolic link exist ... "

if [[ ! -L "$ORA_NBK_LIB_SYMLINK" ]]; then
    LogCons "The oracle library Symbolic link does not exist. Creating it..."
    ln -s "$CH_SBT_LIBRARY" "$ORA_NBK_LIB_SYMLINK"
    LogCons "Symbolic link created: $ORA_NBK_LIB_SYMLINK -> $CH_SBT_LIBRARY"
else
    LogCons "Symbolic link already exists: $ORA_NBK_LIB_SYMLINK"
fi

}
#---------------------------------------------------------
SetTag ()
#---------------------------------------------------------
{

KeepPeriode=$(eval "echo \$$1")

TAG=$(echo $AllParameters | awk -F'TAG=' '{print $2}' | awk '{print $1}')

if [[ -z "$TAG" ]]
then
        MAIN_TAG=$(echo ${BACKUP_RETENTION}_${MAIN_TAG} | sed 's/..$//')
        FINAL_TAG=${ORACLE_SID}_${ArchLabel}_${MAIN_TAG}
        SPF_TAG=${ORACLE_SID}_${SpfileLabel}_${MAIN_TAG}
        CTL_TAG=${ORACLE_SID}_${ControlFileLabel}_${MAIN_TAG}
        LogCons "Backup TAG not provided on the parameter, the default backup will be used  : $FINAL_TAG !!!"
else
        FINAL_TAG=$TAG
        SPF_TAG=${SpfileLabel}_${FINAL_TAG}
        CTL_TAG=${ControlFileLabel}_${FINAL_TAG}
        LogCons  "Backup TAG: $FINAL_TAG will be used !!!"

fi

CheckDate=$(DoSqlQ "select $KeepPeriode from dual;" | grep ORA-)

if [[ ! -z "$CheckDate" ]]
then
        LogError "Wrong date format in TAG: $BACKUP_RETENTION Expire Periode: $KeepPeriode"
        LogError "Error: $CheckDate"
        exit 1
else
        ExpDate=$(DoSqlQ "select $KeepPeriode from dual;")
        ExpDateDays=$(DoSqlQ "select replace(round(abs(sysdate-$KeepPeriode)), chr(32), '') from dual;")
        LogCons "Backup RMAN: expire date: $ExpDate, in days: $ExpDateDays"
fi

LogCons "Using Backup TAG: $FINAL_TAG Expire Periode: $KeepPeriode"
}
#---------------------------------------------------------
IdentifyServer ()
#---------------------------------------------------------
{

LogCons "Identify in which zone (Common/Secure) the Server ($HOSTNAME) are placed."

if [ "$OSNAME" = "Linux" ] ; then
        NetWorkPing=$(ping -c 1 $HOSTNAME | grep "bytes from" | awk '{print $5}' | awk -F "." '{print $1,$2,$3,$4}' | sed s/[\(\):]//g | tr ' ' '.')
        LogCons "OS system: $OSNAME"
elif [ "$OSNAME" = "SunOS" ] ; then
        NetWorkPing=$(/sbin/ping -s $HOSTNAME 64 1 | grep "bytes from" | awk '{print $5}' | awk -F "." '{print $1,$2,$3,$4}' | sed s/[\(\):]//g | tr ' ' '.')
        LogCons "OS system: $OSNAME"
elif [ "$OSNAME" = "AIX" ] ; then
        NetWorkPing=$(ping -c 1 $HOSTNAME | grep "bytes from" | awk '{print $4}' | awk -F "." '{print $1,$2,$3,$4}' | sed s/[\(\):]//g | tr ' ' '.')
        LogCons "OS system: $OSNAME"
fi

for i in $CommonNetAddress
do

        NetAdd=$(echo ${NetWorkPing} | grep -w ^${i})
        if [[ ! -z "$NetAdd" ]]
        then
                TAPE_path_zone=$COMM_TAPE_path
                LogCons "Server in Common zone, Server ip: $NetWorkPing"
                 NB_ORA_POLICY="prd_com_db_ora"
                break
        fi
done

if [[ -z "$TAPE_path_zone" ]]
then
        TAPE_path_zone=$SECU_TAPE_path
        LogCons "Server in Secure zone, Server ip: $NetWorkPing"
        NB_ORA_POLICY="prd_sec_db_ora"
fi

}
#---------------------------------------------------------
GetMediaServer ()
#---------------------------------------------------------
{
LogCons "Getting the Media server name... "
ServerLocation=$(echo "${HOSTNAME}" | cut -c4-6 )


IFS=' '
# Loop through the items in the list
for item in $NB_MEDIA_SERV_LIST; do
    # Compare each item with the comparison variable
        var=$(echo "$item" | cut -c4-6 )
    if [[ "$var" == "$ServerLocation" ]]; then
            LogCons "The Media server will be $item."
        NB_ORA_SERV="$item"
    fi
done

}
#---------------------------------------------------------
DBTypeEvProd ()
#---------------------------------------------------------
{
LogCons "Identify in which DB type (evx/Prod) of the Database ($ORACLE_SID)."
DBType=$(echo $ORACLE_SID | grep -i PRD)
if [ ! -z "$DBType" ] ; then
        DBType=$PRD_TAPE
else
        DBType=$EVX_TAPE
fi
LogCons "Database: $ORACLE_SID Type: $DBType"
}


#---------------------------------------------------------
GetBackupProperties()
#---------------------------------------------------------
{

BACKUP_RETENTION=$1

if [[ " $NBK_RETENTION " == *"$BACKUP_RETENTION"* ]]; then
      LogCons "Backup Retention OK !"

elif  [[ -z $BACKUP_RETENTION  ]]; then
      LogError "Please provide a backup retention on the list  $NBK_RETENTION"
      exit 1;
else
      LogError "The $BACKUP_RETENTION does't exist on the list ! illegal option"
      LogError "The backup retention should be  $NBK_RETENTION"
      exit 1;
fi



if  [[ $BACKUP_RETENTION  == "DAYS21"  ]]; then
              NB_ORA_SCHED="daily"

elif [[ $BACKUP_RETENTION == "DAYS03" ]] ; then
              NB_ORA_SCHED="daily3"

else
        LogCons "The $BACKUP_RETENTION is incorrect for archive backup !"
        LogCons "Please put the right backup retention."
        exit 1;
fi

         LogCons "The Netbackup schedule will be $NB_ORA_SCHED."

}
#------------------------------------------------
SetRMAN_REPO ()
#------------------------------------------------
{
# set -xv
LogCons "Start SetRMAN_REPO"

for i in $RMAN_NAME_REPO
do
        tnsping $i > $TnsPingLog 2>&1
        ErrorMess=$(grep "TNS-" $TnsPingLog)
        if [[ -z "$ErrorMess" ]]
        then
                LogCons "Connecting to RMAN repo: $i"
                RMAN_REPO=$i
                break
        fi
done


if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error tnsping: $i"
        LogError "Error: $ErrorMess"
        LogError "Log file: $TnsPingLog"
        exit 1
fi
# set +vx
}
#---------------------------------------------------------
CheckConnRepo ()
#---------------------------------------------------------
{
SetRMAN_REPO

LogCons "Checking connection to RMAN repository and resync catalog. (${RMAN_NAME_REPO})"
LogCons "Log file: $CheckConnRepoLogFile"

rman $TARG_CAT_CONN_STRING << ___EOF > $CheckConnRepoLogFile 2>&1
RESYNC CATALOG;
exit
___EOF

if [[ $? -ne 0 ]]
then
        OFA_CONS_VOL_OLD=$OFA_CONS_VOL
        export OFA_CONS_VOL=1

        LogWarning "Error connecting to RMAN repository $RMAN_CONN_USER/<password>@${RMAN_NAME_REPO}"

        LogWarning "Log file: $CheckConnRepoLogFile"
        LogWarning "Using control file instead of RMAN repository !!!!"
        ConnectString="TARGET /"
        LogCons "Connect command: rman $ConnectString"

        OFA_CONS_VOL=$OFA_CONS_VOL_OLD
        export OFA_CONS_VOL
        ExitCode=50
else
        LogCons "Check RMAN repository connection, connection OK"
        LogCons "Connect command: rman TARGET / CATALOG $RMAN_CONN_USER/xxxxxxxxxx@$RMAN_NAME_REPO"
fi

}

#----------------------------------------------------------------------------------------------
SetNumChannels()
#----------------------------------------------------------------------------------------------
{
unset NumChannels

NumChannels=$(echo $AllParameters |  awk -F'CHANNELS=' '{print $2}' | awk '{print $1}')

if [[ ! -z $NumChannels ]]
then
        CHANNELS=$NumChannels
        LogCons "Number of CHANNELS=${CHANNELS}, none Default."
else
        LogCons "Number of CHANNELS=${CHANNELS}, Default."
fi
}
#----------------------------------------------------------------------------------------------
SetSectionSize()
#----------------------------------------------------------------------------------------------
{
unset SectionSize

SectionSize=$(echo $AllParameters | awk -F'SECTION_SIZE=' '{print $2}' | awk '{print $1}')

if [[ ! -z $SectionSize ]]
then
        export SECTION_SIZE="${SectionSize}G"
        export SECTION_SIZE_COMMAND="SECTION SIZE ${SECTION_SIZE}"
        LogCons "Backup using SECTION_SIZE (Size: ${SECTION_SIZE})."
else
        export SECTION_SIZE_COMMAND="SECTION SIZE 30G"
        LogCons "Default section size will be used (Size: 30G)."
fi

}
#--------------------------------------------------------
GetClientName ()
#---------------------------------------------------------
{
LogCons "Checking the block change tracking"


QUERY="select DB_UNIQUE_NAME from V\$DATAGUARD_CONFIG where DEST_ROLE='PRIMARY DATABASE'; "
PRIM_DB_UNIQUE_NAME=$(${ORACLE_HOME}/bin/sqlplus -s  "/ as sysdba" <<EOF
SET HEADING OFF
SET PAGESIZE 0
SET TIMING OFF
SET FEEDBACK OFF
set echo off
$QUERY
EOF
)

   if [[ -z $PRIM_DB_UNIQUE_NAME  ]]; then

        LogCons "The DB is not in DataGuard Configuration"
        ClientName=$(echo ${Database}-vip.corp.ubp.ch | tr "[:upper:]" "[:lower:]")

   else

        ClientName=$(echo ${PRIM_DB_UNIQUE_NAME}-VIP | tr -d '_' | tr "[:upper:]" "[:lower:]")
        LogCons "The DB is in DataGuard Configuration"
        LogCons "The $ClientName will be used."

     fi

}
#---------------------------------------------------------
SetChannel ()
#---------------------------------------------------------
{
ChNumber=$1
LoopCount=0

> $ChannelStart
> $ChannelStop

while (( $LoopCount < $ChNumber ))
do
        let LoopCount=$LoopCount+1
        ChannelConfAll="allocate channel c${LoopCount} type sbt  FORMAT '${FINAL_TAG}_${CH_FORMAT}' $MAXPICESIZE_COMMAND ;"
        ChannelConfSend="send channel='c${LoopCount}' 'NB_ORA_POLICY=$NB_ORA_POLICY,NB_ORA_SERV=$NB_ORA_SERV,NB_ORA_CLIENT=$ClientName,NB_ORA_SCHED=$NB_ORA_SCHED';"
        echo $ChannelConfAll >> $ChannelStart
        echo $ChannelConfSend >> $ChannelStart
        echo "release channel c${LoopCount};" >> $ChannelStop


done
}

#---------------------------------------------------------
BackupArch ()
#---------------------------------------------------------
{
LogCons "Backup Archive files."
LogCons "Script:$RmanExecFileArch"

SetChannel $CHANNELS ${ArchLabel}

DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileArch

echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE SBT_TAPE  TO '${ORACLE_SID}_CT_%F';">> $RmanExecFileArch
echo "run {" >> $RmanExecFileArch
cat $ChannelStart >> $RmanExecFileArch
echo "backup as compressed backupset ARCHIVELOG ALL delete input TAG ${FINAL_TAG};" >> $RmanExecFileArch
echo "SQL \"ALTER SYSTEM ARCHIVE LOG CURRENT\";" >> $RmanExecFileArch
echo "backup as compressed backupset ARCHIVELOG ALL delete input TAG ${FINAL_TAG};" >> $RmanExecFileArch
echo "change backupset TAG ${FINAL_TAG} KEEP FOREVER;" >> $RmanExecFileArch
cat $ChannelStop >> $RmanExecFileArch
echo "}" >> $RmanExecFileArch
echo "exit;" >> $RmanExecFileArch
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileArch 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
BackupContfile ()
#---------------------------------------------------------
{
LogCons "Backup Control file."
LogCons "Script:$RmanExecFileCONT"

DoSqlQ "execute dbms_backup_restore.resetConfig;"
echo $RetentionPolicy > $RmanExecFileCONT
SetChannel 1 ${CTL_TAG}
echo "run {" >> $RmanExecFileCONT
cat $ChannelStart >> $RmanExecFileCONT
echo "backup current controlfile TAG ${CTL_TAG};" >> $RmanExecFileCONT
echo "change backupset TAG ${CTL_TAG} KEEP FOREVER;" >> $RmanExecFileCONT
cat $ChannelStop >> $RmanExecFileCONT
echo "}" >> $RmanExecFileCONT
echo "exit;" >> $RmanExecFileCONT
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileCONT 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
BackupValidateArch ()
#---------------------------------------------------------
{
LogCons "Backup Validate file."
LogCons "Script:$RmanExecFileValidate"

SetChannel $CHANNELS

echo "run {" >> $RmanExecFileValidate
cat $ChannelStart >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL controlfile from TAG ${CTL_TAG};" >> $RmanExecFileValidate
cat $ChannelStop >> $RmanExecFileValidate
echo "}" >> $RmanExecFileValidate
echo "exit;" >> $RmanExecFileValidate
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileValidate 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
DeleteObsolete ()
#---------------------------------------------------------
{
LogCons "Delete Obsolete Backups"
LogCons "Script:$RmanExecFileObsolete"

LogCons "Cross check archive logs"
LogCons "Script: $RmanExecFileObsolete"
echo "allocate channel for maintenance device type 'SBT_TAPE';" >> $RmanExecFileObsolete
echo "delete NOPROMPT force obsolete;" >> $RmanExecFileObsolete
echo "exit;" >> $RmanExecFileObsolete
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileObsolete 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
ArchCrossCheck ()
#---------------------------------------------------------
{
LogCons "Cross check archive logs"
LogCons "Script: $RmanExecCrossArch"
echo "list backup summary;" > $RmanExecCrossArch
echo "run {" >> $RmanExecCrossArch
cat $ChannelStart >> $RmanExecCrossArch
echo "crosscheck archivelog all;" >> $RmanExecCrossArch
cat $ChannelStop >> $RmanExecCrossArch
echo "}" >> $RmanExecCrossArch
echo "exit;" >> $RmanExecCrossArch
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecCrossArch 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}

#---------------------------------------------------------
CheckError ()
#---------------------------------------------------------
{
ExecError=$(grep "RMAN-"  $TmpLogFile)

if [[ ! -z "$ExecError" ]]
then
        FirstLineError=$(grep "RMAN-"  $TmpLogFile | head -1)
        LogError "Error: $FirstLineError"
        LogError "Log file: $TmpLogFile"
        ORA_19511_ERROR=$(grep "ORA-19511"  $TmpLogFile)
        if [[ ! -z "$ORA_19511_ERROR" ]]
        then
                LogError "Check the Log file: $TAPE_logfile"
        fi
        exit 1
fi
}

#---------------------------------------------------------
# Main
#---------------------------------------------------------
IdentifyServer
CheckNBKSymlink
if [[ -z $NB_ORA_SERV ]]; then
   GetMediaServer
fi
GetClientName
SetNumChannels


LogCons "Running Archive file backup"
LogCons "Checking variables for BACKUP_ARCH."
GetBackupProperties "$2"
SetSectionSize
SetTag "$BACKUP_RETENTION"
CheckConnRepo
BackupArch
BackupContfile
DeleteObsolete
ArchCrossCheck


#------------- CROSS_CHK_ARCH -------------
if [[  "$Function" == "CROSS_CHK_ARCH" ]]
then
        CheckConnRepo
        ArchCrossCheck
fi
