#!/bin/ksh -p
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: rman_tape_hot_bkp.sh [SID] [FUNCTION] [RETENTION] <FUNCTIONS PARAMATERS>  <backup or blank>
##
## Paramaters:
## SID:         SID of the database to backup
##
## FUNCTION:
##              BACKUP_FULL:
##                Full database backup, Level 0
##
##              BACKUP_INCR:
##                Incremental backup, Level 1
##
##              BACKUP_CUM:
##                Cumulative backup, Level 2
##
##              VERIFY :
##                    (ONLY verify the last backup) eg. rman_tape_hot_bkp.sh DBATST04 VERIFY
##
##                 FUNCTIONS PARAMATERS:
##                     RETENTION: Backup retention  [eg: DAYS03 - DAYS21 - WEEK05 - MONT12 - YEAR10 ]
##
##                     TAG=(TAG NAME) The backup tag name(limit 11 characteres) e.g TAG=BNRNOV2024.
##
##
##                     CHANNELS=(NUMBER_OF CHANNELS) set the number of channels to use diffrent from default.
##
##                     SECTION_SIZE=(SIZE_OF_SECTION) Backup will use section size during backup, eg SIZE_OF_SECTION=40 .
##
##
##                     backup :
##                         (ONLY Backup the last backup)
##
##                     blank :
##                      (No parameters: backup and verify))
##
##              CROSS_CHK_ARCH:
##                RMAN command: archive crosscheck all.
##                    This will sync the rman catalog with the archive logs existing.
##
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
AllParameters=$*



RmanConfFile=$OFA_ETC/rman_tape_hot_bkp/rman_tape_hot_bkp.defaults
TmpLogFile=$OFA_LOG/tmp/rman_tape_hot_bkp.tmp.$$.$PPID.$TimeStamp.log
TmpLogFiles=$OFA_LOG/tmp/rman_tape_hot_bkp.tmp.$$.$PPID.$TimeStamp.logs
CheckConnRepoLogFile=$OFA_LOG/tmp/rman_tape_hot_bkp.CheckConnRepo.$$.$PPID.$TimeStamp.log
ChannelStart=$OFA_LOG/tmp/rman_tape_hot_bkp.ChannelStart.$$.$PPID.$TimeStamp.txt
ChannelStop=$OFA_LOG/tmp/rman_tape_hot_bkp.ChannelStop.$$.$PPID.$TimeStamp.txt
RmanCommandList=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanCommandList.$$.$PPID.$TimeStamp.rman
RmanExecFileSP=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileSP.$$.$PPID.$TimeStamp.rman
RmanExecFileCONT=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileCONT.$$.$PPID.$TimeStamp.rman
RmanExecFileDB=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileDB.$$.$PPID.$TimeStamp.rman
RmanExecFileCrossCheck=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileCrossCheck.$$.$PPID.$TimeStamp.rman
RmanExecFileCrossCheckLog=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileCrossCheck.$$.$PPID.$TimeStamp.log
RmanExecFileValidate=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileValidate.$$.$PPID.$TimeStamp.rman
RmanExecFileCheckBackup=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileCheckBackup.$$.$PPID.$TimeStamp.rman
RmanExecFileObsolete=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileObsolete.$$.$PPID.$TimeStamp.rman
RmanExecFileList=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecFileList.$$.$PPID.$TimeStamp.rman
RmanExecCrossArch=$OFA_LOG/tmp/rman_tape_hot_bkp.RmanExecCrossArch.$$.$PPID.$TimeStamp.rman
TnsPingLog=$OFA_LOG/tmp/rman_tape_hot_bkp.TnsPingLog.$$.$PPID.$TimeStamp.log

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$TAPE_LIBRARY_PATH
RetentionPolicy="CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 356 DAYS;"
#RetentionPolicy="CONFIGURE RETENTION POLICY TO NONE;"


  #
  # Check var
  #
  LogCons "Checking variables."
  CheckVar                              \
        Database                        \
        Function                        \
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

fi
LogCons "Oracle library symbolic link check OK ! "

}
#---------------------------------------------------------
SetTag ()
#---------------------------------------------------------
{

KeepPeriode=$(eval "echo \$$1")

TAG=$(echo $AllParameters | awk -F'TAG=' '{print $2}' | awk '{print $1}')


if [[ "$TAG" == "DEFAULT" || -z "$TAG"  ]]
then
        MAIN_TAG=$(echo ${BACKUP_RETENTION}_${MAIN_TAG} | sed 's/..$//')
        FINAL_TAG=${ORACLE_SID}_${BACKUP_LABEL}_${MAIN_TAG}
        SPF_TAG=${ORACLE_SID}_${SpfileLabel}_${MAIN_TAG}
        CTL_TAG=${ORACLE_SID}_${ControlFileLabel}_${MAIN_TAG}
        LogCons "Backup TAG not provided on the parameter, the default backup will be used  : $FINAL_TAG !!!"
else
      if [[ ${#TAG} -gt 11 ]]; then

           LogCons "The Tag couldn't exceeds 11 characters, please redefine the tag name"
           exit 1;

      else
           FINAL_TAG=${ORACLE_SID}_FU_${TAG}_${TimeStamp}
           SPF_TAG=${ORACLE_SID}_${SpfileLabel}_${TAG}_${TimeStamp}
           CTL_TAG=${ORACLE_SID}_${ControlFileLabel}_${TAG}_${TimeStamp}
           LogCons  "Backup TAG: $FINAL_TAG will be used !"
      fi
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
fi

LogCons "Using Backup TAG: $FINAL_TAG "

KeepCommand="KEEP FOREVER"

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
        TargetConnectString="TARGET /"
        LogCons "Connect command: rman $TargetConnectString"

        OFA_CONS_VOL=$OFA_CONS_VOL_OLD
        export OFA_CONS_VOL
        ExitCode=50
else
        LogCons "Check RMAN repository connection, connection OK"
        LogCons "Connect command: rman TARGET / CATALOG $RMAN_CONN_USER/xxxxxxxxxx@$RMAN_NAME_REPO"
fi

}
#---------------------------------------------------------
GetBackupProperties()
#---------------------------------------------------------
{

BACKUP_FUNCTION=$1
BACKUP_RETENTION=$2

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


if [[ $BACKUP_FUNCTION == "BACKUP_FULL" ]]
then
      BACKUP_LV=0
      BACKUP_LABEL="FU"
      LogCons "RMAN backup script options: Incremental Level 0 - Full."

            if  [[ $BACKUP_RETENTION == "WEEK05" ]] || [[ -z "$BACKUP_RETENTION" ]] || [[ $BACKUP_RETENTION == "DAYS21" ]] || [[ $BACKUP_RETENTION == "DAYS03" ]] ; then
                    NB_ORA_SCHED="weekly"
                    BACKUP_RETENTION="WEEK05"

            elif  [[ $BACKUP_RETENTION == "MONT12" ]]; then
                    NB_ORA_SCHED="monthly"

            else   [[ $BACKUP_RETENTION == "YEAR10" ]]
                    NB_ORA_SCHED="yearly"

            fi

elif [[ $BACKUP_FUNCTION == "BACKUP_INCR" ]]
then
      BACKUP_LV=1
      BACKUP_LABEL="IN"
      NB_ORA_SCHED=daily
      LogCons "RMAN backup script options: Incremental Level 1 - Differential."
      BACKUP_RETENTION="DAYS21"


elif [[ $BACKUP_FUNCTION == "BACKUP_CUM" ]]
then
        BACKUP_LV=2
        BACKUP_LABEL="CU"
        NB_ORA_SCHED=daily
        LogCons "RMAN backup script options: Cumulative Level 2 - Cumulative."

else
        LogError "RMAN backup script ERROR ! illegal option"
        Usage
        exit 1
fi

         LogCons "The Netbackup schedule will be $NB_ORA_SCHED."

}

#---------------------------------------------------------
CheckBackupOption ()
#---------------------------------------------------------
{

BACKUP_OPTION=$(echo $AllParameters  |  grep -o "backup")
case $BACKUP_OPTION  in
    "backup")
        LogCons "The script will run only backup, NO verify of backup "
        BACKUP_OPTION="backup_only"
        ;;
    *)
         LogCons "The script will run backup and verify "
        ;;

esac
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
#---------------------------------------------------------
SetChannel ()
#---------------------------------------------------------
{
ChNumber=$1
LoopCount=0
TAG_FORMAT=$2

#db_vip=$(for VIP in `ip a  | grep inet | awk '{print $2}' | grep -v 127.0.0.1 | awk -F "/" '{print $1}'`; do  nslookup $VIP ; done | grep -i $ORACLE_SID  |  awk '{print $4}')
#ClientName=$(echo "${db_vip%.}")

> $ChannelStart
> $ChannelStop

if [[  $Function == "VERIFY" ]]; then

        while (( $LoopCount < $ChNumber ))
        do
                let LoopCount=$LoopCount+1
                ChannelConfAll="allocate channel c${LoopCount} type sbt  FORMAT '${TAG_FORMAT}_${CH_FORMAT}';"
                 ChannelConfSend="send channel='c${LoopCount}' 'NB_ORA_POLICY=$NB_ORA_POLICY,NB_ORA_SERV=$NB_ORA_SERV,NB_ORA_CLIENT=$ClientName';"
                echo $ChannelConfAll >> $ChannelStart
                echo $ChannelConfSend >> $ChannelStart
                echo "release channel c${LoopCount};" >> $ChannelStop


        done

else

        while (( $LoopCount < $ChNumber ))
        do
                let LoopCount=$LoopCount+1
                ChannelConfAll="allocate channel c${LoopCount} type sbt  FORMAT '${TAG_FORMAT}_${CH_FORMAT}';"
                ChannelConfSend="send channel='c${LoopCount}' 'NB_ORA_POLICY=$NB_ORA_POLICY,NB_ORA_SERV=$NB_ORA_SERV,NB_ORA_CLIENT=$ClientName,NB_ORA_SCHED=$NB_ORA_SCHED';"
                echo $ChannelConfAll >> $ChannelStart
                echo $ChannelConfSend >> $ChannelStart
                echo "release channel c${LoopCount};" >> $ChannelStop


        done

fi

}


#---------------------------------------------------------
BackupSpfile ()
#---------------------------------------------------------
{

LogCons "Backup SP file."
LogCons "Script:$RmanExecFileSP"

DoSqlQ "execute dbms_backup_restore.resetConfig;"
echo $RetentionPolicy > $RmanExecFileSP
SetChannel 1 ${SPF_TAG}
echo "run {" >> $RmanExecFileSP
cat $ChannelStart >> $RmanExecFileSP
echo "backup spfile TAG ${SPF_TAG} ;" >> $RmanExecFileSP
echo "change backupset TAG ${SPF_TAG} KEEP FOREVER ;" >> $RmanExecFileSP
cat $ChannelStop >> $RmanExecFileSP
echo "}" >> $RmanExecFileSP
echo "exit;" >> $RmanExecFileSP
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileSP 2>&1 | tee $TmpLogFile | LogStdIn

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
#echo "backup current controlfile TAG ${ControlFileLabel}_${MAIN_TAG};" >> $RmanExecFileCONT
echo "backup current controlfile TAG ${CTL_TAG};" >> $RmanExecFileCONT
echo "change backupset TAG ${CTL_TAG} KEEP FOREVER;" >> $RmanExecFileCONT
cat $ChannelStop >> $RmanExecFileCONT
echo "}" >> $RmanExecFileCONT
echo "exit;" >> $RmanExecFileCONT
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileCONT 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
BackupCrossCheck ()
#---------------------------------------------------------
{
LogCons "Backup Cross Check."
LogCons "Script:$RmanExecFileCrossCheck"

SetChannel $CHANNELS
echo "run {" >> $RmanExecFileCrossCheck
cat $ChannelStart >> $RmanExecFileCrossCheck
echo "CROSSCHECK BACKUP;" >> $RmanExecFileCrossCheck
cat $ChannelStop >> $RmanExecFileCrossCheck
echo "}" >> $RmanExecFileCrossCheck
echo "exit;" >> $RmanExecFileCrossCheck
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileCrossCheck 2>&1 | tee $RmanExecFileCrossCheckLog | LogStdIn



CrossCheckErr=$(grep "crosschecked backup piece: found to be " $RmanExecFileCrossCheckLog | grep -v AVAILABLE)

#if [[ ! -z "$CrossCheckErr" ]]
#then
#        LogError "Error by Cross check. Check log file."
#        LogError "Log file: $RmanExecFileCrossCheckLog"
#        LogError "Backup pieces not in AVAILABLE status"
#fi
}
#---------------------------------------------------------
BackupDatabase ()
#---------------------------------------------------------
{
LogCons "Backup Database."
LogCons "Script:$RmanExecFileDB"

SetChannel $CHANNELS ${FINAL_TAG}
DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileDB
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '$ORACLE_HOME/dbs/${ORACLE_SID}_bck_ctf_%F.ctl';">> $RmanExecFileDB
echo "SQL \"ALTER SYSTEM ARCHIVE LOG CURRENT\";" >> $RmanExecFileDB
echo "run {" >> $RmanExecFileDB
cat $ChannelStart >> $RmanExecFileDB
echo "backup filesperset $FILESPERSET as compressed backupset INCREMENTAL LEVEL $BACKUP_LV $SECTION_SIZE_COMMAND DATABASE TAG $FINAL_TAG PLUS ARCHIVELOG delete input TAG $FINAL_TAG;" >> $RmanExecFileDB
echo "change backupset TAG $FINAL_TAG KEEP FOREVER;" >> $RmanExecFileDB
cat $ChannelStop >> $RmanExecFileDB
echo "}" >> $RmanExecFileDB
echo "exit;" >> $RmanExecFileDB
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileDB 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}

#---------------------------------------------------------
BackupValidate ()
#---------------------------------------------------------
{

LogCons "Backup Validate file."
LogCons "Script:$RmanExecFileValidate"
QUERY="select distinct a.BS_KEY from RC_BACKUP_SET a join RC_BACKUP_PIECE b on  a.BS_KEY=b.BS_KEY and b.TAG='$FINAL_TAG';"
BACKUP_SET_NUM_TMP=$(${ORACLE_HOME}/bin/sqlplus -s $CAT_CONN_STRING <<EOF
SET SILENT ON
SET HEADING OFF
SET PAGESIZE 0 LINE 100
SET TIMING OFF
SET FEEDBACK OFF
$QUERY
EOF
)

BACKUP_SET_NUM=$(echo "$BACKUP_SET_NUM_TMP" |  tr '\n' ',' |  rev | cut -c 2- | rev )

SetChannel $CHANNELS

echo "run {" >> $RmanExecFileValidate
cat $ChannelStart >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL spfile from TAG ${SPF_TAG};" >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL controlfile from TAG ${CTL_TAG};" >> $RmanExecFileValidate
echo "VALIDATE BACKUPSET $BACKUP_SET_NUM ;" >> $RmanExecFileValidate
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

SetChannel $CHANNELS
echo "crosscheck backup ;" >> $RmanExecFileObsolete
echo "host 'echo \"******************************* List Before delete of Backup *******************************\"';" >> $RmanExecFileObsolete
echo "list backup summary;" >> $RmanExecFileObsolete
echo "run {" >> $RmanExecFileObsolete
cat $ChannelStart >> $RmanExecFileObsolete
echo "delete noprompt obsolete;" >> $RmanExecFileObsolete
echo "delete expired backup ;" >> $RmanExecFileObsolete
cat $ChannelStop >> $RmanExecFileObsolete
echo "}" >> $RmanExecFileObsolete
echo "host 'echo \"******************************* List After delete of Backup *******************************\"';" >> $RmanExecFileObsolete
echo "list backup summary;" >> $RmanExecFileObsolete
echo "exit;" >> $RmanExecFileObsolete
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileObsolete 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#--------------------------------------------------------
CheckBlockChangeTracking ()
#---------------------------------------------------------
{
LogCons "Checking the block change tracking"

BCT_STATUS=$(sqlplus -s "/ as sysdba" <<EOF
SET HEADING OFF
SET PAGESIZE 0
SET TIMING OFF
SET FEEDBACK OFF
set echo off
select status from v\$block_change_tracking;
EXIT;
EOF
)

if [[ $BCT_STATUS == "ENABLED" ]]; then
 LogCons "The block change tracking is already enabled ..."

else
DoSqlQ "alter database enable block change tracking using file '/DB/$ORACLE_SID/block_tracking_rman.f';"
 LogCons "The block change tracking enabled !"
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

#----------------------------------------------------------------------------------------------
GetLastTag()
#----------------------------------------------------------------------------------------------
{
LogCons "Checking the last TAG"

echo "list backup summary;" > $RmanCommandList
echo "exit;" >> $RmanCommandList
rman $TARG_CAT_CONN_STRING cmdfile=$RmanCommandList 2>&1 | tee $TmpLogFile | LogStdIn

FINAL_TAG=$(cat $TmpLogFile | grep $ORACLE_SID |  grep -v ${ORACLE_SID}_SP |  grep -v ${ORACLE_SID}_AR |  grep -v ${ORACLE_SID}_CT | tail -1 | awk '{print $NF}')

LogCons "Checking th $FINAL_TAG"

SPF_TAG=$(echo $FINAL_TAG  | sed 's/^\([^_]*_\)\(..\)/\1SP/')

CTL_TAG=$(echo $FINAL_TAG  | sed 's/^\([^_]*_\)\(..\)/\1CT/')

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
SetNumChannels
GetClientName

#------------- FULL BACKUP -------------

if [[ "$Function" == "BACKUP_FULL"  ]] || [[ "$Function" == "BACKUP_INCR" ]] || [[ "$Function" == "BACKUP_CUM" ]]
then
        BACKUP_RETENTION=$3
        CheckBackupOption
        LogCons "Checking variables for $Function ."
        CheckBlockChangeTracking
        SetSectionSize
        GetBackupProperties "$2" "$3"
        SetTag $BACKUP_RETENTION
        CheckConnRepo
        BackupSpfile
        BackupDatabase
        BackupContfile
        if [[ -z $BACKUP_OPTION ]]; then
        BackupValidate
        fi
        BackupCrossCheck
        exit $ExitCode

elif [[  "$Function" == "VERIFY"  ]]
then
        LogCons "Checking variables for $Function ."
        LogCons "The script will run only verify  with the last backup."
        SetSectionSize
        CheckConnRepo
        GetLastTag
        BackupValidate

else
        LogError "Wrong FUNCTION! Function: $Function"
        Usage
        exit 1
fi
