#!/bin/ksh 

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: rman_restore_bkp  [FUNCTION] [SID] [see function]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##
## Function:            Parameters:
##
## Info                 [SID] Database name
##                      List first and last SCN/DATE 
##
## Restore              [SID] Database name
##                      Database name to restore
##
##                      [TYPE]  (Type of until patameter used.)
##			SCN 
##			Date
##			Default (The "base" backup image will be restored.)
##			Last    (Restore until last archive file.)
##
##                      [UNTIL] 
##                      restore until SCN number
##			or 
##			Date (format: YYYY-MM-DD_HH24:MI:SS)
##			if TYPE=Default or Last parameter is NOT used.
##
#
__EOF
exit 1
}
#---------------------------------------------



FuncToDo=$1
SID=$2
TimeStamp=$(date +"%Y%m%d_%H%M%S")
TmpLogFile=$OFA_LOG/tmp/rman_restore_bkp.sh.tmp.$$.$PPID.$TimeStamp.log
SqlLogFile=$OFA_LOG/tmp/rman_restore_bkp.sh.sql.$$.$PPID.$TimeStamp.log
FileListInf=$OFA_LOG/tmp/rman_restore_bkp.FileListInf.$$.$PPID.$TimeStamp.log
FileListLog=$OFA_LOG/tmp/rman_restore_bkp.FileListLog.$$.$PPID.$TimeStamp.log
ServerNameCheck=$(hostname | grep -i prd)
# ServerNameCheck=$(hostname)
ServerName=$(hostname)
DatabaseNameCheck=$(echo $SID | grep -i prd)
# DatabaseNameCheck=$SID
BackupDir=${OFA_DB_BKP}/${SID}/rman

    LogIt "Check variable completeness"
    CheckVar                       \
        SID                        \
        FuncToDo                   \
     && LogIt "Variables complete" \
     || usage

        OraEnv $SID 2>&1 >/dev/null
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                # VolUp 1
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

ExecRestoreFile=$(ls -rt ${BackupDir}/RUNFILE_RECO_${SID}*.rcv | tail -1 2>&1 >/dev/null)

if [[ $? -eq 0  ]]
then
	ExecRestoreFile=$(ls -rt ${BackupDir}/RUNFILE_RECO_${SID}*.rcv | tail -1)
	LogCons "Using restore file: $ExecRestoreFile"
else
	LogError "Restore file: ${BackupDir}/RUNFILE_RECO_${SID}*.rcv DON'T exist"
	exit 1
fi

#---------------------------------------------
FindScnDate ()
#---------------------------------------------
{
# set -xv
LastBackInfFile=$(ls -1rt ${BackupDir}/*.inf 2>&1 | tail -1)
FirstBackInfFile=$(ls -1rt ${BackupDir}/*.inf 2>&1 | head -1)
LastControlFile=$(ls -1rt ${BackupDir}/bck_control_file_c-*.ctl 2>&1 | tail -1 | awk -F "/" '{print $NF}')
FirstControlFile=$(ls -1rt ${BackupDir}/bck_control_file_c-*.ctl 2>&1 | head -1 | awk -F "/" '{print $NF}')

Errro=$(echo $FirstBackInfFile $LastBackInfFile $FirstControlFile $LastControlFile | grep "No such file or directory")
if [[ ! -z $Errro ]]
then
	LogError "*.log or *.inf files missing in ${BackupDir}"
	exit 1
fi


LogCons "First info file:   $FirstBackInfFile"
LogCons "Last info file:    $LastBackInfFile"
LogCons "First control file: $FirstControlFile"
LogCons "Last control file: $LastControlFile"


# FirstSCN=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
#       $FirstBackInfFile \
#       | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | head -1 | awk '{print $5}')

# FirstSCN=$(grep "Control File Included: Ckp SCN:" $FirstBackInfFile | awk '{print $6}' | sort | head -1) 

FirstSCN=$(grep "Recovery must be done beyond SCN" $FirstBackInfFile | awk '{print $7}' | sort | head -1) 

LastSCN=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
      $LastBackInfFile \
      | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | tail -1 | awk '{print $5}')
let LastSCN=$LastSCN-1

# LastSCN=$(grep "Control File Included: Ckp SCN:" $LastBackInfFile | awk '{print $6}' | sort | tail -1)

# FirstDate=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
#      $FirstBackInfFile \
#      | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | head -1 | awk '{print $6}')

# FirstDate=$(grep "Control File Included: Ckp SCN:" $FirstBackInfFile | awk '{print $9}' | sort | head -1)
##
# FirstDate=$(grep ${FirstSCN} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | head -1 | awk '{print $6}')

FirstDate=$(grep ${FirstSCN} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | head -1 | awk -F "${FirstSCN}" '{print $2}' | awk '{print $1}')

LastDate=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
      $LastBackInfFile \
      | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | tail -1 | awk '{print $6}')

# LastDate=$(grep "Control File Included: Ckp SCN:" $LastBackInfFile | awk '{print $9}' | sort | tail -1)


DefaultScn=$(grep "until scn" $ExecRestoreFile | awk '{print $NF}' | sed 's/;//')
DefaultDate=$(grep ${DefaultScn} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | awk '{print $NF}' | tail -1 )
# DefaultDate=$(grep ${DefaultScn} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | tail -1 | awk -F "${DefaultScn}" '{print $2}' | awk '{print $1}' )



# DefaultDate=$(grep ${DefaultScn} ${FirstBackInfFile} | awk '{print $9}')
# DefaultDate=$(grep "Control File Included: Ckp SCN: ${DefaultScn}" ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | awk '{print $NF}')
UntilText=$(grep "until scn" $ExecRestoreFile | awk 'sub(/^ */, "")')
ControlText=$(grep "restore controlfile from" $ExecRestoreFile | awk 'sub(/^ */, "")')


LogCons "Default SCN Number: $DefaultScn"
LogCons "Default Date: $DefaultDate"
LogCons "First SCN Number: $FirstSCN"
LogCons "First Date: $FirstDate"
LogCons "Last SCN Number: $LastSCN"
LogCons "Last Date: $LastDate"
}
#---------------------------------------------
FindScnDateAll ()
#---------------------------------------------
{
# set -xv
ls -1 ${BackupDir}/rman_*.inf > $FileListInf
ls -1 ${BackupDir}/rman_*.log > $FileListLog

# LastBackInfFile=$(ls -1rt ${BackupDir}/*.inf 2>&1 | tail -1)
LastBackInfFile=$(cat $FileListInf | tail -1)

# FirstBackInfFile=$(ls -1rt ${BackupDir}/*.inf 2>&1 | head -1)
FirstBackInfFile=$(cat $FileListInf | head -1)

LastControlFile=$(ls -1 ${BackupDir}/bck_control_file_c-*.ctl 2>&1 | tail -1 | awk -F "/" '{print $NF}')
FirstControlFile=$(ls -1 ${BackupDir}/bck_control_file_c-*.ctl 2>&1 | head -1 | awk -F "/" '{print $NF}')

Error=$(echo $FirstBackInfFile $LastBackInfFile $FirstControlFile $LastControlFile | grep "No such file or directory")
# echo "*$Error*"
if [[ ! -z $Error ]]
then
        LogError "*.log or *.inf files missing in ${BackupDir}"
        exit 1
fi



LogCons "First info file:   $FirstBackInfFile"
LogCons "Last info file:    $LastBackInfFile"
LogCons "First control file: $FirstControlFile"
LogCons "Last control file: $LastControlFile"

AllBackInfFile=$(ls -1rt ${BackupDir}/*.inf)
AllBackLogFile=$(ls -1rt ${BackupDir}/rman_hot*.log)

AllBackInfBac=$(ls -1rt ${BackupDir}/*.inf ${BackupDir}/rman_hot*.log | sed 'N;s/\n/:/')

AllBackInfBac=$(awk 'NR==FNR{a[NR]=$0; next} {$0=$0 a[FNR]}1' $FileListInf $FileListLog)


BackUpNumber=1

# echo $AllBackInfBac
echo ""
# set -- $AllBackInfBac
# while [ "$#" -gt 0 ]; do
  # printf '%s\n' "$1:$2"


for i in $AllBackInfBac
do
# BackInfFile=$1
# BackLogFile=$2

# echo "*$i*"


BackInfFile=$(echo $i | awk -F ".log" '{print $2}')
# BackInfFile=$(echo $i | sed 's/:/\n/' | grep ".inf")
BackLogFile=$(echo $i | awk -F ".log" '{print $1}').log
# BackLogFile=$(echo $i | sed 's/:/\n/' | grep ".log")

# echo "BackInfFile: $BackInfFile"
# echo "BackLogFile: $BackLogFile"

#  echo READ
#  read


# for i in $AllBackInfFile
# do


# echo "READ"
# read

# i=$BackInfFile
# j=$BackLogFile

# LogCons "Info file: $i"
# LogCons "Backup log: $j"
BackupType=$(grep "incremental level" $BackLogFile | head -1)
echo ""
LogCons "************************************ Backup Number: $BackUpNumber $BackupType ************************************"
LogCons "Info file: $BackInfFile"
LogCons "Backup log: $BackLogFile"
# set -xv 

FirstSCN=$(grep "Recovery must be done beyond SCN" $BackInfFile | awk '{print $7}' | sort | head -1)

LastSCN=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
      $BackInfFile \
      | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | tail -1 | awk '{print $5}')
let LastSCN=$LastSCN-1

# FirstDate=$(grep ${FirstSCN} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | head -1 | awk -F "${FirstSCN}" '{print $2}' | awk '{print $1}')

if [[ $BackUpNumber -eq 1 ]]
then
	BackupFirstDate=$(grep ${FirstSCN} $BackInfFile | head -1 | awk -F "${FirstSCN}" '{print $2}' | awk '{print $1}')
	LogCons "First backup date: $BackupFirstDate"
fi

FirstDate=$(grep ${FirstSCN} $BackInfFile | head -1 | awk -F "${FirstSCN}" '{print $2}' | awk '{print $1}')

LastDate=$(grep --no-group-separator -A 3 " Thrd Seq     Low SCN    Low Time            Next SCN   Next Time" \
      $BackInfFile \
      | grep -v "Thrd Seq" | grep -v "\-\-\-\-" | sort -n -k5 | sed '/^$/d' | tail -1 | awk '{print $6}')

DefaultScn=$(grep "until scn" $ExecRestoreFile | awk '{print $NF}' | sed 's/;//')
DefaultDate=$(grep ${DefaultScn} ${BackupDir}/rman_*_${SID}_bck_control_file*.inf | awk '{print $NF}' | tail -1 )
UntilText=$(grep "until scn" $ExecRestoreFile | awk 'sub(/^ */, "")')
ControlText=$(grep "restore controlfile from" $ExecRestoreFile | awk 'sub(/^ */, "")')


if [[ $BackUpNumber -gt 1 ]]
then
	ArchiveMissing=$(grep "validation failed for archived log" $BackLogFile)
fi

if [[ ! -z $ArchiveMissing ]]
then
	LogCons "Can't restore point in time missing Archive files in the backup" 

	# LogCons "Backup log file:$BackLogFile"
	LogCons "Only possible restore points:" 
	LogCons "Default SCN Number: $DefaultScn"
	LogCons "Default Date: $DefaultDate"
	LogCons "Last SCN Number: $LastSCN"
	LogCons "Last Date: $LastDate" 
else

LogCons "Default SCN Number: $DefaultScn"
LogCons "Default Date: $DefaultDate"
LogCons "First SCN Number: $FirstSCN"
LogCons "First Date: $FirstDate"
LogCons "Last SCN Number: $LastSCN"
LogCons "Last Date: $LastDate"
fi
let BackUpNumber=$BackUpNumber+1 
done
}
#---------------------------------------------
Restore ()
#---------------------------------------------
{
if [[ ! -z "$ServerNameCheck" ]] || [[ ! -z "$DatabaseNameCheck" ]]
then
	LogCons "Server/database are PRODUCTION!"
	LogCons "Server Name:	$ServerName"
	LogCons "Database Name:	$SID"
while true;
do
    LogCons "Sure to restore the backup? done [Yes/No]: "
    read response
    if [[ $response = Yes ]]
    then
        LogCons "You chose: $response"
        break 
    elif [[ $response = No ]]
    then
	LogCons "You chose: $response"
	LogCons "Exit rman_restore_bkp.sh"
	exit 0
    else
        echo "You chose: $response"
    fi
done

	# LogError "Can't be used on PRODUCTION server!!!!"
	# exit 1
fi


OraEnv $SID 2>&1 >/dev/null  || BailOut "Failed OraEnv \"$SID\""

ExecRestoreFileRun="${BackupDir}/RUNFILE_RECO_RUN_${SID}_$TimeStamp.rcv"



LogCons "Check backup image."
if [[ -f ${ExecRestoreFile} ]]
then
        LogCons "File exist: $ExecRestoreFile"
	cp ${ExecRestoreFile} ${ExecRestoreFileRun} 
        chmod 770 ${ExecRestoreFileRun}
	LogCons "Restore script: ${ExecRestoreFileRun}"
else
        LogError "Restore script dont exist: $ExecRestoreFile Dir: $BackupDir"
        exit 1
fi

ScriptControlFile=$(grep "restore controlfile" $ExecRestoreFileRun | awk -F "'" '{print $2}' | awk -F "/" '{print $NF}')
sed -i "s/$ScriptControlFile/$LastControlFile/" $ExecRestoreFileRun

if [[ $Type == SCN ]] 
then
	LogCons "Type: SCN"
	if (( $Until >= $FirstSCN && $Until <= $LastSCN ))
	then
		LogCons "Valid SCN number: $Until"
		LogCons "Restore until SCN: $Until"
		sed -i "s/$UntilText/until scn $Until/" $ExecRestoreFileRun 
	else
		 LogError "Wrong SCN number: $Until, Have to be between $FirstSCN and $LastSCN"
		 exit 1
	fi
elif [[ $Type == Date ]]
then
	LogCons "Type: Date"
        if (( $(echo $Until | sed 's/[-:_]//g') >= $(echo $BackupFirstDate | sed 's/[-:_]//g') && $(echo $Until | sed 's/[-:_]//g') <= $(echo $LastDate | sed 's/[-:_]//g') ))
        then
                 LogCons "Valid Date: $Until"
		 LogCons "Restore until date: $Until"
		 # sed -i "s/$UntilText/set until time \"to_date('$Until','YYYY-MM-DD_HH24:MI:SS')\";/" $ExecRestoreFileRun
		 sed -i "s/$UntilText/# $UntilText/" $ExecRestoreFileRun
		 sed -i "s/restore database/set until time \"to_date('$Until','YYYY-MM-DD_HH24:MI:SS')\"; restore database/" $ExecRestoreFileRun
        else
                 LogError "Wrong Date: $Until, Have to be between $BackupFirstDate and $LastDate"
                 exit 1
        fi

elif [[ $Type == Default ]]
then
	Until=$DefaultScn
	LogCons "Type: Default Until: $Until"
	sed -i "s/$UntilText/until scn $Until/" $ExecRestoreFileRun
elif [[ $Type == Last ]]
then
	Until=$LastSCN
	LogCons "Type: Last" 
	LogCons "Restore until SCN: $Until"
	sed -i "s/$UntilText/until scn $Until/" $ExecRestoreFileRun
else
	LogError "Wrong TYPE value: $Type"
	exit 1
fi

#  echo "*stop*"
#  read
#  exit 0

LogCons "ShutDown database: $SID"
DoSqlV "shutdown abort" > $SqlLogFile

ShutDownAbort=$(grep ORA- $SqlLogFile)

if [[ ! -z "$ShutDownAbort" ]]
then
        LogError "Error shutdown the database: $SID Logfile: $SqlLogFile"
        exit 1
fi

find $OFA_DB_DATA/$ORACLE_SID* -type f 2>/dev/null > $TmpLogFile
find $OFA_DB_ARCH/$ORACLE_SID/*.arc -type f 2>/dev/null >> $TmpLogFile
echo ""
LogCons "Removeing file(s):"
echo ""
cat $TmpLogFile | LogStdInEcho

if [[ ! -z "$ServerNameCheck" ]] || [[ ! -z "$DatabaseNameCheck" ]]
then
        LogCons "Server/database are PRODUCTION!"
        LogCons "Server Name:   $ServerName"
        LogCons "Database Name: $SID"
while true;
do
    LogCons "Sure to Remove files? [Yes/No]: "
    read response
    if [[ $response = Yes ]]
    then
        LogCons "You chose: $response"
        break
    elif [[ $response = No ]]
    then
        LogCons "You chose: $response"
        LogCons "Exit rman_restore_bkp.sh"
        exit 0
    else
        echo "You chose: $response"
    fi
done

        # LogError "Can't be used on PRODUCTION server!!!!"
        # exit 1
fi

# LogCons "REMOVE FILES ????,   Ctrl-C to stop or ENTER to Continue"
# tty -s && read

if [[ $? -ne 0 ]]
then
	LogError "Terminated by user..." 
	exit 1
fi

LogCons "Removing the files............"
find $OFA_DB_DATA/$ORACLE_SID* -type f -exec rm -f {} \; 2>/dev/null > $TmpLogFile
find $OFA_DB_ARCH/$ORACLE_SID/*.arc -type f -exec rm -f {} \; 2>/dev/null > $TmpLogFile

cat $TmpLogFile  | LogStdInEcho

# Add lines:
sed -i '/alter database mount;/a CONFIGURE CONTROLFILE AUTOBACKUP OFF;' $ExecRestoreFileRun
sed -i '/}/a CONFIGURE CONTROLFILE AUTOBACKUP ON;' $ExecRestoreFileRun

LogCons "Starting the Restore..... ($ExecRestoreFileRun)"
# eval "$ExecRestoreFileRun" | LogStdInEcho
eval "$ExecRestoreFileRun" | LogStdIn
LogCons "End backup..."
LogCons "REMEMBER!  To run full backup after restore....."
}
#---------------------------------------------
# MAIN 
#---------------------------------------------
if [[ "$FuncToDo" == "Info" ]]
then
#	FindScnDate
	FindScnDateAll
elif [[ "$FuncToDo" == "Restore" ]]
then
	Type=$3
	Until=$4
        FindScnDateAll
        # FindScnDate
	Restore
elif [[ "$FuncToDo" == "InfoAll" ]]
then
	FindScnDateAll
else
        usage
fi
