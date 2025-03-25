#!/bin/ksh -p
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: rman_tape_duplicate.sh [DESTINATION_DB_SID]  [FUNCTION]  [SOURCE_DB_SID] <FUNCTIONS PARAMATERS>
##
## Paramaters:
## SID:         SID of the database to backup
##
## FUNCTION:
##
##              DUPLICATE_DB
##                Duplicate the database, restore DB with an other name.
##              Parameter:
##                TAG=<TAG NAME> Name of the TAG to restore e.g DBAEV10_FU_DAYS40_241104_1613.
##                if TYPE=Default or Last parameter is NOT used.
##                
##                 CHANNELS=<16> Number of channel tp perform the duplicate
##                Default channel will be 8
##              
##                UNTIL_TIME : FORMAT DD-MM-YYYY-HH24i:MM:SS
##                With date format e.g UNTIL_TIME=30-11-2024-12:00:00
##              Remark:
##                      If no TAG duplicating the latest backup.
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
DbArchLabel=AR
AllParameters=$*

RmanConfFile=$OFA_ETC/rman_tape_duplicate/rman_tape_duplicate.defaults
TmpLogFile=$OFA_LOG/tmp/rman_tape_duplicate.tmp.$$.$PPID.$TimeStamp.log
TmpLogFiles=$OFA_LOG/tmp/rman_tape_duplicate.tmp.$$.$PPID.$TimeStamp.logs
CheckConnRepoLogFile=$OFA_LOG/tmp/rman_tape_duplicate.CheckConnRepo.$$.$PPID.$TimeStamp.log
ChannelStart=$OFA_LOG/tmp/rman_tape_duplicate.ChannelStart.$$.$PPID.$TimeStamp.txt
ChannelStop=$OFA_LOG/tmp/rman_tape_duplicate.ChannelStop.$$.$PPID.$TimeStamp.txt
RmanExecFileGetSCN=$OFA_LOG/tmp/rman_tape_duplicate.RmanExecFileGetSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileGetInca=$OFA_LOG/tmp/rman_tape_duplicate.RmanExecFileGetIncaSCN.$$.$PPID.$TimeStamp.rman
RmanExecFileList=$OFA_LOG/tmp/rman_tape_duplicate.RmanExecFileList.$$.$PPID.$TimeStamp.rman
RmanExecRmanGetTheTAGToRestore=$OFA_LOG/tmp/rman_tape_duplicate.RmanExecRmanGetTheTAGToRestore.$$.$PPID.$TimeStamp.rman
RmanExecFileDuplicate=$OFA_LOG/tmp/rman_tape_duplicate.RmanExecFileDuplicate.$$.$PPID.$TimeStamp.rman
TnsPingLog=$OFA_LOG/tmp/rman_tape_duplicate.TnsPingLog.$$.$PPID.$TimeStamp.log
RmanExecRestoreSpf=$OFA_LOG/tmp/rman_tape_restore_bkp.RmanExecRestoreSpf.$$.$PPID.$TimeStamp.rman
InitfileLocation=$ORACLE_HOME/dbs/init${ORACLE_SID}.ora


export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$TAPE_LIBRARY_PATH
RetentionPolicy="CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${RECOVERY_WINDOW_DAYS} DAYS;"

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
         LogCons "We can't duplicate PRD database  ($ORACLE_SID)."
        exit 1

else
        DBType=$EVX_TAPE
fi
LogCons "Database: $ORACLE_SID Type: $DBType"
}
#---------------------------------------------------------
SetTapePath ()
#---------------------------------------------------------
{
DBTypeEvProd
DBHostName=$(echo ${ORACLE_SID}-vip |tr "[:upper:]" "[:lower:]")

TAPE_path="${MAIN_TAPE_path}/${TAPE_path_zone}/${DBType}/${DBHostName}"

LogCons "Setting TAPE PATH=$TAPE_path"

}
#------------------------------------------------
SetRMAN_NAME_REPO ()
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
                RMAN_NAME_REPO=$i
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
}

#---------------------------------------------------------
CheckConnRepo ()
#---------------------------------------------------------
{
SetRMAN_NAME_REPO

LogCons "Checking connection to RMAN repository and resync catalog. (${RMAN_NAME_REPO})"
LogCons "Log file: $CheckConnRepoLogFile"

rman TARGET / CATALOG $DBSourceSID/$CAT_CONN_STRING << ___EOF > $CheckConnRepoLogFile 2>&1
RESYNC CATALOG;
exit
___EOF

if [[ $? -ne 0 ]]
then
        OFA_CONS_VOL_OLD=$OFA_CONS_VOL
        export OFA_CONS_VOL=1

        LogWarning "Error connecting to RMAN repository $ORACLE_SID/<password>@${RMAN_NAME_REPO}"

        LogWarning "Log file: $CheckConnRepoLogFile"
        LogWarning "Using control file instead of RMAN repository !!!!"
        ConnectString="TARGET /"
        LogCons "Connect command: rman $ConnectString"

        OFA_CONS_VOL=$OFA_CONS_VOL_OLD
        export OFA_CONS_VOL
        ExitCode=50
else
        LogCons "Check RMAN repository connection, connection OK"
        LogCons "Connect command: rman TARGET / CATALOG $ORACLE_SID/xxxxxxxxxx@$RMAN_NAME_REPO"
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

#---------------------------------------------------------
GetSourceDBID ()
#---------------------------------------------------------
{
LogCons "Getting the database Source DBID  from RMAN repository"
QUERY="select  DBID from RC_DATABASE_INCARNATION where name='$DBSourceSID' order by RESETLOGS_TIME desc FETCH FIRST 1 ROWS ONLY;"
RESULT=$(sqlplus -S $DBSourceSID/${RMAN_CONN}@${RMAN_NAME_REPO}  <<EOF
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

unset TagParameter

LogCons "Checking connection to RMAN repository and Source database list"
LogCons "Script: $RmanExecRmanGetTheTAGToRestore"

LogCons "Connect String: CATALOG $RMAN_CONN_USER/xxxxxxxxxx@$RMAN_NAME_REPO"

echo "set dbid $SourceDBID" > $RmanExecRmanGetTheTAGToRestore
echo "list backup summary ;" >> $RmanExecRmanGetTheTAGToRestore

rman CATALOG $DBSourceSID/$CAT_CONN_STRING cmdfile=$RmanExecRmanGetTheTAGToRestore 2>&1 | tee $TmpLogFiles | LogStdIn

TagParameter=$(echo $AllParameters |  awk -F'TAG=' '{print $2}' | awk '{print $1}')

if [[ ! -z $TagParameter ]]
then
 TAG_RESTORE=$(cat $TmpLogFiles | grep $TagParameter | grep -v ${DBSourceSID}_CT |  grep -v ${DBSourceSID}_SP | grep -v ${DBSourceSID}_AR | tail -1 | awk '{print $NF}' )
 LogCons "The backup TAG: $TAG_RESTORE"

else
    
 TAG_RESTORE=$(cat $TmpLogFiles | grep $DBSourceSID | grep -v ${DBSourceSID}_CT |  grep -v ${DBSourceSID}_SP | grep -v ${DBSourceSID}_AR | tail -1 | awk '{print $NF}')
 LogCons "TAG no provided the last backup will be used"
 LogCons "Last backup TAG: $TAG_RESTORE"

fi
}
#---------------------------------------------------------
SetChannelDup ()
#---------------------------------------------------------
{
ChNumber=$1
LoopCount=0

DBTypeEvProd

TAPE_path=${MAIN_TAPE_path}/${TAPE_path_zone}/${DBType}/${DBSourceSID}-VIP

> $ChannelStart
> $ChannelStop

while (( $LoopCount < $ChNumber ))
do
        let LoopCount=$LoopCount+1
        ChannelConfAll="allocate auxiliary channel c${LoopCount} type sbt PARMS='ENV=(NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SERV=$NB_ORA_SERV, NB_ORA_CLIENT=${DBSourceSID}-vip.corp.ubp.ch)';"
        echo $ChannelConfAll >> $ChannelStart

        echo "release channel c${LoopCount};" >> $ChannelStop

done
}

#---------------------------------------------------------
DuplicateDatabase ()
#---------------------------------------------------------.
{
DoSqlQ "startup force nomount;"
LogCons "Duplicate Database."
LogCons "Script:$RmanExecFileDuplicate"
SetChannelDup $CHANNELS

echo "run {" >> $RmanExecFileDuplicate
echo "Set archivelog destination to '$OFA_DB_ARCH/$ORACLE_SID';" >> $RmanExecFileDuplicate
cat $ChannelStart >> $RmanExecFileDuplicate
echo "set dbid $SourceDBID;" >> $RmanExecFileDuplicate
echo "duplicate database  to $ORACLE_SID" >> $RmanExecFileDuplicate
echo "$DuplicateType " >> $RmanExecFileDuplicate
echo "nofilenamecheck;" >> $RmanExecFileDuplicate
echo "}" >> $RmanExecFileDuplicate
LogCons "Starting Duplicating the database....."
rman auxiliary / CATALOG $DBSourceSID/$CAT_CONN_STRING cmdfile=$RmanExecFileDuplicate 2>&1 | tee $TmpLogFile | LogStdIn

if [ $? -ne 0 ]; then
    echo "RMAN command failed. Exiting."
    exit 1
fi


}
#---------------------------------------------------------
GetSCN ()
#---------------------------------------------------------
{
LogCons "Getting the SCN Number."
LogCons "Script:$RmanExecFileGetSCN"


echo "set dbid $SourceDBID " > $RmanExecFileGetSCN
echo "list backup TAG=$TAG_RESTORE;" >> $RmanExecFileGetSCN
rman CATALOG  $DBSourceSID/$CAT_CONN_STRING cmdfile=$RmanExecFileGetSCN 2>&1 | tee $TmpLogFile | LogStdIn

CheckError

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
RestoreSpfile ()
#---------------------------------------------------------
{
LogCons "Spfile Database."
LogCons "Script:$RmanExecRestoreSpf"
DoSqlQ "startup force nomount;" 

echo "run {" >> $RmanExecRestoreSpf
echo "allocate channel c1 type sbt PARMS='ENV=(NB_ORA_POLICY=$NB_ORA_POLICY, NB_ORA_SERV=$NB_ORA_SERV, NB_ORA_CLIENT=${DBSourceSID}-vip.corp.ubp.ch)';" >> $RmanExecRestoreSpf
echo "set dbid $SourceDBID " >> $RmanExecRestoreSpf
echo "restore spfile to '$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora';" >> $RmanExecRestoreSpf
echo "sql \"create pfile=''$OFA_DB_BKP/$ORACLE_SID/rman/init${ORACLE_SID}.ora'' from spfile=''$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora''\";" >> $RmanExecRestoreSpf
echo "sql \"create pfile=''$ORACLE_HOME/dbs/init${ORACLE_SID}.ora'' from spfile=''$OFA_DB_BKP/$ORACLE_SID/rman/spfile${ORACLE_SID}.ora''\";" >> $RmanExecRestoreSpf
echo "}" >> $RmanExecRestoreSpf
echo "exit;" >> $RmanExecRestoreSpf
rman TARGET / CATALOG $DBSourceSID/$CAT_CONN_STRING cmdfile=$RmanExecRestoreSpf 2>&1 | tee $TmpLogFile | LogStdIn

SetInit

CheckError

LogCons "Spfile restored and pfile created in $OFA_DB_BKP/$ORACLE_SID/rman/"

}

#---------------------------------------------------------
SetInit ()
#---------------------------------------------------------
{
DoSqlQ "shutdown abort;" >/dev/null 2>&1
if [ -f "$ORACLE_HOME/dbs/init${ORACLE_SID}.ora" ] ; then
        InitFileBck=$ORACLE_HOME/dbs/init${ORACLE_SID}.ora
        LogCons "Init file $ORACLE_HOME/dbs/init${ORACLE_SID}.ora used"
elif [ -f "/backup/${ORACLE_SID}/rman/init${ORACLE_SID}.ora" ] ; then
        InitFileBck=/backup/${ORACLE_SID}/rman/init${ORACLE_SID}.ora
        LogInfo "Init file /backup/${ORACLE_SID}/rman/init${ORACLE_SID}.ora used"
else
        BailOut "No init file found."
fi

if [ ! -f "$InitFileBck" ] ; then
        LogError "Source init.ora file: $InitFileBck  missing"
        exit 1
fi

cat $InitFileBck | grep -vi "db_file_name_convert" | grep -vi "log_file_name_convert" | sed "s/$DBSourceSID/$ORACLE_SID/g" > $InitFileBck.tmp


InitTemplateDB=/ofa/local/oracle/script/refresh/${ORACLE_SID}/init${ORACLE_SID}.ora

if [[ ! -r ${InitTemplateDB} ]]
then
        LogError "init refresh file missing: ${InitTemplateDB}"
        exit 1
fi

grep -v '^$'  ${InitTemplateDB} > ${InitTemplateDB}.temp
mv ${InitTemplateDB}.temp ${InitTemplateDB}

tempRemoveLine="/tmp/RemoveLine"

rm -rf $tempRemoveLine
touch $tempRemoveLine

if [ -f $InitTemplateDB ] ; then
        LogInfo "Init template file exist. File: $InitTemplateDB"

        while read line
        do
                ParameterName=$(echo "$line" | awk -F "=" '{print $1}' | awk -F "." '{print $2}')
                LogInfo "$ParameterName" >> $tempRemoveLine
                LogInfo "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
                LogInfo "Paramater Value: $line"
                LogCons "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
                LogCons "Paramater Value: $line"
        done < "$InitTemplateDB"

        grep -v -i -f $tempRemoveLine $InitFileBck.tmp > $InitFileBck.new
        cat ${InitTemplateDB} >> $InitFileBck.new
else
        cat $InitFileBck.tmp > $InitFileBck.new
fi

echo "*.db_file_name_convert='${OFA_DB_DATA}/${DBSourceSID}/','${OFA_DB_DATA}/${ORACLE_SID}/','$OFA_DB_DATA/${DBSourceSID}_PDB/','$OFA_DB_DATA/${ORACLE_SID}_PDB/'" >> $InitFileBck.new
echo "*.log_file_name_convert='${OFA_DB_DATA}/${DBSourceSID}/','${OFA_DB_DATA}/${ORACLE_SID}/','$OFA_DB_ARCH/${DBSourceSID}/','$OFA_DB_ARCH/${ORACLE_SID}/'" >> $InitFileBck.new

cat $InitFileBck.new | grep -v "${ORACLE_SID}.__" > $InitFileBck.new.01

cp $InitFileBck.new.01 $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
cp $InitFileBck.new.01 /backup/${ORACLE_SID}/rman/init${ORACLE_SID}.ora

mv $InitFileBck.new.01  $InitFileBck.${TimeStamp}
rm  $InitFileBck.new 
rm  $InitFileBck.tmp 
DoSqlQ "CREATE spfile from pfile='$ORACLE_HOME/dbs/init${ORACLE_SID}.ora';"
RestartNomount

}
#---------------------------------------------------------
GenerateInitFile ()
#---------------------------------------------------------
{
LogCons "Generate init file before spfile restore"
DoSqlQ "shutdown abort;" >/dev/null 2>&1 
rm -f "$ORACLE_HOME/dbs/init${ORACLE_SID}.ora" > /dev/null 2>&1
rm -f "$ORACLE_HOME/dbs/spfile${ORACLE_SID}.ora" > /dev/null 2>&1
echo "db_name='${ORACLE_SID}'"> $InitfileLocation
echo "memory_target=4G">> $InitfileLocation
echo "processes = 150" >> $InitfileLocation
echo "audit_file_dest='/dbvar/$ORACLE_SID/log/adump'" >> $InitfileLocation
echo "db_block_size=8192">> $InitfileLocation
echo "control_files ='/DB/${ORACLE_SID}/control01.ctl','/DB/${ORACLE_SID}/control02.ctl'">> $InitfileLocation
DoSqlQ "startup nomount pfile='$InitfileLocation';" >/dev/null 2>&1
DoSqlQ "create spfile from pfile='$InitfileLocation';" >/dev/null 2>&1
DoSqlQ "startup force nomount;" 
LogCons "Target database started in Nomount "

}
#---------------------------------------------------------
RestartNomount ()
#---------------------------------------------------------
{
LogCons "Restart the database in $ORACLE_SID in nomount mode."
DoSqlQ "shutdown abort;" >/dev/null 2>&1
DoSqlQ "startup nomount;" >/dev/null 2>&1

LogCons "Target DB restarted."

}

#---------------------------------------------------------
# Main
#---------------------------------------------------------

IdentifyServer
CheckNBKSymlink
GetMediaServer

#------------- DUPLICATE_DB -------------
if [[ "$Function" == "DUPLICATE_DB" ]]
then
        DBSourceSID="$3"
        RESTORE_TO_DATE=$(echo $AllParameters |  awk -F'UNTIL_TIME=' '{print $2}' | awk '{print $1}')
        LogCons "Running DUPLICATE of database, Source SID: $DBSourceSID Target SID: $Database."
        #
        # Check var
        #
        LogCons "Checking variables for DUPLICATE_DB."
        CheckVar             \
                DBSourceSID   \
        && LogCons "Variables OK!"   \
        || Usage
        SetTapePath
        RestartNomount
        GenerateInitFile
        GetSourceDBID
        SetNumChannels
        RestoreSpfile
        if [[ -z $RESTORE_TO_DATE ]];then
        GetTheTAGToRestore
        GetSCN
        DuplicateType="until scn $SCN_NUMBER"
        else
        LogCons "Parameter UNTIL TIME Provided, the duplicate will be done until: $RESTORE_TO_DATE ...."
        DuplicateType="until time \"to_date('${RESTORE_TO_DATE}', 'DD-MM-YYYY-HH24:MI:SS')\""
        fi
        LogCons "Deleting the old database: $ORACLE_SID"
        LogCons "$OFA_DB_DATA/$ORACLE_SID/*"
        LogCons "$ORACLE_HOME/dbs/*$ORACLE_SID*"
        LogCons "$OFA_DB_ARCH/$ORACLE_SID/*"
        DoSql "shutdown abort" > /dev/null 2>&1
        rm $OFA_DB_DATA/$ORACLE_SID/* > /dev/null 2>&1
        rm -f "$OFA_DB_DATA/${ORACLE_SID}_PDB/*"
        DuplicateDatabase


else
        LogError "Wrong FUNCTION! Function: $Function"
        Usage
        exit 1
fi
  
