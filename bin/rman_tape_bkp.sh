#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: rman_tape_bkp.sh [SID] [FUNCTION] <FUNCTIONS PARAMATERS> 
##
## Paramaters:
## SID: 	SID of the database to backup
##
## FUNCTION:	 
##              BACKUP_FULL:
##                Full database backup, 
##		Parameters:
##		  TAG:  Tag name readed from $OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults
##
##              BACKUP_ARCH:
##                Archive file backup
##              Paramaters:
##		  TAG:  Tag name readed from $OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults
##
##		RESTORE_FULL:
##                Full restore of database
##		Parameter:
##		  TAG: <TAG NAME> Name of the TAG to restore e.g DAYS02_20150710_104246_DB_ARCH.
##		
##		RESTORE_SCN
##		  Full restore until SCN number
##		Parameter:
##		  SCN: <SCN_NUMBER> Restore until scn number.
##		  
##              DUPLICATE_DB
##		  Duplicate the database, restore DB with an other name.
##              Parameter:
##		  SOURCE_DB: Name of the source database.
##                SERVER_NAME: Server name of source database.
##                TAG: <TAG NAME> Name of the TAG to restore e.g DAYS02_20150710_104246_DB_ARCH.
##		  Remark:
##			If no TAG duplicating the newest backup.
##
##		CROSS_CHK_ARCH:
##		  RMAN command: archive crosscheck all. 
##                This will sync the rman catalog with the archive logs existing.
##
##		BACKUP_LIST
##		  List avaiable backups for the database.
##		Parameter:
##                INCARNATION:	List database Incarnations. 
##		  SUMMARY:	Show the summary list of backups.
##		  LONG:		Detailed list of backups.
##		    Parameter:
##                    TAG: <TAG NAME> Name of TAG for detailed info e.g DAYS02_20150710_104246_DB_ARCH
##			
##		RUN_COMMAND
##  		  Running a RMAN command. With the tape interface.
##		Parameter:
##		  "[RMAN_COMMAND]"
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
ControlFileLabel=CON_F
DbArchLabel=DB_AR
SpfileLabel=SP_FI
ArchLabel=ARCHI

RmanConfFile=$OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults
AvaFlagFile=$OFA_LOG/tmp/rman_tape_bkp.FlagFile$$.$PPID.$TimeStamp.conf
TmpLogFile=$OFA_LOG/tmp/rman_tape_bkp.tmp.$$.$PPID.$TimeStamp.log
CheckConnRepoLogFile=$OFA_LOG/tmp/rman_tape_bkp.CheckConnRepo.$$.$PPID.$TimeStamp.log
ChannelStart=$OFA_LOG/tmp/rman_tape_bkp.ChannelStart.$$.$PPID.$TimeStamp.txt
ChannelStop=$OFA_LOG/tmp/rman_tape_bkp.ChannelStop.$$.$PPID.$TimeStamp.txt
RmanExecFileSP=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileSP.$$.$PPID.$TimeStamp.rman
RmanExecFileCONT=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileCONT.$$.$PPID.$TimeStamp.rman
RmanExecFileDB=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileDB.$$.$PPID.$TimeStamp.rman
RmanExecFileCrossCheck=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileCrossCheck.$$.$PPID.$TimeStamp.rman
RmanExecFileCrossCheckLog=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileCrossCheck.$$.$PPID.$TimeStamp.log
RmanExecFileValidate=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileValidate.$$.$PPID.$TimeStamp.rman
RmanExecFileCheckBackup=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileCheckBackup.$$.$PPID.$TimeStamp.rman
RmanExecFileObsolete=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileObsolete.$$.$PPID.$TimeStamp.rman
RmanExecFileArch=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileArch.$$.$PPID.$TimeStamp.rman
RmanExecFileRestore=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileRestore.$$.$PPID.$TimeStamp.rman
RmanExecFileGetSCN=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileGetSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileGetInca=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileGetIncaSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileList=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileList.$$.$PPID.$TimeStamp.rman
RmanExecCrossArch=$OFA_LOG/tmp/rman_tape_bkp.RmanExecCrossArch.$$.$PPID.$TimeStamp.rman
RmanExecRmanCommand=$OFA_LOG/tmp/rman_tape_bkp.RmanExecRmanCommand.$$.$PPID.$TimeStamp.rman
RmanExecRmanGetLastTAG=$OFA_LOG/tmp/rman_tape_bkp.RmanExecRmanGetLastTAG.$$.$PPID.$TimeStamp.rman
RmanExecFileDuplicate=$OFA_LOG/tmp/rman_tape_bkp.RmanExecFileDuplicate.$$.$PPID.$TimeStamp.rman
TnsPingLog=$OFA_LOG/tmp/rman_tape_bkp.TnsPingLog.$$.$PPID.$TimeStamp.log

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
SetTag ()
#---------------------------------------------------------
{

TAG=$(eval "echo \$$Tag")

if [[ -z "$TAG" ]]
then
	LogError "Backup TAG: $Tag don't exist in $OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults"
        exit 1
else 

	MAIN_TAG=${Tag}_${MAIN_TAG}
	KeepPeriode=$TAG        
	LogCons "Using Backup TAG: $Tag Expire Periode: $KeepPeriode Main TAG: $MAIN_TAG" 
fi

CheckDate=$(DoSqlQ "select $KeepPeriode from dual;" | grep ORA-)

if [[ ! -z "$CheckDate" ]]
then
	LogError "Wrong date format in TAG: $Tag Expire Periode: $KeepPeriode"
        LogError "Error: $CheckDate"
	exit 1
else
        ExpDate=$(DoSqlQ "select $KeepPeriode from dual;")
	ExpDateDays=$(DoSqlQ "select replace(round(abs(sysdate-$KeepPeriode)), chr(32), '') from dual;")
        ExpDateAvamar=$(($ExpDateDays+AvamarExpirePlus))
        expiresExpDateAvamar="\"--expires=${ExpDateAvamar}\""
	LogCons "Backup RMAN: expire date: $ExpDate, in days: $ExpDateDays, AVAMAR: expire in days: $ExpDateAvamar"
fi

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
		break
	fi
done

if [[ -z "$TAPE_path_zone" ]]
then
	TAPE_path_zone=$SECU_TAPE_path
	LogCons "Server in Secure zone, Server ip: $NetWorkPing"
fi
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
SetTapePath ()
#---------------------------------------------------------
{
# set -vx

# Not Used
# IdentifyServer
DBTypeEvProd



# if [ "$OSNAME" = "Linux" ] ; then
#	# LogCons "OS system: $OSNAME"
#	IpNo=$(/sbin/ifconfig | grep "inet addr:" | awk '{print $2}' | awk -F ":" '{print $2}')
#elif [ "$OSNAME" = "SunOS" ] ; then
#	# LogCons "OS system: $OSNAME"
#	IpNo=$(/sbin/ifconfig -a | grep "inet " | awk '{print $2}')
#elif [ "$OSNAME" = "AIX" ] ; then
#	# LogCons "OS system: $OSNAME"
#	IpNo=$(/etc/ifconfig -a | grep "inet " | awk '{print $2}')
#fi
#
#for i in $IpNo
#do 
# typeset -u DBHostName 
#
# IpRev=$(echo $i | awk -F"." '{for(i=NF;i>1;i--) printf("%s.",$i);print $1}')
# DBHostName=$(nslookup $i | grep $IpRev | awk -F "name =" '{print $2}' | sed s/.$// | sed -e 's/^ *//g;s/ *$//g' | awk -F "." '{print $1}') 
# DBHostName=$(echo $DBHostName | grep $ORACLE_SID)
#
# if [[ ! -z "$DBHostName" ]]
# then
#	typeset -l DBHostName
#	break
# fi
#done
#
#
#if [[ -z $DBHostName ]]
#then
#	typeset -l DBHostName
#	DBHostName=$HOSTNAME
#fi

DBHostName=$(echo ${ORACLE_SID}-vip |tr "[:upper:]" "[:lower:]")

TAPE_path="${MAIN_TAPE_path}/${TAPE_path_zone}/${DBType}/${DBHostName}"
# TAPE_path="${MAIN_TAPE_path}/${DBType}/${DBHostName}"

LogCons "Setting TAPE PATH=$TAPE_path"

}
#------------------------------------------------
SetRMAN_REPO ()
#------------------------------------------------
{
# set -xv
LogCons "Start SetRMAN_REPO"

ListRmanRepo=$(grep RMAN_NAME_REPO $RmanConfFile  | awk -F '=' '{print $2}' | tr '\n' ' ')
LogCons "RMAN repo DB's: $ListRmanRepo"

for i in $ListRmanRepo
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

echo "*$ErrorMess*"

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

LogCons "Checking connection to RMAN repository and resync catalog. (${RMAN_REPO})"
LogCons "Log file: $CheckConnRepoLogFile"

ConnectString="TARGET / CATALOG $ORACLE_SID/$RMAN_CONN@$RMAN_REPO"
rman $ConnectString << ___EOF > $CheckConnRepoLogFile 2>&1
RESYNC CATALOG;
exit
___EOF

if [[ $? -ne 0 ]]
then
	OFA_CONS_VOL_OLD=$OFA_CONS_VOL
	export OFA_CONS_VOL=1

	LogWarning "Error connecting to RMAN repository $ORACLE_SID/<password>@${RMAN_REPO}"
        LogWarning "Log file: $CheckConnRepoLogFile"
        LogWarning "Using control file instead of RMAN repository !!!!"
	ConnectString="TARGET /"
	LogCons "Connect command: rman $ConnectString"
	
	OFA_CONS_VOL=$OFA_CONS_VOL_OLD
	export OFA_CONS_VOL
	ExitCode=50
else
	LogCons "Check RMAN repository connection, connection OK"
	LogCons "Connect command: rman $ConnectString"
fi

}
#---------------------------------------------------------
GetLastTAG ()
#---------------------------------------------------------
{
LogCons "Checking connection to RMAN repository and Source database list"
LogCons "Script: $RmanExecRmanGetLastTAG"

ConnectString="CATALOG $DuplicateSourceSid/$RMAN_CONN@$RMAN_REPO"

LogCons "Connect String: CATALOG $DuplicateSourceSid/xxxxxxxxxx@$RMAN_REPO"

echo "connect target /" > $RmanExecRmanGetLastTAG 
echo "list backup summary;" >> $RmanExecRmanGetLastTAG

rman $ConnectString cmdfile=$RmanExecRmanGetLastTAG 2>&1 | tee $TmpLogFile | LogStdIn
CheckError

LastBackup=$(cat $TmpLogFile | grep $DbArchLabel | tail -1 | awk '{print $NF}')
LogCons "Last backup TAG: $LastBackup"

}
#---------------------------------------------------------
CheckBackup ()
#---------------------------------------------------------
{
LogCons "Backup Check"
LogCons "Script:$RmanExecFileCheckBackup"
rman $ConnectString << ___EOF > $TmpLogFile 2>&1
list backup summary;
___EOF

Year=$(date +"%Y")
Month=$(date +"%Y%m")

CheckYear=$(grep YEAR_${Year} $TmpLogFile | tail -1)
CheckMonth=$(grep MONTH_${Month} $TmpLogFile | tail -1)

if [ -z "$CheckYear" ] ; then
	MAIN_TAG=YEAR_${MAIN_TAG}	
	KeepPeriode="add_months(sysdate,12)"
elif [ -z "$CheckMonth" ] ; then
	MAIN_TAG=MONTH_${MAIN_TAG}
	KeepPeriode="add_months(sysdate,12)"
else
	MAIN_TAG=DAY_${MAIN_TAG}
	KeepPeriode="sysdate+${RECOVERY_WINDOW_DAYS}"
fi
}
#---------------------------------------------------------
SetChannel ()
#---------------------------------------------------------
{
ChNumber=$1
TagFormat="$2_"
LoopCount=0

# CreAvaFlagFile

> $ChannelStart
> $ChannelStop

while (( $LoopCount < $ChNumber ))
do
	let LoopCount=$LoopCount+1 
	ChannelConfAll="allocate channel c${LoopCount} type sbt PARMS=\"SBT_LIBRARY=${CH_SBT_LIBRARY} ENV=${CH_ENV}\" FORMAT='${TagFormat}${CH_FORMAT}' maxpiecesize ${MAXPIECESIZE};"
	ChannelConfSend="send channel='c${LoopCount}' '\"--flagfile=${AvaFlagFile}\" \"--bindir=${TAPE_bindir}\" \"--cacheprefix=${TAPE_cacheprefix}_c${LoopCount}\" ${expiresExpDateAvamar} \"--path=${TAPE_path}\"';"
#	ChannelConfSend="send channel='c${LoopCount}' '\"--flagfile=${TAPE_flagfile}\" \"--bindir=${TAPE_bindir}\" \"--logfile=${TAPE_logfile}\" \"--vardir=${TAPE_vardir}\" \"--cacheprefix=${TAPE_cacheprefix}_c${LoopCount}\" ${expiresExpDateAvamar} \"--path=${TAPE_path}\"';"
#	 ChannelConfSend="send channel='c${LoopCount}' '\"--flagfile=${TAPE_flagfile}\" \"--bindir=${TAPE_bindir}\" \"--logfile=${TAPE_logfile}\" \"--vardir=${TAPE_vardir}\" \"--cacheprefix=${TAPE_cacheprefix}_c${LoopCount}\" \"--expires=${ExpDateAvamar}\" \"--path=${TAPE_path}\"';"

	echo $ChannelConfAll >> $ChannelStart 
	echo $ChannelConfSend >> $ChannelStart 

	echo "release channel c${LoopCount};" >> $ChannelStop


done
}
#---------------------------------------------------------
SetChannelDup ()
#---------------------------------------------------------
{
ChNumber=$1
LoopCount=0

# Not used 
# IdentifyServer
DBTypeEvProd

# CreAvaFlagFile

TAPE_path=${MAIN_TAPE_path}/${TAPE_path_zone}/${DBType}/${ServerNameSource}

> $ChannelStart
> $ChannelStop

while (( $LoopCount < $ChNumber ))
do
        let LoopCount=$LoopCount+1
        ChannelConfAll="allocate auxiliary channel c${LoopCount} type sbt PARMS=\"SBT_LIBRARY=${CH_SBT_LIBRARY}\" send '\"--flagfile=${AvaFlagFile}\" \"--bindir=${TAPE_bindir}\" \"--cacheprefix=${TAPE_cacheprefix}_c${LoopCount}\" \"--path=${TAPE_path}\"';"
        # ChannelConfAll="allocate auxiliary channel c${LoopCount} type sbt PARMS=\"SBT_LIBRARY=${CH_SBT_LIBRARY}\" send '\"--flagfile=${TAPE_flagfile}\" \"--bindir=${TAPE_bindir}\" \"--logfile=${TAPE_logfile}\" \"--vardir=${TAPE_vardir}\" \"--cacheprefix=${TAPE_cacheprefix}_c${LoopCount}\" \"--path=${TAPE_path}\"';"

        echo $ChannelConfAll >> $ChannelStart

        echo "release channel c${LoopCount};" >> $ChannelStop


done
}
#---------------------------------------------------------
BackupSpfile ()
#---------------------------------------------------------
{
LogCons "Backup SP file."
LogCons "Script:$RmanExecFileSP"

DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileSP
SetChannel 1 ${MAIN_TAG}_${SpfileLabel}
echo "run {" >> $RmanExecFileSP
cat $ChannelStart >> $RmanExecFileSP
echo "backup spfile TAG ${MAIN_TAG}_${SpfileLabel};" >> $RmanExecFileSP
echo "change backupset TAG ${MAIN_TAG}_${SpfileLabel} keep until time '${KeepPeriode}';" >> $RmanExecFileSP
cat $ChannelStop >> $RmanExecFileSP
echo "}" >> $RmanExecFileSP
echo "exit;" >> $RmanExecFileSP
rman $ConnectString cmdfile=$RmanExecFileSP 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
GetIncarnation ()
#---------------------------------------------------------
{
LogCons "Getting the Incarnation Number."
LogCons "Script:$RmanExecFileGetInca"

echo "list INCARNATION;" > $RmanExecFileGetInca
echo "exit" >> $RmanExecFileGetInca
rman $ConnectString cmdfile=$RmanExecFileGetInca 2>&1 | tee $TmpLogFile | LogStdIn
CheckError

linecnt=`wc -l $TmpLogFile | awk '{print $1}'`

while [ $linecnt -ge 1 ]
do
	# LineContent=$(sed -n "$linecnt"p $TmpLogFile | grep -v "DB Key" | grep -v "ecovery" | grep -v "List of Database" | grep -v "\--" | grep -v -F  ">" | grep -v "Copyright" | grep -v "conn")
	LineContent=$(sed -n "$linecnt"p $TmpLogFile | grep -v "DB Key" | grep -v "ecovery" | grep -v "List of Database" | grep -v "\--" | grep -v -F  ">" | grep -v "Copyright" | grep -v "conn")
	if [[ ! -z "$LineContent" ]]
	then
		SCN_NUMBER_INCA=$(echo $LineContent | awk '{print $6}')
		INCA_NUMBER=$(echo $LineContent | awk '{print $2}')
#		LogCons "LINE: *$LineContent*"
#		LogCons "SCN_NUMBER_INCA: $SCN_NUMBER_INCA"
#		LogCons "INCA_NUMBER: $INCA_NUMBER"

		if [[ $SCN_NUMBER -gt $SCN_NUMBER_INCA  ]]
		then
			INCA_NUMBER_RESTORE=$INCA_NUMBER
			LogCons "Using Incarnation Number: $INCA_NUMBER_RESTORE"
			return
		fi
	fi
	linecnt=$(($linecnt - 1))
done

}
#---------------------------------------------------------
BackupContfile ()
#---------------------------------------------------------
{
LogCons "Backup Control file."
LogCons "Script:$RmanExecFileCONT"

DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileCONT
SetChannel 1 ${MAIN_TAG}_${ControlFileLabel}
echo "run {" >> $RmanExecFileCONT
cat $ChannelStart >> $RmanExecFileCONT
echo "backup current controlfile TAG ${MAIN_TAG}_${ControlFileLabel};" >> $RmanExecFileCONT
echo "change backupset TAG ${MAIN_TAG}_${ControlFileLabel} keep until time '${KeepPeriode}';" >> $RmanExecFileCONT
cat $ChannelStop >> $RmanExecFileCONT
echo "}" >> $RmanExecFileCONT
echo "exit;" >> $RmanExecFileCONT
rman $ConnectString cmdfile=$RmanExecFileCONT 2>&1 | tee $TmpLogFile | LogStdIn

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
# echo "CROSSCHECK BACKUP;" >> $RmanExecFileCrossCheck
echo "CROSSCHECK BACKUP DEVICE TYPE sbt;" >> $RmanExecFileCrossCheck
cat $ChannelStop >> $RmanExecFileCrossCheck
echo "}" >> $RmanExecFileCrossCheck
echo "exit;" >> $RmanExecFileCrossCheck
rman $ConnectString cmdfile=$RmanExecFileCrossCheck 2>&1 | tee $RmanExecFileCrossCheckLog | LogStdIn

CheckError

CrossCheckErr=$(grep "crosschecked backup piece: found to be " $RmanExecFileCrossCheckLog | grep -v AVAILABLE)

if [[ ! -z "$CrossCheckErr" ]]
then
	LogError "Error by Cross check. Check log file."
	LogError "Log file: $RmanExecFileCrossCheckLog"
	LogError "Backup pieces not in AVAILABLE status"
fi
}
#---------------------------------------------------------
BackupDatabase ()
#---------------------------------------------------------
{
LogCons "Backup Database."
LogCons "Script:$RmanExecFileDB"

SetChannel $CHANNELS ${MAIN_TAG}_${DbArchLabel}

DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileDB
echo "SQL \"ALTER SYSTEM ARCHIVE LOG CURRENT\";" >> $RmanExecFileDB
echo "run {" >> $RmanExecFileDB
cat $ChannelStart >> $RmanExecFileDB
echo "backup database filesperset $FILESPERSET TAG ${MAIN_TAG}_${DbArchLabel} PLUS ARCHIVELOG delete input TAG ${MAIN_TAG}_${DbArchLabel};" >> $RmanExecFileDB
echo "change backupset TAG ${MAIN_TAG}_${DbArchLabel} keep until time '${KeepPeriode}';" >> $RmanExecFileDB
cat $ChannelStop >> $RmanExecFileDB
echo "}" >> $RmanExecFileDB
echo "exit;" >> $RmanExecFileDB
rman $ConnectString cmdfile=$RmanExecFileDB 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
DuplicateDatabase ()
#---------------------------------------------------------
{
LogCons "Duplicate Database."
LogCons "Script:$RmanExecFileDuplicate"

ConnectString="auxiliary / CATALOG $DuplicateSourceSid/$RMAN_CONN@$RMAN_REPO"

SetChannelDup $CHANNELS

echo "run {" >> $RmanExecFileDuplicate
cat $ChannelStart >> $RmanExecFileDuplicate
echo "duplicate database $DuplicateSourceSid to $ORACLE_SID" >> $RmanExecFileDuplicate
echo "until scn $SCN_NUMBER" >> $RmanExecFileDuplicate
echo "db_file_name_convert '$OFA_DB_DATA/$DuplicateSourceSid','$OFA_DB_DATA/$ORACLE_SID'" >> $RmanExecFileDuplicate
echo "spfile" >> $RmanExecFileDuplicate
echo "parameter_value_convert '$DuplicateSourceSid','$ORACLE_SID'" >> $RmanExecFileDuplicate
echo "set log_file_name_convert '$DuplicateSourceSid','$ORACLE_SID';" >> $RmanExecFileDuplicate
echo "}" >> $RmanExecFileDuplicate

LogCons "Starting Duplicating the database....."

rman $ConnectString cmdfile=$RmanExecFileDuplicate 2>&1 | tee $TmpLogFile | LogStdIn

CheckError


}
#---------------------------------------------------------
RestoreDatabase ()
#---------------------------------------------------------
{
LogCons "Restore Database."
LogCons "Script:$RmanExecFileRestore"

SetChannel $CHANNELS


# Restore sp file
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore spfile from TAG=${TAG_RESTORE}_${SpfileLabel};" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "shutdown immediate;" >> $RmanExecFileRestore
echo "startup nomount;" >> $RmanExecFileRestore

# Restore control file
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore controlfile from TAG=${TAG_RESTORE}_${ControlFileLabel};" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "reset database to incarnation $INCA_NUMBER_RESTORE;" >> $RmanExecFileRestore

echo "alter database mount;" >> $RmanExecFileRestore


# Restore database
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore database until scn $SCN_NUMBER from TAG=${TAG_RESTORE}_${DbArchLabel};" >> $RmanExecFileRestore
echo "recover database until scn $SCN_NUMBER from TAG=${TAG_RESTORE}_${DbArchLabel};" >> $RmanExecFileRestore
echo "alter database open resetlogs;" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "exit;" >> $RmanExecFileRestore

rman $ConnectString cmdfile=$RmanExecFileRestore 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
RestoreDatabaseScn ()
#---------------------------------------------------------
{
Func=SUMMARY
SpFileTag=$(ExecBackupList SUMMARY | grep "_SPFILE" | tail -1 | awk '{print $11}') 
LogCons "spfile to restore: $SpFileTag"

LogCons "Restore Database until SCN $SCN_NUMBER"
LogCons "Script:$RmanExecFileRestore"

SetChannel $CHANNELS

echo "reset database to incarnation $INCA_NUMBER_RESTORE;" >> $RmanExecFileRestore

# Restore sp file
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore spfile from TAG=${SpFileTag};" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "shutdown immediate;" >> $RmanExecFileRestore
echo "startup nomount;" >> $RmanExecFileRestore

# Restore control file
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore controlfile;" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "alter database mount;" >> $RmanExecFileRestore


# Restore database
echo "run {" >> $RmanExecFileRestore
cat $ChannelStart >> $RmanExecFileRestore
echo "restore database until scn $SCN_NUMBER;" >> $RmanExecFileRestore
echo "recover database until scn $SCN_NUMBER;" >> $RmanExecFileRestore
echo "alter database open resetlogs;" >> $RmanExecFileRestore
cat $ChannelStop >> $RmanExecFileRestore
echo "}" >> $RmanExecFileRestore

echo "exit;" >> $RmanExecFileRestore

rman $ConnectString cmdfile=$RmanExecFileRestore 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
GetSCN ()
#---------------------------------------------------------
{
LogCons "Getting the SCN Number."
LogCons "Script:$RmanExecFileGetSCN"

ConnectStringOld=$ConnectString
ConnectString=$(echo ${ConnectString} | sed -e 's/TARGET \///g')

echo "connect target /" >> $RmanExecFileGetSCN
echo "list backup TAG=${TAG_RESTORE}_${DbArchLabel};" >> $RmanExecFileGetSCN
rman $ConnectString cmdfile=$RmanExecFileGetSCN 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

# Check if TAG exist
TagExist=$(grep "specification does not" $TmpLogFile)
if [[ ! -z "$TagExist" ]]
then
	LogError "TAG ${TAG_RESTORE}_${DbArchLabel} don't exist"
	exit 1
fi

ConnectString=$ConnectStringOld
SCN_NUMBER=$(grep -v "Recovery Manager complete" $TmpLogFile | sed '/^$/d' | tail -1 | awk '{print $6}')
let SCN_NUMBER=$SCN_NUMBER-1
LogCons "Restore until SCN number: $SCN_NUMBER"

}
#---------------------------------------------------------
BackupArch ()
#---------------------------------------------------------
{
LogCons "Backup Archive files."
LogCons "Script:$RmanExecFileArch"

SetChannel $CHANNELS ${MAIN_TAG}_${ArchLabel}

DoSqlQ "execute dbms_backup_restore.resetConfig;"

echo $RetentionPolicy > $RmanExecFileArch
# echo "SQL \"ALTER SYSTEM ARCHIVE LOG CURRENT\";" >> $RmanExecFileArch
echo "run {" >> $RmanExecFileArch
cat $ChannelStart >> $RmanExecFileArch
echo "backup ARCHIVELOG ALL delete input TAG ${MAIN_TAG}_${ArchLabel};" >> $RmanExecFileArch
echo "change backupset TAG ${MAIN_TAG}_${ArchLabel} keep until time '${KeepPeriode}';" >> $RmanExecFileArch
cat $ChannelStop >> $RmanExecFileArch
echo "}" >> $RmanExecFileArch
echo "exit;" >> $RmanExecFileArch
rman $ConnectString cmdfile=$RmanExecFileArch 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}

#---------------------------------------------------------
BackupValidate ()
#---------------------------------------------------------
{
LogCons "Backup Validate file."
LogCons "Script:$RmanExecFileValidate"

SetChannel $CHANNELS

echo "run {" >> $RmanExecFileValidate
cat $ChannelStart >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL spfile from TAG ${MAIN_TAG}_${SpfileLabel};" >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL controlfile from TAG ${MAIN_TAG}_${ControlFileLabel};" >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL DATABASE from TAG ${MAIN_TAG}_${DbArchLabel};" >> $RmanExecFileValidate
cat $ChannelStop >> $RmanExecFileValidate
echo "}" >> $RmanExecFileValidate
echo "exit;" >> $RmanExecFileValidate
rman $ConnectString cmdfile=$RmanExecFileValidate 2>&1 | tee $TmpLogFile | LogStdIn

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
# echo "restore VALIDATE CHECK LOGICAL ARCHIVELOG ALL from TAG ${MAIN_TAG}_${ArchLabel};" >> $RmanExecFileValidate
echo "restore VALIDATE CHECK LOGICAL controlfile from TAG ${MAIN_TAG}_${ControlFileLabel};" >> $RmanExecFileValidate
cat $ChannelStop >> $RmanExecFileValidate
echo "}" >> $RmanExecFileValidate
echo "exit;" >> $RmanExecFileValidate
rman $ConnectString cmdfile=$RmanExecFileValidate 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
DeleteObsolete ()
#---------------------------------------------------------
{
LogCons "Delete Obsolete Backups"
LogCons "Script:$RmanExecFileObsolete"

SetChannel $CHANNELS

echo "host 'echo \"******************************* List Before delete of Backup *******************************\"';" >> $RmanExecFileObsolete
echo "list backup summary;" >> $RmanExecFileObsolete
echo "run {" >> $RmanExecFileObsolete
cat $ChannelStart >> $RmanExecFileObsolete
echo "delete noprompt obsolete;" >> $RmanExecFileObsolete
cat $ChannelStop >> $RmanExecFileObsolete
echo "}" >> $RmanExecFileObsolete
echo "host 'echo \"******************************* List After delete of Backup *******************************\"';" >> $RmanExecFileObsolete
echo "list backup summary;" >> $RmanExecFileObsolete
echo "exit;" >> $RmanExecFileObsolete
rman $ConnectString cmdfile=$RmanExecFileObsolete 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
ArchCrossCheck ()
#---------------------------------------------------------
{
LogCons "Cross check archive logs"
LogCons "Script: $RmanExecCrossArch"
echo "crosscheck archivelog all;" >> $RmanExecCrossArch
echo "exit;" >> $RmanExecCrossArch
rman $ConnectString cmdfile=$RmanExecCrossArch 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

}
#---------------------------------------------------------
RunCommand ()
#---------------------------------------------------------
{
LogCons "Running RMAN command: $RmanCommand "
LogCons "Script: $RmanExecRmanCommand"

SetChannel $CHANNELS

echo "run {" >> $RmanExecRmanCommand
cat $ChannelStart >> $RmanExecRmanCommand
echo "$RmanCommand" >> $RmanExecRmanCommand
cat $ChannelStop >> $RmanExecRmanCommand
echo "}" >> $RmanExecRmanCommand
echo "exit;" >> $RmanExecRmanCommand
rman $ConnectString cmdfile=$RmanExecRmanCommand 2>&1 | tee $TmpLogFile

CheckError

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

echo "$ListCommand" >> $RmanExecFileList
echo "exit;" >> $RmanExecFileList
rman $ConnectString cmdfile=$RmanExecFileList 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

cat $TmpLogFile

}
#---------------------------------------------------------
CheckAvamarPath ()
#---------------------------------------------------------
{
ServerName=$1
DBName=$2
DBTypeEvProd
# not used
# IdentifyServer

AvmarPath=${MAIN_TAPE_path}/${TAPE_path_zone}/${DBType}/${ServerName}

LogCons "Check Avamer PATH $AvmarPath"
avtar \
--backups \
--flagfile=${TAPE_flagfile} \
--bindir=${TAPE_bindir} \
--vardir=${TAPE_vardir} \
--path=${AvmarPath} 2>&1 | tee $TmpLogFile | LogStdIn 
# --path=${MAIN_TAPE_path}/${TAPE_path_zone}/${ServerName}_${DBName} 2>&1 | tee $TmpLogFile | LogStdIn 

ExecError=$(grep "Error"  $TmpLogFile | head -1)

if [[ ! -z "$ExecError" ]]
then
        LogError "Error: $ExecError"
        LogError "Log file: $TmpLogFile"
        exit 1
fi

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
		LogError "Check AVAMAR Log file: $TAPE_logfile"
	fi
        exit 1
fi
}
#---------------------------------------------------------
RestartNomount ()
#---------------------------------------------------------
{
LogCons "Restart the database in $ORACLE_SID in nomount mode."
export ORA_RMAN_SGA_TARGET=1024
DoSql "shutdown abort;" >/dev/null 2>&1
rman << ___EOF > $TmpLogFile 2>&1
connect target /;
startup nomount;
exit;
___EOF

StartError=$(grep RMAN- $TmpLogFile)
if [[ ! -z "$StartError" ]]
then
	LogError "ERROR: Starting Datebase "STARTUP NOMOUNT""
	LogError "Log file: $TmpLogFile"
	exit 1
fi
}
#---------------------------------------------------------
CreAvaFlagFile ()
#---------------------------------------------------------
{
LogCons "Create Avamar flagfile: $AvaFlagFile"
cat $TAPE_flagfile | grep -v "#" > $AvaFlagFile
echo "--logfile=${TAPE_logfile}" >> $AvaFlagFile
echo "--vardir=${TAPE_vardir}" >> $AvaFlagFile
# echo "--path=${TAPE_path}" >> $AvaFlagFile
}
#---------------------------------------------------------
RestartNomountClone ()
#---------------------------------------------------------
{
LogCons "Restart the database in $ORACLE_SID in nomount clone mode."
export ORA_RMAN_SGA_TARGET=1024
DoSql "shutdown abort;" >/dev/null 2>&1
rman << ___EOF > $TmpLogFile 2>&1
connect auxiliary /;
startup clone nomount;
exit;
___EOF

StartError=$(grep RMAN- $TmpLogFile)
if [[ ! -z "$StartError" ]]
then
        LogError "ERROR: Starting Datebase "STARTUP NOMOUNT""
        LogError "Log file: $TmpLogFile"
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
        CheckConnRepo
 	BackupList
}
#---------------------------------------------------------
# Main 
#---------------------------------------------------------

CreAvaFlagFile

if [[ "$Function" == "BACKUP_FULL" ]] 
then
	Tag=$3
	LogCons "Running FULL databace backup"
  	#
  	# Check var
  	#
  	LogCons "Checking variables for BACKUP_FULL."
  	CheckVar                              \
        	Tag                        \
  	&& LogCons "Variables OK!"    \
  	|| Usage
	SetTag
	SetTapePath
	CheckConnRepo
	BackupSpfile
	BackupDatabase
	BackupContfile
	BackupValidate
	BackupCrossCheck
	DeleteObsolete
	exit $ExitCode
elif [[ "$Function" == "BACKUP_ARCH" ]]
then
        Tag=$3
        LogCons "Running Archive file backup"
        #
        # Check var
        #
        LogCons "Checking variables for BACKUP_FULL."
        CheckVar                              \
                Tag                        \
        && LogCons "Variables OK!"    \
        || Usage
        SetTag
        SetTapePath
        CheckConnRepo
	BackupArch
	BackupContfile
	BackupValidateArch
#------------- RESTORE_FULL -------------
elif [[ "$Function" == "RESTORE_FULL" ]]
then
        Tag=$3
        LogCons "Running FULL RESTORE of database. "
        #
        # Check var
        #
        LogCons "Checking variables for FULL_RESTORE."
        CheckVar                              \
                Tag                        \
        && LogCons "Variables OK!"    \
        || Usage
	

	

	TAG_RESTORE=$(echo $Tag | sed s/_${DbArchLabel}//g)
	SetTapePath
	RestartNomount
	CheckConnRepo
	GetSCN
	GetIncarnation
	LogCons "Deleting the old database: $ORACLE_SID"
	LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
	LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
	LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
	DoSql "shutdown abort" > /dev/null 2>&1
	rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
	rm $ORACLE_HOME/dbs/*$ORACLE_SID* > /dev/null 2>&1
	rm $OFA_DB_ARCH/$ORACLE_SID/* > /dev/null 2>&1

	RestartNomount
	RestoreDatabase
#------------- DUPLICATE_DB -------------
elif [[ "$Function" == "DUPLICATE_DB" ]]
then
	DuplicateSourceSid=$3
	ServerNameSource=$4
        Tag=$5
        LogCons "Running DUPLICATE of database, Source SID: $DuplicateSourceSid Target SID: $Database."
        #
        # Check var
        #
        LogCons "Checking variables for DUPLICATE_DB."
        CheckVar                     \
                DuplicateSourceSid   \
                ServerNameSource     \
        && LogCons "Variables OK!"   \
        || Usage
	CheckAvamarPath $ServerNameSource $DuplicateSourceSid
	SetTapePath
	RestartNomountClone
	GetLastTAG
	if [[ -z "$Tag" ]]
	then
		Tag=$LastBackup 
		LogCons "Duplicate last backup, TAG: $Tag"
	fi
	TAG_RESTORE=$(echo $Tag | sed s/_${DbArchLabel}//g)
	GetSCN
        LogCons "Deleting the old database: $ORACLE_SID"
        LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
        LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
        LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
        DoSql "shutdown abort" > /dev/null 2>&1
        rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
        rm $ORACLE_HOME/dbs/*$ORACLE_SID* > /dev/null 2>&1
        rm $OFA_DB_ARCH/$ORACLE_SID/* > /dev/null 2>&1
	RestartNomountClone
	DuplicateDatabase


#------------- RESTORE_SCN -------------
elif [[ "$Function" == "RESTORE_SCN" ]]
then
	SCN_NUMBER=$3

        LogCons "Running FULL RESTORE until SCN number: $SCN_NUMBER ."
        LogCons "Checking variables for RESTORE_SCN."
        CheckVar                              \
                SCN_NUMBER                        \
        && LogCons "Variables OK!"    \
        || Usage
        SetTapePath
        RestartNomount
        CheckConnRepo
        GetIncarnation
        LogCons "Deleting the old database: $ORACLE_SID"
        LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
        LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
        LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
        DoSql "shutdown abort" > /dev/null 2>&1
        rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
        rm $ORACLE_HOME/dbs/*$ORACLE_SID* > /dev/null 2>&1
        rm $OFA_DB_ARCH/$ORACLE_SID/* > /dev/null 2>&1

        RestartNomount
	RestoreDatabaseScn


#------------- BACKUP_LIST -------------
elif [[  "$Function" == "BACKUP_LIST" ]]
then
	ExecBackupList $3 $4
#------------- CROSS_CHK_ARCH -------------
elif [[  "$Function" == "CROSS_CHK_ARCH" ]]
then
	CheckConnRepo
	ArchCrossCheck
#------------- RUN_COMMAND -------------
elif [[  "$Function" == "RUN_COMMAND" ]]
then
	RmanCommand=$3
        CheckVar                     \
        RmanCommand                   \
        && LogCons "Variables OK!"   \
        || Usage

	CheckConnRepo
	SetTapePath
	RunCommand
else
	LogError "Wrong FUNCTION! Function: $Function"
	Usage
	exit 1
fi
