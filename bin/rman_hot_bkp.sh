#!/bin/ksh -p
#
# rman_hot_bkp.sh: perform database backups
#
# Modifications: 
#    20120329 ols - cration du fichier
#
# ------------------------------------------------------------------------------
  #
  ## Name: rman_hot_bkp.sh
  ##
  ## In:  Oracle Database
  ## Out: Rman Backup
  ## Ret: 0/1
  ##
  ## Synopsis: Perform ONLINE R-Man backup of an oracle database.
  ##
  ## Usage: rman_hot_bkp.sh <SID> [<backup> or <verify> or blank] <CHANNELS=[NUM]> <SECTION_SIZE>
  ## 
  ## Parameter:
  ##    backup (ONLY run backup, NO verify of backup)
  ##    verify (ONLY verify the last backup)
  ##    blank  (No parameters: backup and verify)
  ##
  ##    CHANNELS=[NUMBER_OF CHANNELS] set the number of channels to use diffrent from default. 
  ##    SECTION_SIZE=[SIZE_OF_SECTION] Backup will use section size during backup, SIZE_OF_SECTION in GB.
  ##    BACKUP_TYPE=[BACKUP_TYPE] Which backup type Full backup: 0, Incremental: 1, Cumulative Incremental: 2
  ##
  ##    Any variable from the ../etc/rman_hot_bkp/rman_hot_bkp.defaults can be changed by
  ##    VAIRABLE_NAME=NEW_VALUE
  ##    e.g.
  ##    PIECESIZE=10G 
  ## 
  ## Description:
  ## ============
  ##   Performs an online database backup to disk using control file for a catalogue.
  ## 
  ##   Items backed up
  ##   ---------------
  ##   Apart from the R-Man backup set, these items are also saved to the same
  ##   location: 
  ##    - pfile 
  ##    - spfile
  ##    - controlfile trace (text)
  ##    - original controlfile (binary)
  ##    - The rman backup script used for the current backup.
  ##    - the restore script (generated)
  ##    - the relevant part of the alert log.
  ##    - this script's log for this run (copy).
  ##
  ##   Recovery UNTIL
  ##   --------------
  ##    - If available, SCN: extracted from rman "backup list" output (first control file)
  ##    - Else, a time stamp based on the backup end time (minus $PITR_LAG_SECONDS)
  ##
  #
  # ------------------------------------------------------------------------------

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#----------------------------------------------------------------------------------------------
# functions
#----------------------------------------------------------------------------------------------
function GetRecoScn {
#----------------------------------------------------------------------------------------------
      #
      # capture SCN:
      #  - delete output upt to and in cluding $RMAN_TAG
      #  - retain only lines containing "Control File Included" (there are 3)
      #  - retain only the first one
      #  - field #6 is the SCN
      #
      #  rman << EOF | sed "1,/$RMAN_TAG/d" | grep 'Control File Included' | head -1 | awk '{print $6}'
        rman << EOF | sed "s/Standby//g" | sed "1,/$RMAN_TAG/d" | grep 'Control File Included' | head -1 | awk '{print $6}'
        connect target /

        list backup;
EOF
    }
#----------------------------------------------------------------------------------------------
function GetLastTag
#----------------------------------------------------------------------------------------------
{
rman << EOF | grep $ORACLE_SID |  tail -1 | awk '{print $10}'
        connect target /
        list backup summary;
EOF
}
#----------------------------------------------------------------------------------------------
function SetBackupType
#----------------------------------------------------------------------------------------------
{
unset BackupType

# BackupType=$(echo $AllParameters | grep BACKUP_TYPE | awk -F 'BACKUP_TYPE' '{print $2}' | sed 's/=//')

# if [[ -z $BackupType ]]
# then
	BackupType=$BACKUP_TYPE
# fi


if [[ $BackupType -eq 0 ]] || [[ -z $BackupType ]] 
then 
	BackLevel="Full backup"
	BackLevelShort="Full"
	BACKUP_TYPE=0
	
elif [[ $BackupType -eq 1 ]]
then
	BackLevel="Incremental"
	BackLevelShort="Inc"
	BACKUP_TYPE=1
elif [[ $BackupType -eq 2 ]]
then
	BackLevel="Cumulatilve Incremental"
	BackLevelShort="Cum"
	BACKUP_TYPE="1 CUMULATIVE"
else
	LogError "Error: Wrong backup type: $BackupType, Full backup: 0, Incremental: 1, Cumulative Incremental: 2"
	exit 1
fi

LogCons "           - Backup type used: $BackLevel"

}
#----------------------------------------------------------------------------------------------
function SetSectionSize
#----------------------------------------------------------------------------------------------
{
unset SectionSize

SectionSize=$(echo $AllParameters | grep SECTION | awk -F 'SECTION' '{print $2}' | sed 's/=//')

if [[ ! -z $SectionSize ]]
then
        SECTION_SIZE=${SectionSize}
        LogCons "           - Backup using SECTION_SIZE (Size: ${SectionSize})."
else
        LogCons "           - Backup using MAXPICESIZE (Size: ${PIECESIZE})."
fi
}

#----------------------------------------------------------------------------------------------
function SetNumChannels
#----------------------------------------------------------------------------------------------
{
unset NumChannels

NumChannels=$(echo $AllParameters | grep CHANNELS | awk -F 'CHANNELS' '{print $2}' | sed 's/=//')

if [[ ! -z $NumChannels ]]
then
	CHANNELS=$NumChannels
	LogCons "           - Number of CHANNELS=${CHANNELS}, none Default."
else
	LogCons "           - Number of CHANNELS=${CHANNELS}, Default."
fi 
}
#----------------------------------------------------------------------------------------------
function SetParameters
#----------------------------------------------------------------------------------------------
{
for i in $AllParameters
do
	# echo "**** $i ****"
	export $i
	if [[ ! -z $(echo $i | grep "=") ]]
	then
		LogCons "           - Parameter set: $i"
	fi
done 

if [[ ! -z $CHANNELS ]]
then
        LogCons "           - Number of CHANNELS=${CHANNELS}."
fi

if [[ ! -z $SECTION_SIZE ]]
then
	export SECTION_SIZE=${SECTION_SIZE}G
	export SECTION_SIZE_COMMAND="SECTION SIZE ${SECTION_SIZE}"
        LogCons "           - Backup using SECTION_SIZE (Size: ${SECTION_SIZE})."
else
	export MAXPICESIZE_COMMAND="maxpiecesize ${PIECESIZE}"
        LogCons "           - Backup using MAXPICESIZE (Size: ${PIECESIZE})."
fi
}
#----------------------------------------------------------------------------------------------
function VerifyLast 
#----------------------------------------------------------------------------------------------
{
STEP_LABEL="Step: 2/$STEPS - Getting last backup TAG." && LogCons "$STEP_LABEL"
LastTag=$(GetLastTag)
RMAN_TAG=$LastTag
LogCons "          - Last TAG name: $LastTag"

  #
  ## The "TAG" feature
  ## =================
  ## The $TAG variable, if supplied, extends the $OFA_MY_DB_BKP path, which is the default
  ## backup destination. The tag may be itself a path of any permissible depth.
  #
    STEP_LABEL="Step: 3/$STEPS - custom backup tag" && LogCons "$STEP_LABEL"
    if [[ -n $TAG ]];then
        LogIt "Extpanding RMAN backup dump path \"$OFA_MY_DB_BKP\" by \"$TAG\""
        RMAN_DUMP_PATH=$(StraightPath $OFA_MY_DB_BKP/$TAG)
        mkdir -p $RMAN_DUMP_PATH
        [[ ! -d $RMAN_DUMP_PATH ]] && UsageExit1 "Error: Failed to create direcroy $RMAN_DUMP_PATH"
        LogIt "New RMAN backup dump path is $RMAN_DUMP_PATH"
    else
        RMAN_DUMP_PATH=$OFA_MY_DB_BKP
        LogIt "RMAN backup dump path is $RMAN_DUMP_PATH"
    fi
    mkdir -p $RMAN_DUMP_PATH
    [[ ! -w $RMAN_DUMP_PATH ]] && UsageExit1 "Error: direcroy $RMAN_DUMP_PATH is not writeable"


  #
  # Generate backup script
  #
    STEP_LABEL="Step: 4/$STEPS - generate backup script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN BACKUP script from template script $RMAN_BKP_GENSCR"
    [[ ! -r $RMAN_BKP_GENSCR  ]] && RMAN_BKP_GENSCR=$OFA_MY_ETC/$RMAN_BKP_GENSCR
    [[ -r $RMAN_BKP_GENSCR ]]  || UsageExit1 "$OFA_ERR Failed read of file: \"$RMAN_BKP_GENSCR\""
    RUNFILE_BKP_RCV=$RMAN_DUMP_PATH/RUNFILE_BKP_${RMAN_TAG}_verify.rcv
    touch $RUNFILE_BKP_RCV || UsageExit1 "$OFA_ERR Failed touch of file \"$RUNFILE_BKP_RCV\""
    LogIt "Generating RMAN script to file \"$RUNFILE_BKP_RCV\""
    . $RMAN_BKP_GENSCR | tee $RUNFILE_BKP_RCV | LogStdIn

  #
  # Run the backup
  #
    STEP_LABEL="Step: 5/$STEPS - run verify backup" && LogCons "$STEP_LABEL"
    LogIt "Runnung the RMAN BACKUP script \"$RUNFILE_BKP_RCV\""
    . $RUNFILE_BKP_RCV  2>&1 | LogStdIn



}
#----------------------------------------------------------------------------------------------
# MAIN
#----------------------------------------------------------------------------------------------
    RunMmDp
  #
  # must be sysdba
  #
    ImaSysDba || BailOut "Backup of $ORACLE_SID requires sysdba"

  #
  # check that no other rman task is running on the same target from ofa
  #
    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  #
  # Settings de base
  #
    STEPS=18

  AllParameters=$*

  #
  # Check $2
  #

 if [[ "$2" == "backup" ]] || [[ "$2" == "verify" ]]
 then
	BackupFunction=$2
 fi 


#  CheckParameterTwo=$(echo $2 | grep -e CHANNELS -e SECTION)

#  if [[ ! -z $CheckParameterTwo ]]
#  then 
#	BackupFunction=""
#  else
#	BackupFunction=$2
#  fi  
 
  # SetNumChannels
  # SetSectionSize
  SetParameters
  SetBackupType


  #
  # Function: verify or backup.
  #
        # BackupFunction=$2

	if [[ ! -z "$BackupFunction" ]] 
	then
		if [[ "$BackupFunction" == "backup" ]] 
		then
    			STEP_LABEL="Step: 1/$STEPS - basic settings" && LogCons "$STEP_LABEL"
			LogCons "           - Backup function: Running backup ONLY. No verify of backup!!!!"
			RMAN_BKP_GENSCR=$RMAN_BKP_GENSCR_NV	
			LogCons "           - Using template: $RMAN_BKP_GENSCR"
		elif [[ "$BackupFunction" == "verify" ]]
		then
    			STEPS=5
    			STEP_LABEL="Step: 1/$STEPS - basic settings" && LogCons "$STEP_LABEL"
			LogCons "          - Backup function: Verify ONLY! (Of last backup)"
                        RMAN_BKP_GENSCR=$RMAN_BKP_GENSCR_VL
			LogCons "          - Using template: $RMAN_BKP_GENSCR"
			VerifyLast
			exit 0
		else
    			STEP_LABEL="Step: 1/$STEPS - basic settings" && LogCons "$STEP_LABEL"
			LogError "Wrong \$2 parameter: $2!, <backup> or <verify> or blank "
			exit 1
		fi
	else
    		STEP_LABEL="Step: 1/$STEPS - basic settings" && LogCons "$STEP_LABEL"
		LogCons "           - Backup function: Backup and Verify"
		LogCons "           - Using template: $RMAN_BKP_GENSCR"
	fi

  #
  # The SID: $1 
  #
    STEP_LABEL="Step: 2/$STEPS - setting SID" && LogCons "$STEP_LABEL"
    [[ ! -n $1 ]] \
        && UsageExit1 "Supply SID pls" \
        || SID=$1
        TimeStamp=$(Tmsp)
	# SidUpper=$(echo $SID |tr [[:lower:]] [[:upper:]])
	SidUpper=$(echo $SID | awk '{print toupper($0)}')

	LogCons "           - Database name: $SidUpper"
	LogCons "           - Time stamp: $TimeStamp"
    RMAN_TAG=${SidUpper}_${TimeStamp}
    # RMAN_TAG=$(echo ${SID}_$(Tmsp)|tr [[:lower:]] [[:upper:]])
	LogCons "           - Rman tag: ${RMAN_TAG}"
    
    # RMAN_TAG=$(echo ${SID}_$(Tmsp)_${BackLevelShort}|tr [[:lower:]] [[:upper:]])


  #
  # Verify args and connectivity, else fail with Usage
  #
    STEP_LABEL="Step: 3/$STEPS - check connectivity" && LogCons "$STEP_LABEL"
    [[ ! -n $SID ]] && UsageExit1 "$OFA_ERR No SID!"
    OraEnv  $SID >/dev/null || UsageExit1 "$OFA_ERR Failed OraEnv" 
    OraDbTestCnx    || UsageExit1 "$OFA_ERR Failed connection test to $SID"
  #
  # Check variable completeness 
  #
    STEP_LABEL="Step: 4/$STEPS - check variable completeness" && LogCons "$STEP_LABEL"
    CheckVar                          \
	   BACKUP_TYPE                \
           CHANNELS                   \
           OFA_ERR_PAT                \
           FILESPERSET                \
           OFA_MY_DB_BKP              \
           PIECESIZE                  \
           PITR_LAG_SECONDS           \
           CLEAR_TO_DEL_INCL_ARC      \
           RMAN_BKP_GENSCR            \
           RMAN_RECO_GENSCR           \
        && LogIt "Variables complete" \
        || UsageExit1 "$OFA_ERR Variables vides ci-avant - fournir les valeurs manquantes"

  #
  # Get the number of log members or bail out
  # (This value is used for the number of switches after the backup). 
  #
    STEP_LABEL="Step: 5/$STEPS - Query # of redo members" && LogCons "$STEP_LABEL"
    LOG_MEMBERS=$(DoSqlQ "SELECT COUNT(*) FROM V\$LOG;"|awk '{print $NF}')
    [[ $LOG_MEMBERS -lt 2 ]] && BailOut "Failed to query log member in \"$SID\""
    LogIt "$SID has $LOG_MEMBERS online redo log members"

  #
  # extract DBID and current SCN from the running database
  #
    STEP_LABEL="Step: 6/$STEPS - Query DBID from $SID" && LogCons "$STEP_LABEL"
    DBID=$(DoSqlQ "SELECT DBID FROM V\$DATABASE;"|awk '{print $NF}')
    [[ ! -n $DBID ]] && BailOut "Failed to query DBID from \"$SID\""
    LogIt "$SID's DBID is $DBID"


  # ----------------------------------------------------------------------------
  # All pre-requisites are checked okay. 
  # Proceed with interaction now.
  # ----------------------------------------------------------------------------
if [[ $BackLevelShort == Full ]]
then
  #
  # Freeing up space at backup dump fs.
  # If the CLEAR_TO_DEL_INCL_ARC variable contains anything other than 0,
  # move previous backup into the to_be_deleted sub-directory.
  # Else, delete previous backup. 
  # Mind you 
  #
    mkdir -p $OFA_MY_DB_BKP
    [[ -w $OFA_MY_DB_BKP ]] || BailOut "$OFA_MY_DB_BKP not writeable"
    LogIt "Deleting second to last backup from \"to_be_deleted\" directory"
    rm -fr               $OFA_MY_DB_BKP/to_be_deleted    2>/dev/null  # rm dir
    mkdir -p             $OFA_MY_DB_BKP/to_be_deleted    2>/dev/null  # re-create dir
    LogIt "Moving previous backup to \"$OFA_MY_DB_BKP/to_be_deleted\" sub-directory"
    touch $OFA_MY_DB_BKP/dumbme 
  #
  # The following block should be redundant when bk2pro is in use,
  # because bk2pro.sh readily moves backed-up files to the to_be_deleted directory.
  # However in many non-prod environments this is not the case. 
  # 
  #
    if [[ $CLEAR_TO_DEL_INCL_ARC != "0" ]] 
    then
      #
      # Preserve previous: shoves all previous into to_be_deleted.
      # including archivelog backups.
      #
        LogIt "Moving last backup to \"to_be_deleted\" directory"
        STEP_LABEL="Step: 7/$STEPS - shift previous backup" && LogCons "$STEP_LABEL"
        mv -f $(ls -1d $OFA_MY_DB_BKP/*|egrep -v "to_be_deleted") $OFA_MY_DB_BKP/to_be_deleted 
    else
      #
      # Deletes everything EXCEPT archivelog backups. 
      # If there are any, then they have not yet been backed-up to tape. 
      # This is the default as most hot backups occur in PROD, where archived logs are 
      # shipped away to tape. 
      #
        LogIt "Count before delete: $(ls -1d $OFA_MY_DB_BKP/*|wc -l)"
        eval $OFA_DF_COMMAND $OFA_MY_DB_BKP | LogStdIn
        LogIt "Deleting last backup from \"$OFA_MY_DB_BKP/\" directory"
        STEP_LABEL="Step: 7/$STEPS - skip preserve previous" && LogCons "$STEP_LABEL"
        rm -rf $(ls -1d $OFA_MY_DB_BKP/*|egrep -v "to_be_deleted|$ARC_FILE_NAME_PAT")
        LogIt "Count after delete: $(ls -1d $OFA_MY_DB_BKP/*|wc -l)"
        eval $OFA_DF_COMMAND $OFA_MY_DB_BKP | LogStdIn
    fi
fi
  #
  ## The "TAG" feature
  ## =================
  ## The $TAG variable, if supplied, extends the $OFA_MY_DB_BKP path, which is the default
  ## backup destination. The tag may be itself a path of any permissible depth.
  #
    STEP_LABEL="Step: 8/$STEPS - custom backup tag" && LogCons "$STEP_LABEL"
    if [[ -n $TAG ]];then
        LogIt "Extpanding RMAN backup dump path \"$OFA_MY_DB_BKP\" by \"$TAG\""
        RMAN_DUMP_PATH=$(StraightPath $OFA_MY_DB_BKP/$TAG)
        mkdir -p $RMAN_DUMP_PATH 
        [[ ! -d $RMAN_DUMP_PATH ]] && UsageExit1 "Error: Failed to create direcroy $RMAN_DUMP_PATH"
        LogIt "New RMAN backup dump path is $RMAN_DUMP_PATH"
    else
        RMAN_DUMP_PATH=$OFA_MY_DB_BKP
        LogIt "RMAN backup dump path is $RMAN_DUMP_PATH"
    fi
    mkdir -p $RMAN_DUMP_PATH
    [[ ! -w $RMAN_DUMP_PATH ]] && UsageExit1 "Error: direcroy $RMAN_DUMP_PATH is not writeable"
   
  #
  # Attempt to spot the database's alert log and count its lines
  #
    STEP_LABEL="Step: 9/$STEPS - capture alert log" && LogCons "$STEP_LABEL"
    # cd trace 2>/dev/null >/dev/null || cd bdump 2>/dev/null >/dev/null
    # ALERTLOG=$(ls -1t $PWD/alert*$SID.log 2>/dev/null|head -1)
    ALERTLOG=$(AlertLog)
    [[ -f $ALERTLOG ]]                                         \
        && ALERTLOG_LINES_B4=$(cat $ALERTLOG|wc -l)            \
        && LogIt "spotted $ALERTLOG, $ALERTLOG_LINES_B4 lines" \
        || LogWarning  "failed spotting $SID's alert log"

  #
  # Generate backup script
  #
    STEP_LABEL="Step: 10/$STEPS - generate backup script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN BACKUP script from template script $RMAN_BKP_GENSCR"
    [[ ! -r $RMAN_BKP_GENSCR  ]] && RMAN_BKP_GENSCR=$OFA_MY_ETC/$RMAN_BKP_GENSCR 
    [[ -r $RMAN_BKP_GENSCR ]]  || UsageExit1 "$OFA_ERR Failed read of file: \"$RMAN_BKP_GENSCR\""
    RUNFILE_BKP_RCV=$RMAN_DUMP_PATH/RUNFILE_BKP_${RMAN_TAG}.rcv
    touch $RUNFILE_BKP_RCV || UsageExit1 "$OFA_ERR Failed touch of file \"$RUNFILE_BKP_RCV\""
    LogIt "Generating RMAN script to file \"$RUNFILE_BKP_RCV\""
    . $RMAN_BKP_GENSCR | tee $RUNFILE_BKP_RCV | LogStdIn

  #
  # Set up generation of recovery script.
  #
    STEP_LABEL="Step: 11/$STEPS - setup reco script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN RECOVERY script from template script $RMAN_RECO_GENSCR"
    [[ ! -r $RMAN_RECO_GENSCR  ]] && RMAN_RECO_GENSCR=$OFA_MY_ETC/$RMAN_RECO_GENSCR 
    RUNFILE_RECO_RCV=$RMAN_DUMP_PATH/RUNFILE_RECO_${RMAN_TAG}.rcv
    [[ -r $RMAN_RECO_GENSCR ]]  || UsageExit1 "$OFA_ERR Failed read of file: \"$RUNFILE_RECO_RCV\""
    touch $RUNFILE_RECO_RCV || UsageExit1 "$OFA_ERR Failed touch of file \"$RMAN_RECO_GENSCR\""

  #
  # Make sure there is a pfile and an spfile.
  # Do this here as rman complains when the database hasn-t been started with the spfile.
  #
    STEP_LABEL="Step: 12/$STEPS - get (s)pfile(s)" && LogCons "$STEP_LABEL"
    DoSqlQ "create spfile from memory;" 2>&1 >/dev/null
    DoSqlQ "create pfile from spfile;"  2>&1 >/dev/null
    LogIt "cp $ORACLE_HOME/dbs/spfile$SID.ora to $RMAN_DUMP_PATH/spfile$SID.$RMAN_TAG.ora"
    cp $ORACLE_HOME/dbs/spfile$SID.ora $RMAN_DUMP_PATH/spfile$SID.$RMAN_TAG.ora 2>/dev/null
    [[ $? -ne 0 ]] && LogWarning "Failed cp $ORACLE_HOME/dbs/spfile$SID.ora"
    LogIt "cp $ORACLE_HOME/dbs/init*$SID.ora to $RMAN_DUMP_PATH/init$SID.ora"
    cp $(ls -1 $ORACLE_HOME/dbs/init_$SID.ora $ORACLE_HOME/dbs/init$SID.ora 2>/dev/null|head -1) $RMAN_DUMP_PATH/ 2>/dev/null
    [[ $? -ne 0 ]] && LogWarning "Failed cp $ORACLE_HOME/dbs/init$SID.ora"

  # 
  # Run the backup
  #
    STEP_LABEL="Step: 13/$STEPS - run backup" && LogCons "$STEP_LABEL"
    LogIt "Runnung the RMAN BACKUP script \"$RUNFILE_BKP_RCV\""
    LogCons "            - Running script: $RUNFILE_BKP_RCV"
    BackLogFile=$LOGFILE
    LogCons "            - Backup log file: $BackLogFile"
    . $RUNFILE_BKP_RCV  2>&1 | LogStdIn
  #
  # Check for missing Archive files
  #
    BackInfFile=$(grep "spool log to" $RUNFILE_BKP_RCV | awk '{print $4}' | sed 's/;//g')
    BackLevel=$(grep "incremental level" $RUNFILE_BKP_RCV | awk '{print $3}')
    LogCons "            - Info file: $BackInfFile"
    LogCons "            - Backup level: $BackLevel"
    
if [[ $BackLevel -gt 0 ]]
    then
	ArchiveMissing=$(grep "validation failed for archived log" $BackLogFile)
        if [[ ! -z $ArchiveMissing ]]
	then
        	LogCons "            - Can't restore point in time missing Archive files in the backup"
		LogWarning "Can't restore point in time missing Archive files in the backup"
	fi
    fi
 
  # 
  # Populate "recover until" condition
  #
    STEP_LABEL="Step: 14/$STEPS - Populate \"recover until\" condition" && LogCons "$STEP_LABEL"
    RECO_SCN=$(GetRecoScn)
    LogCons "            - Reco scn: ${RECO_SCN}"
    CheckVar RECO_SCN && echo $RECO_SCN | egrep "^[${_DIGIT_}][${_DIGIT_}]*$" >/dev/null
    if [[ $? -eq 0 ]]
    then
      #
      # SCN
      #
        LogCons "            - RECO_SCN looks good: $RECO_SCN - using that for recovery script"
        RECO_CONDITION="scn $RECO_SCN"
    else
      #
      # PITR
      #
        LogWarning "Failed to extract appropriate SCN for recovery script: using PITR instead."
        LogCons "Getting time stamp from $SID for PITR ($PITR_LAG_SECONDS prior to backup completion)"
        PITR_TMSP="$(DoSqlQ "SELECT TO_CHAR(sysdate-$PITR_LAG_SECONDS/86400, 'YYYYMMDDHH24MISS') FROM DUAL;")"
        RECO_CONDITION="time \"to_date(\'$PITR_TMSP\','YYYYMMDDHH24MISS')\""
    fi

  # 
  # Identify backup controlfile
  #
    STEP_LABEL="Step: 15/$STEPS - get reco controlfile" && LogCons "$STEP_LABEL"
    CONTROLFILE_AFTER="$RMAN_DUMP_PATH/controlfile_${RMAN_TAG}.after.ctl"
    LogCons "            - Looking for control file for use with reco script"
    CONTROLFILE=$(ls -1rt $RMAN_DUMP_PATH/${OFA_CTL_FMT_PREFIX}* $CONTROLFILE_AFTER 2>/dev/null | tail -2 | head -1)
    

    if [[ ! -r "$CONTROLFILE" ]] \
    then
        LogError "Couldn't find suitable backup controlfile for reco script" 
        LogWarning  "No recovery script will be generated." 
    else
        LogCons "            - Generating RMAN RECOVERY script  \"$RUNFILE_RECO_RCV\"" 
        . $RMAN_RECO_GENSCR | tee $RUNFILE_RECO_RCV | LogStdIn
    fi

  #
  # copy relevant portion of alert log to $OFA_MY_DB_BKP
  #
    STEP_LABEL="Step: 16/$STEPS - alert log extract" && LogCons "$STEP_LABEL"
	LogIt "Alert log: $ALERTLOG"
     [[ -f $ALERTLOG ]]                                                         \
         && LogIt "Committing relevant portion of $ALERTLOG to record"          \
         && eval $(echo sed -n \'$ALERTLOG_LINES_B4,\$p\' $ALERTLOG) > $OFA_MY_DB_BKP/alert$RMAN_TAG.log \
         || LogWarning "Alert log not captured (possibly couldn't find it)"

  #
  # list contents of backup destination directory
  #
    ls -ldi $OFA_MY_DB_BKP/* | grep -v $OFA_MY_DB_BKP/to_be_deleted | LogStdIn
  #
  # Check for missing Archive files in All inc backups
  #
  STEP_LABEL="Step: 17/$STEPS - Check validation of archiv files INC backup." && LogCons "$STEP_LABEL"
  FilesList=$(grep -m1 -l "incremental level 1" $RMAN_DUMP_PATH/rman_hot_*)
  for i in $FilesList
  do 
  ArchiveMissing=$(grep "validation failed for archived log" $i)
        if [[ ! -z $ArchiveMissing ]]
        then
                LogCons "            - Can't restore point in time missing Archive files in the backup"
		LogCons "            - Log File: $i"
                LogWarning "Can't restore point in time missing Archive files in the backup....."
		LogWarning "Log file: $i"
        fi
  done

  #
  # trap 2: de-activate trap
  #
    OFA_TRAP_XIT=""
  #
  # finish
  #
    STEP_LABEL="Step: $STEPS/$STEPS - Completed" && LogCons "$STEP_LABEL"
    MailLogReport "$SID: $STEP_LABEL"
    RV=$?
    LogIt "Committing this log to record."
    LogIt "END"
    cp -p $LOGFILE $OFA_MY_DB_BKP
    exit $RV


