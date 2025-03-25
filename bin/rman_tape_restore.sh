#!/bin/ksh -p
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: rman_tape_restore.sh [SID] [FUNCTION] <FUNCTIONS PARAMATERS> 
##
## Paramaters:
## SID: 	SID of the database to backup
##
## FUNCTION:	 
##		RESTORE_FULL:
##                Full restore of database
##		Parameter:
##	        TAG: <TAG NAME> Name of the TAG to restore
##                             e.g DAYS02_20150710_104246_DB_ARCH.
##		  The last backup will be restore if tag not specified.
##
##              UNTIL_TIME : FORMAT DD-MM-YYYY-HH24i:MM:SS
##                            e.g UNTIL_TIME=30-11-2024-12:00:00
##
##		RESTORE_SCN
##		  Full restore until SCN number
##		Parameter:
##		  SCN: <SCN_NUMBER> Restore until scn number.
##
##		RESTORE_SPFILE
##		  Restore spfile from backup and create init file.
##		  The sp- and pfile will be copied in to /backup/[SID]/rman
##		Parameter:
##		  TAG: <TAG NAME> Name of the TAG to restore e.g .
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
CONFIRM_STRING="RESTORE"

RmanConfFile=$OFA_ETC/rman_tape_restore_bkp/rman_tape_restore_bkp.defaults
TmpLogFile=$OFA_LOG/tmp/rman_tape_restore_bkp.tmp.$$.$PPID.$TimeStamp.log
TmpLogFiles=$OFA_LOG/tmp/rman_tape_restore_bkp.tmp.$$.$PPID.$TimeStamp.logs
RmanExecFileCrossCheck=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileCrossCheck.$$.$PPID.$TimeStamp.rman
CheckConnRepoLogFile=$OFA_LOG/tmp/rman_tape_restore_bkp.CheckConnRepo.$$.$PPID.$TimeStamp.log
ChannelStart=$OFA_LOG/tmp/rman_tape_restore_bkp.ChannelStart.$$.$PPID.$TimeStamp.txt
ChannelStop=$OFA_LOG/tmp/rman_tape_restore_bkp.ChannelStop.$$.$PPID.$TimeStamp.txt
RmanExecFileCheckBackup=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileCheckBackup.$$.$PPID.$TimeStamp.rman
RmanExecFileObsolete=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileObsolete.$$.$PPID.$TimeStamp.rman
RmanExecFileRestore=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileRestore.$$.$PPID.$TimeStamp.rman
RmanExecRestoreSpf=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecRestoreSpf.$$.$PPID.$TimeStamp.rman
RmanExecRestoreCtl=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecRestoreCtl.$$.$PPID.$TimeStamp.rman
RmanExecRestoreDB=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecRestoreDB.$$.$PPID.$TimeStamp.rman
RmanExecFileGetSCN=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileGetSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileGetInca=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileGetIncaSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileList=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecFileList.$$.$PPID.$TimeStamp.rman
RmanExecRmanGetTheTAGToRestore=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecRmanGetTheTAGToRestore.$$.$PPID.$TimeStamp.rman
SQLExecCommand=$OFA_LOG/tmp/rman_tape_restore_bkp.SQLExecCommand.$$.$PPID.$TimeStamp.rman
InitfileLocation=$ORACLE_HOME/dbs/init${ORACLE_SID}.ora
TnsPingLog=$OFA_LOG/tmp/rman_tape_restore_bkp.TnsPingLog.$$.$PPID.$TimeStamp.log

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$TAPE_LIBRARY_PATH
RetentionPolicy="CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${RECOVERY_WINDOW_DAYS} DAYS;"

  #
  # Check var
  #
  LogCons "Checking variables."
  CheckVar				\
	Database			\
	Function			\
  && LogCons "Variables OK!"	\
  || Usage

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
        var=$(echo "$item" | cut -c4-6 )
    if [[ "$var" == "$ServerLocation" ]]; then
            LogCons "The Media server will be $item."
        NB_ORA_SERV="$item"
    fi
done

}
#---------------------------------------------------------
GenerateInitFile ()
#---------------------------------------------------------
{
LogCons "Generate init file before spfile restore"

echo "db_name='${ORACLE_SID}'"> $InitfileLocation
echo "memory_target=1G">> $InitfileLocation
echo "processes = 150" >> $InitfileLocation
echo "audit_file_dest='/dbvar/$ORACLE_SID/log/adump'" >> $InitfileLocation
echo "db_block_size=8192">> $InitfileLocation
echo "control_files ='/DB/${ORACLE_SID}/control01.ctl','/DB/${ORACLE_SID}/control02.ctl'">> $InitfileLocation
DoSql "shutdown abort" > /dev/null 2>&1
DoSql "startup  nomount pfile='$InitfileLocation'"    >/dev/null 2>&1              

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
#---------------------------------------------------------
GetSourceDBID ()
#---------------------------------------------------------
{
LogCons "Getting the database Source DBID  from RMAN repository"
LogCons "Script: select * from rc_database where name='$DBSourceSID';"
QUERY="select  DBID from RC_DATABASE_INCARNATION where name='$DBSourceSID' order by RESETLOGS_TIME desc FETCH FIRST 1 ROWS ONLY;"
RESULT=$($ORACLE_HOME/bin/sqlplus  -s "$CAT_CONN_STRING"  <<EOF
SET LINESIZE 80
SET PAGESIZE 0
SET TRIMSPOOL OFF
SET HEADING OFF
SET FEEDBACK OFF
SET TIMING OFF
SET TERMOUT OFF
set echo off
WHENEVER SQLERROR EXIT SQL.SQLCODE
$QUERY
EXIT;
EOF
)
SourceDBID=$(echo $RESULT|tail -n 1)
LogCons "The source database DBID: $SourceDBID"


}
#---------------------------------------------------------
GetTheTAGToRestore ()
#---------------------------------------------------------
{
isTagAvaliable=$1
LogCons "Checking connection to RMAN repository and Source database list"
LogCons "Script: $RmanExecRmanGetTheTAGToRestore"

LogCons "Connect String: CATALOG $DBSourceSID/xxxxxxxxxx@$RMAN_NAME_REPO"
echo "set dbid $SourceDBID" > $RmanExecRmanGetTheTAGToRestore 
echo "list backup summary;" >> $RmanExecRmanGetTheTAGToRestore

rman CATALOG $CAT_CONN_STRING cmdfile=$RmanExecRmanGetTheTAGToRestore 2>&1 | tee $TmpLogFiles | LogStdIn


if [[ -z $isTagAvaliable ]]; 
then 

TAG_RESTORE=$(cat $TmpLogFiles | grep $DBSourceSID |  grep -v ${DBSourceSID}_SP |  grep -v ${DBSourceSID}_AR |  grep -v ${DBSourceSID}_CT | tail -1 | awk '{print $NF}')
LogCons "TAG no provided the last backup will be used"
LogCons "Last backup TAG: $TAG_RESTORE"

CompletionTime=$(cat $TmpLogFiles  | grep $TAG_RESTORE |awk  ' {print  $6, $7}' | tail -1)
SPF_TAG=$(cat $TmpLogFiles | grep $DBSourceSID | grep  _SP_ | tail -1 | awk '{print $NF}')  
CTL_TAG=$(cat $TmpLogFiles | grep $DBSourceSID | grep _CT_ |tail -1 | awk '{print $NF}' )  

elif [[ -z $RESTORE_TO_DATE ]];
then

TAG_RESTORE=$(cat $TmpLogFiles | grep $isTagAvaliable  | grep -v ${DBSourceSID}_CT |  grep -v ${DBSourceSID}_SP  | grep -v ${DBSourceSID}_AR | tail -1 | awk '{print $NF}' )
LogCons "Backup TAG to restore: $TAG_RESTORE"

CompletionTime=$(cat $TmpLogFiles  | grep $TAG_RESTORE |awk  ' {print  $6, $7}' | tail -1)
SPF_TAG=$(echo $TAG_RESTORE  | sed 's/^\([^_]*_\)\(..\)/\1SP/')
CTL_TAG=$(echo $TAG_RESTORE  | sed 's/^\([^_]*_\)\(..\)/\1CT/')

else 
        LogCons "RESTORING DATABASE $DBSourceSID  from  UNTIL TIME "

fi

}
#---------------------------------------------------------
SetChannel ()
#---------------------------------------------------------
{

ChNumber=$1
TagFormat="$2_"
LoopCount=0

ClientName=$(echo ${Database}-vip.corp.ubp.ch | tr "[:upper:]" "[:lower:]")


> $ChannelStart
> $ChannelStop

while (( $LoopCount < $ChNumber ))
do
	let LoopCount=$LoopCount+1 
        ChannelConfAll="allocate channel c${LoopCount} type sbt;"
	ChannelConfSend="send channel='c${LoopCount}' 'NB_ORA_POLICY=$NB_ORA_POLICY,NB_ORA_SERV=$NB_ORA_SERV,NB_ORA_CLIENT=$ClientName';"
	echo $ChannelConfAll >> $ChannelStart 
	echo $ChannelConfSend >> $ChannelStart 
	echo "release channel c${LoopCount};" >> $ChannelStop
done
}
#---------------------------------------------------------
GetIncarnation ()
#---------------------------------------------------------
{
LogCons "Getting the Incarnation Number."
LogCons "Script:$RmanExecFileGetInca"


if [[ ! -z $RESTORE_TO_DATE ]]
then
INC_QUERY="SELECT DBINC_KEY  FROM RC_BACKUP_REDOLOG WHERE RESETLOGS_TIME <= TO_DATE('${RESTORE_TO_DATE}', 'DD-MM-YYYY HH24:MI:SS') 
AND COMPLETION_TIME IN ( SELECT MIN(COMPLETION_TIME) FROM RC_BACKUP_REDOLOG WHERE RESETLOGS_TIME <= TO_DATE('${RESTORE_TO_DATE}', 'DD-MM-YYYY HH24:MI:SS')
    GROUP BY DBINC_KEY)
ORDER BY COMPLETION_TIME DESC FETCH FIRST 1 ROW ONLY ;"
LAST_INC=$($ORACLE_HOME/bin/sqlplus -s "$CAT_CONN_STRING" <<EOF
SET SILENT ON
SET HEADING OFF 
SET PAGESIZE 0 
SET TIMING OFF
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CALL DBMS_RCVMAN.SETDATABASE(null,null,null,$SourceDBID,null);
$INC_QUERY
EXIT;
EOF
)

else 

LAST_INC_QUERY="select distinct a.DBINC_KEY from RC_BACKUP_DATAFILE  a, RC_BACKUP_FILES  b  where a.BS_KEY=b.BS_KEY and a.DB_NAME='${DBSourceSID}' AND TAG='${TAG_RESTORE}';"
LAST_INC=$($ORACLE_HOME/bin/sqlplus -s "$CAT_CONN_STRING" <<EOF
SET HEADING OFF 
SET PAGESIZE 0 
SET TIMING OFF
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
CALL DBMS_RCVMAN.SETDATABASE(null,null,null,$SourceDBID,null);
$LAST_INC_QUERY
EXIT;
EOF
)

fi

INCA_NUMBER_RESTORE=$(echo $LAST_INC| tail -n 1) 

LogCons "Using Incarnation Number: $INCA_NUMBER_RESTORE"

}
#---------------------------------------------------------
RestoreDatabase ()
#---------------------------------------------------------
{

LogCons "Restore Database."
LogCons "Script:$RmanExecRestoreDB"

SetChannel $CHANNELS

TargetConnectString="TARGET / "

# Restore database
echo "run {" >> $RmanExecRestoreDB
cat $ChannelStart >> $RmanExecRestoreDB
echo "restore database until scn $SCN_NUMBER from TAG=$TAG_RESTORE;" >> $RmanExecRestoreDB
echo "recover database until scn $SCN_NUMBER from TAG=$TAG_RESTORE;" >> $RmanExecRestoreDB
echo "alter database open resetlogs;" >> $RmanExecRestoreDB
cat $ChannelStop >> $RmanExecRestoreDB
echo "}" >> $RmanExecRestoreDB

echo "exit;" >> $RmanExecRestoreDB

rman $TargetConnectString cmdfile=$RmanExecRestoreDB 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
RestoreSpfile ()
#---------------------------------------------------------
{
LogCons "Spfile Database."
LogCons "Script:$RmanExecRestoreSpf"

SPF_TAG_TO_RESTORE=$1
SetChannel $CHANNELS
# Restore sp file
echo "run {" >> $RmanExecRestoreSpf
cat $ChannelStart >> $RmanExecRestoreSpf
echo "set dbid $SourceDBID " >> $RmanExecRestoreSpf
echo "restore spfile;" >> $RmanExecRestoreSpf
echo "restore spfile to '$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora' from TAG=$SPF_TAG_TO_RESTORE;" >> $RmanExecRestoreSpf
echo "sql \"create pfile=''$OFA_DB_BKP/$ORACLE_SID/rman/init${ORACLE_SID}.ora'' from spfile=''$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora''\";" >> $RmanExecRestoreSpf
cat $ChannelStop >> $RmanExecRestoreSpf
echo "}" >> $RmanExecRestoreSpf
echo "shutdown immediate;" >> $RmanExecRestoreSpf
echo "startup nomount;" >> $RmanExecRestoreSpf
echo "exit;" >> $RmanExecRestoreSpf

rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecRestoreSpf 2>&1 | tee $TmpLogFile | LogStdIn

CheckError
LogCons "SPFILE restored and PFILE created in $OFA_DB_BKP/$ORACLE_SID/rman/"
}

#---------------------------------------------------------
RestoreControlfile ()
#---------------------------------------------------------
{
LogCons "Controlfile Database."
LogCons "Script:$RmanExecRestoreCtl"

SetChannel $CHANNELS

echo "reset database to incarnation $INCA_NUMBER_RESTORE;" >> $RmanExecRestoreCtl
# Restore control file
echo "run {" >> $RmanExecRestoreCtl
cat $ChannelStart >> $RmanExecRestoreCtl
echo "set dbid $SourceDBID " >> $RmanExecRestoreCtl
echo "restore controlfile from TAG=$1;" >> $RmanExecRestoreCtl
cat $ChannelStop >> $RmanExecRestoreCtl
echo "}" >> $RmanExecRestoreCtl

echo "alter database mount;" >> $RmanExecRestoreCtl
rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecRestoreCtl 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

LogCons "Restore Controlfile Done ! "
}
#---------------------------------------------------------
BackupList ()
#---------------------------------------------------------
{
LogCons "List Backups"
LogCons "Script:$RmanExecFileList"

if [[ ! -z "$ListTag" ]]
then
	LogCons "Listing for TAG: $ListTag"
fi

if [[ "$Func" == "SUMMARY" ]] && [[ ! -z "$ListTag" ]]
then
	ListCommand="List backup summary TAG=$ListTag; list incarnation;"
elif [[ "$Func" == "SUMMARY" ]]
then
        ListCommand="List backup summary; list incarnation;"
elif [[ "$Func" == "LONG" ]] && [[ ! -z "$ListTag" ]]
then
	 ListCommand="List backup TAG=$ListTag; list incarnation;"
elif [[ "$Func" == "LONG" ]]
then
	ListCommand="List backup; list incarnation;"
elif [[ "$Func" == "INCARNATION" ]]
then
	ListCommand="List INCARNATION;"
else
        LogError "Wrong FUNCTION! Function: $Func"
        Usage
        exit 1
fi

echo "set dbid=$SourceDBID" >> $RmanExecFileList
echo "$ListCommand" >> $RmanExecFileList
echo "exit;" >> $RmanExecFileList
rman CATALOG $CAT_CONN_STRING cmdfile=$RmanExecFileList 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

cat $TmpLogFile

}
#---------------------------------------------------------
RestoreDatabaseScn ()
#---------------------------------------------------------
{
Func=SUMMARY
SpFileTag=$(ExecBackupList SUMMARY | grep "_SP_" | tail -1 | awk '{print $11}') 
CtlFileTag=$(ExecBackupList SUMMARY | grep "_CT_" | tail -1 | awk '{print $11}') 

LogCons "Restore spfile until SCN $SCN_NUMBER"
LogCons "spfile to restore: $SpFileTag"

# Restore sp file
RestoreSpfile $SpFileTag

LogCons "Restore Controlfile until SCN $SCN_NUMBER"
RestoreControlfile $CtlFileTag

SetChannel $CHANNELS

LogCons "Restore Database until SCN $SCN_NUMBER"
LogCons "Script:$RmanExecFileRestore"
# Restore database
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore database until scn $SCN_NUMBER;" >> $RmanExecFileRestore
echo "recover database until scn $SCN_NUMBER;" >> $RmanExecFileRestore
echo "alter database open resetlogs;" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo " shutdown immediate; ">> $RmanExecFileRestore
echo "startup;"  >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "exit;" >> $RmanExecFileRestore

rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileRestore 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
GetSCN ()
#---------------------------------------------------------
{
LogCons "Getting the SCN Number."
LogCons "Script:$RmanExecFileGetSCN"


echo "set dbid $SourceDBID " > $RmanExecFileGetSCN
echo "list backup TAG=$TAG_RESTORE;" >> $RmanExecFileGetSCN
rman CATALOG $CAT_CONN_STRING cmdfile=$RmanExecFileGetSCN 2>&1 | tee $TmpLogFile | LogStdIn


TagExist=$(grep "specification does not" $TmpLogFile)
if [[ ! -z "$TagExist" ]]
then
	LogError "TAG $TAG_RESTORE don't exist"
	exit 1
fi

SCN_NUMBER=$(grep -v "Recovery Manager complete" $TmpLogFile | sed '/^$/d' | tail -1 | awk '{print $6}')
let SCN_NUMBER=$SCN_NUMBER-1
LogCons "Restore until SCN number: $SCN_NUMBER"

}

#---------------------------------------------------------
RestoreDatabaseTime ()
#---------------------------------------------------------
{

SetChannel $CHANNELS
LogCons "Restore SPFILE AND CONTROLFILE. "
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "set dbid $SourceDBID " >> $RmanExecFileRestore
echo "set until time \"to_date('${RESTORE_TO_DATE}', 'DD-MM-YYYY-HH24:MI:SS')\";" >> $RmanExecFileRestore
echo "restore spfile ;" >> $RmanExecFileRestore
echo "restore spfile to '${OFA_DB_BKP}/${ORACLE_SID}/rman/spfile${ORACLE_SID}.ora';" >> $RmanExecFileRestore
echo "sql \"create pfile=''$OFA_DB_BKP/$ORACLE_SID/rman/init${ORACLE_SID}.ora'' from spfile=''$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora''\";" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "shutdown immediate;" >> $RmanExecFileRestore
echo "startup nomount;" >> $RmanExecFileRestore

# Restore control file
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "set dbid $SourceDBID " >> $RmanExecFileRestore
echo "set until time \"to_date('${RESTORE_TO_DATE}', 'DD-MM-YYYY-HH24:MI:SS')\";" >> $RmanExecFileRestore
echo "restore controlfile;" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore
echo "reset database to incarnation $INCA_NUMBER_RESTORE;" >> $RmanExecFileRestore
echo "alter database mount;" >> $RmanExecFileRestore

echo "exit;" >> $RmanExecFileRestore

rman $TARG_CAT_CONN_STRING cmdfile=$RmanExecFileRestore 2>&1 | tee $TmpLogFile | LogStdIn

# Restore database
echo "run {" >> $RmanExecRestoreDB
cat $ChannelStart >> $RmanExecRestoreDB
echo "restore database until time \"to_date('${RESTORE_TO_DATE}', 'DD-MM-YYYY-HH24:MI:SS')\";" >> $RmanExecRestoreDB
echo "recover database until time \"to_date('${RESTORE_TO_DATE}', 'DD-MM-YYYY-HH24:MI:SS')\";" >> $RmanExecRestoreDB
echo "alter database open resetlogs;" >> $RmanExecRestoreDB
cat $ChannelStop >> $RmanExecRestoreDB
echo "}" >> $RmanExecRestoreDB

echo "exit;" >> $RmanExecRestoreDB
LogCons "RESTORING DATABASE BACKUP UNTIL TIME : $RESTORE_TO_DATE  "

rman TARGET / cmdfile=$RmanExecRestoreDB 2>&1 | tee $TmpLogFile | LogStdIn

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
ExecBackupList ()
#---------------------------------------------------------
# Parameter $1 Func, $2 ListTag
#---------------------------------------------------------
{
	Func=$1
        ListTag=$2
        LogCons "Running BACKUP LIST of database. "
        #
        # Check var
        #
        LogCons "Checking variables for BACKUP_LIST."
        CheckVar                              \
                Func                        \
        && LogCons "Variables OK!"    \
        || Usage

	DbStatus=$(OraDbStatus)
	if [[ "$DbStatus" == "DOWN" ]]
	then
		RestartNomount		
	fi
 	BackupList
}
#-
#---------------------------------------------------------
RestartNomount ()
#---------------------------------------------------------
{
LogCons "Restart the database in $ORACLE_SID in nomount mode."
DoSqlQ "shutdown abort;" >/dev/null 2>&1
DoSqlQ "startup nomount;" >/dev/null 2>&1

}

#---------------------------------------------------------
RestoreConfirmation()
#---------------------------------------------------------
{
LogCons "----------------------------------------------------------------- "
LogCons " "
LogCons "WARNING: This action is irreversible. Please proceed with caution."
LogCons " "
LogCons "-----------------------------------------------------------------"
LogCons " "
LogCons  "Please type $CONFIRM_STRING to confirm execution: "
read  user_input

if [[ "$user_input" != "$CONFIRM_STRING" ]]; then
    LogCons "Confirmation failed. Script execution canceled."
    exit 1
fi

# Second confirmation: yes or no
LogCons  "Are you sure you want to proceed? (y/n): "
read  confirmation
if [[ "$confirmation" = "y" ]] || [[ "$confirmation" = "Y" ]];
 then
    LogCons "Confirmation received. Running the script..."

else
    LogCons "Script execution canceled."
    exit 1
fi
}
#---------------------------------------------------------
# Main 
#---------------------------------------------------------
RestoreConfirmation
IdentifyServer

if [[ -z $NB_ORA_SERV ]]; then
   GetMediaServer
fi


if [[ "$Function" == "RESTORE_FULL" ]]
then    
        
        DBSourceSID=$1
        TAG=$3
        RESTORE_TO_DATE=$(echo $AllParameters |  awk -F'UNTIL_TIME=' '{print $2}' | awk '{print $1}')
        LogCons "Running FULL RESTORE of database. "
        LogCons "Checking variables for FULL_RESTORE."
        GenerateInitFile
        GetSourceDBID
        GetTheTAGToRestore $TAG
        GetIncarnation
	LogCons "Deleting the old database: $ORACLE_SID"
	LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
	LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
	LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
	DoSql "shutdown abort" > /dev/null 2>&1
	rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
	rm $ORACLE_HOME/dbs/spfile$ORACLE_SID* > /dev/null 2>&1
	rm $OFA_DB_ARCH/$ORACLE_SID/* > /dev/null 2>&1
	RestartNomount
        if [[ ! -z $RESTORE_TO_DATE ]]
        then
          RestoreDatabaseTime
        else 
        GetSCN
        RestoreSpfile $SPF_TAG
        RestoreControlfile $CTL_TAG
        RestoreDatabase
        fi
        exit $ExitCode

#------------- RESTORE_SPFILE -------------
elif [[ "$Function" == "RESTORE_SPFILE" ]]
then
        Tag=$3
        DBSourceSID=$1
        LogCons "Running RESTORE of spfile."
        #
        # Check var
        #
        LogCons "Checking variables for RESTORE spfile."
        CheckVar                              \
                Tag                        \
        && LogCons "Variables OK!"    \
        || Usage
        SetTapePath
        GetSourceDBID
        GetTheTAGToRestore "$3"
        RestartNomount
        CheckConnRepo
        RestoreSpfile $Tag

#------------- RESTORE_SCN -------------
elif [[ "$Function" == "RESTORE_SCN" ]]
then
	SCN_NUMBER=$3
        DBSourceSID=$1
        LogCons "Running FULL RESTORE until SCN number: $SCN_NUMBER ."
        LogCons "Checking variables for RESTORE_SCN."
        CheckVar                              \
                SCN_NUMBER                        \
        && LogCons "Variables OK!"    \
        || Usage
        GenerateInitFile
        SetTapePath
        RestartNomount
        GetSourceDBID
        CheckConnRepo
        GetIncarnation
        LogCons "Deleting the old database: $ORACLE_SID"
        LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
        LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
        LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
        DoSql "shutdown abort" > /dev/null 2>&1
        rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
        rm $ORACLE_HOME/dbs/spfile$ORACLE_SID* > /dev/null 2>&1
        rm $OFA_DB_ARCH/$ORACLE_SID/* > /dev/null 2>&1

        RestartNomount
	RestoreDatabaseScn

else
	LogError "Wrong FUNCTION! Function: $Function"
	Usage
	exit 1
fi


