#!/bin/ksh -p
#
# rman_cold_bkp.sh: perform database backups
#
# Modifications: 
#    20120329 ols - création du fichier
#
# ------------------------------------------------------------------------------
  #
  ## Name: rman_cold_bkp.sh
  ##
  ## In:  Oracle Database
  ## Out: Rman Backup
  ## Ret: 0/1
  ##
  ## Synopsis: Perform OFFLINE R-Man backup of an oracle database, no catalog.
  ##
  ## Usage: rman_cold_bkp.sh <SID>
  ##
  ## Description:
  ## 
  ##   Performs an offline database backup to disk.
  ## 
  ##   Items backed up
  ##   ===============
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
  # 
  #  Workings:
  # 
  #    OFA_MY_DB_BKP and OFA_MY_DB_VAR
  #    =======================
  #    These variables are automatically set by the OraEnv function. 
  #    By default, their values are an extension of the corresponding OFA_*
  #    Standard paths:
  # 
  #    - OFA_MY_DB_BKP is $OFA_DB_BKP/<SID>/rman   # needed for backup
  #    - OFA_MY_DB_VAR is $OFA_DB__VAR/<SID>       # needed for alert log
  # 
  #    For databases that are not fully "ofa", these paths may be different. 
  #    If so, the best place to store the override assignment is the specific
  #    parameter file $OFA_ETC/rman_hot_bkp/rman_hot_bkp.<SID>.
  # ------------------------------------------------------------------------------

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

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
    STEP=1
    STEPS=24
    let STEP+=1 && STEP_LABEL="Step: 1/$STEPS - basic settings" && LogCons "$STEP_LABEL"

  #
  # The SID: $1 
  #
    let STEP+=1 && STEP_LABEL="Step: 2/$STEPS - setting SID" && LogCons "$STEP_LABEL"
    [[ ! -n $1 ]] \
        && Usage "Supply SID pls" \
        || SID=$1

    RMAN_TAG=$(echo ${SID}_$(Tmsp)|tr [[:lower:]] [[:upper:]])

  #
  # Verify args and connectivity, else fail with Usage
  #
    let STEP+=1 && STEP_LABEL="Step: 5/$STEPS - check connectivity" && LogCons "$STEP_LABEL"
    [[ ! -n $SID ]] && Usage "$OFA_ERR No SID!"
    OraEnv  $SID 2>&1 >/dev/null || Usage "$OFA_ERR Failed OraEnv" 

  #
  # Check variable completeness 
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - check variable completeness" && LogCons "$STEP_LABEL"
    CheckVar                   \
           CHANNELS            \
           DB_STOP_COMMAND     \
           OFA_ERR_PAT         \
           FILESPERSET         \
           OFA_MY_DB_BKP           \
           PIECESIZE           \
           CLEAR_TO_DEL_INCL_ARC \
           RMAN_BKP_GENSCR     \
           RMAN_RECO_GENSCR    \
        && LogIt "Variables complete" \
        || Usage "$OFA_ERR Variables vides ci-avant - fournir les valeurs manquantes"

  # ----------------------------------------------------------------------------
  # All pre-requisites are checked okay. 
  # Proceed with interaction now.
  # ----------------------------------------------------------------------------

  #
  # Put DB into Mounted state
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - take down $SID" && LogCons "$STEP_LABEL"
    DBSTATUS=$(OraDbStatus)
    if [[ "$DBSTATUS" != "CLOSED" ]]
    then
        LogIt "$SID is in \"$DBSTATUS\" state - closing it"
        LogIt "running $DB_STOP_COMMAND"
        eval $DB_STOP_COMMAND | LogStdIn
    fi

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - mount $SID" && LogCons "$STEP_LABEL"
    DBSTATUS=$(OraDbStatus)
    LogIt "$SID is in \"$DBSTATUS\" state. Starting it into mount exclusive state"
    DoSqlQ "STARTUP MOUNT EXCLUSIVE;" | LogStdIn

    DBSTATUS=$(OraDbStatus)
    [[ "$DBSTATUS" != "MOUNTED" ]] && BailOut "Coudn't get $SID into \"MOUNTED\" state. State is now: \"$DBSTATUS\""
    LogIt "$SID is in \"$DBSTATUS\" state. Proceeding."

  #
  # extract DBID and current SCN from the running database
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - query $SID for DBID" && LogCons "$STEP_LABEL"
    DBID=$(DoSqlQ "SELECT DBID FROM V\$DATABASE;"|awk '{print $NF}')
    [[ ! -n $DBID ]] && BailOut "Failed to query DBID from \"$SID\""
    LogIt "$SID's DBID is $DBID"

  #
  # Freeing up space at backup dump fs.
  # If the CLEAR_TO_DEL_INCL_ARC variable contains anything other than 0,
  # move previous backup into the to_be_deleted sub-directory.
  # Else, delete previous backup.
  #
    mkdir -p $OFA_MY_DB_BKP
    [[ -w $OFA_MY_DB_BKP ]] || BailOut "$OFA_MY_DB_BKP not writeable"
    LogIt "Deleting second to last backup from \"to_be_deleted\" directory"
    LogIt "Count before delete: $(ls -1d $OFA_MY_DB_BKP/*|wc -l)"
    eval $OFA_DF_COMMAND $OFA_MY_DB_BKP | LogStdIn
    rm -rf               $OFA_MY_DB_BKP/to_be_deleted 2>/dev/null  # rm dir
    mkdir -p             $OFA_MY_DB_BKP/to_be_deleted 2>/dev/null  # re-create dir
    if [[ $CLEAR_TO_DEL_INCL_ARC != "0" ]]
    then
        LogIt "Moving previous backup to \"$OFA_MY_DB_BKP/to_be_deleted\" sub-directory"
        let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - shift previous backup" && LogCons "$STEP_LABEL"
        mv -f $(ls -1d $OFA_MY_DB_BKP/*|grep -v to_be_deleted) $OFA_MY_DB_BKP/to_be_deleted
    else
        LogIt "Deleting last backup from \"$OFA_MY_DB_BKP/\" directory"
        let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - skip preserve previous" && LogCons "$STEP_LABEL"
        rm -f $(ls -1d $OFA_MY_DB_BKP/*|grep -v to_be_deleted)
    fi
    LogIt "Count after delete: $(ls -1d $OFA_MY_DB_BKP/*|wc -l)"
    eval $OFA_DF_COMMAND $OFA_MY_DB_BKP | LogStdIn


  #
  ## The "TAG" feature
  ## =================
  ## The $TAG variable, if supplied, extends the $OFA_MY_DB_BKP path, which is the default
  ## backup destination. The tag may be itself a path of any permissible depth.
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - custom backup tag" && LogCons "$STEP_LABEL"
    if [[ -n $TAG ]];then
        LogIt "Extending RMAN backup dump path \"$OFA_MY_DB_BKP\" by \"$TAG\""
        RMAN_DUMP_PATH=$(StraightPath $OFA_MY_DB_BKP/$TAG)
        mkdir -p $RMAN_DUMP_PATH 
        [[ ! -d $RMAN_DUMP_PATH ]] && Usage "Error: Failed to create direcroy $RMAN_DUMP_PATH"
        LogIt "New RMAN backup dump path is $RMAN_DUMP_PATH"
    else
        RMAN_DUMP_PATH=$OFA_MY_DB_BKP
        LogIt "RMAN backup dump path is $RMAN_DUMP_PATH"
    fi
    mkdir -p $RMAN_DUMP_PATH
    [[ ! -w $RMAN_DUMP_PATH ]] && Usage "Error: direcroy $RMAN_DUMP_PATH is not writeable"
   
  #
  # Attempt to spot the database's alert log and count its lines
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - capture alert log" && LogCons "$STEP_LABEL"
    cd trace 2>/dev/null >/dev/null || cd bdump 2>/dev/null >/dev/null
    ALERTLOG=$(ls -1t $PWD/alert*$SID.log 2>/dev/null|head -1)
    [[ -f $ALERTLOG ]]                                         \
        && ALERTLOG_LINES_B4=$(cat $ALERTLOG|wc -l)            \
        && LogIt "spotted $ALERTLOG, $ALERTLOG_LINES_B4 lines" \
        || LogWarning  "failed spotting $SID's alert log"

  #
  # Check templates and generate the backup script
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - generate backup script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN BACKUP script from template script $RMAN_BKP_GENSCR"
    [[ ! -r $RMAN_BKP_GENSCR  ]] && RMAN_BKP_GENSCR=$OFA_MY_ETC/$RMAN_BKP_GENSCR 
    [[ -r $RMAN_BKP_GENSCR ]]  || Usage "$OFA_ERR Failed read of file: \"$RMAN_BKP_GENSCR\""
    RUNFILE_BKP_RCV=$RMAN_DUMP_PATH/RUNFILE_BKP_${RMAN_TAG}.rcv
    touch $RUNFILE_BKP_RCV || Usage "$OFA_ERR Failed touch of file \"$RUNFILE_BKP_RCV\""
    LogIt "Generating RMAN script to file \"$RUNFILE_BKP_RCV\""
    . $RMAN_BKP_GENSCR | tee $RUNFILE_BKP_RCV | LogStdIn

  #
  # Set up generation of recovery script.
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - setup reco script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN RECOVERY script from template script $RMAN_RECO_GENSCR"
    [[ ! -r $RMAN_RECO_GENSCR  ]] && RMAN_RECO_GENSCR=$OFA_MY_ETC/$RMAN_RECO_GENSCR 
    RUNFILE_RECO_RCV=$RMAN_DUMP_PATH/RUNFILE_RECO_${RMAN_TAG}.rcv
    [[ -r $RMAN_RECO_GENSCR ]]  || Usage "$OFA_ERR Failed read of file: \"$RUNFILE_RECO_RCV\""
    touch $RUNFILE_RECO_RCV || Usage "$OFA_ERR Failed touch of file \"$RMAN_RECO_GENSCR\""

  #
  # Make sure there is a pfile and an spfile.
  # Do this here as rman complains when the database hasn-t been started with the spfile.
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - get (s)pfile(s)" && LogCons "$STEP_LABEL"
    DoSqlQ "create spfile from memory;" 2>&1 >/dev/null
    DoSqlQ "create pfile from spfile;" 2>&1 >/dev/null
    LogIt "cp $ORACLE_HOME/dbs/spfile$SID.ora to $RMAN_DUMP_PATH/spfile$SID.$RMAN_TAG.ora"
    cp $ORACLE_HOME/dbs/spfile$SID.ora $RMAN_DUMP_PATH/spfile$SID.$RMAN_TAG.ora 2>/dev/null
    [[ $? -ne 0 ]] && LogWarning "Failed cp $ORACLE_HOME/dbs/spfile$SID.ora"
    LogIt "cp $ORACLE_HOME/dbs/init*$SID.ora to $RMAN_DUMP_PATH/init$SID.ora"
    cp $(ls -1 $ORACLE_HOME/dbs/init_$SID.ora $ORACLE_HOME/dbs/init$SID.ora 2>/dev/null|head -1) $RMAN_DUMP_PATH/ 2>/dev/null
    [[ $? -ne 0 ]] && LogWarning "Failed cp $ORACLE_HOME/dbs/init$SID.ora"

  # 
  # Run the backup
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - run backup" && LogCons "$STEP_LABEL"
    LogIt "Runnung the RMAN BACKUP script \"$RUNFILE_BKP_RCV\""
    . $RUNFILE_BKP_RCV  2>&1 | LogStdIn

  # 
  # Get time stamp for recovery process and generate the recovery script.
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - post-backup queries" && LogCons "$STEP_LABEL"
    CONTROLFILE_AFTER="$RMAN_DUMP_PATH/controlfile_${RMAN_TAG}.after.ctl"
    LogIt "Looking for control file for use with reco script"
    CONTROLFILE=$(ls -1rt $RMAN_DUMP_PATH/${OFA_CTL_FMT_PREFIX}* $CONTROLFILE_AFTER 2>/dev/null | tail -2 | head -1)

    if [[ ! -r "$CONTROLFILE" ]] \
    then
        LogError "Couldn't find suitable backup controlfile for reco script" 
        LogWarning  "No recovery script will be generated." 
    else
        LogIt "Generating RMAN RECOVERY script  \"$RUNFILE_RECO_RCV\"" 
        . $RMAN_RECO_GENSCR | tee $RUNFILE_RECO_RCV | LogStdIn
    fi

  #
  # re-open the database
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - reopen DB" && LogCons "$STEP_LABEL"
    DBSTATUS=$(OraDbStatus)

    [[ "$DBSTATUS" != "MOUNTED" ]] \
        && LogWarning "$SID is in \"$DBSTATUS\" state - expected it be in \"MOUNTED\" state."

    if [[ "$DBSTATUS" = "CLOSED" ]]
    then
        Loginfo "Starting up $SID."
        DoSqlQ "STARTUP" | LogStdIn
    elif [[ "$DBSTATUS" = "OPEN" ]]
    then
        LogIt "$SID is already OPEN - leaving it thus"
    else
        LogIt "$SID is in \"$DBSTATUS\" state - opening it"
        DoSqlQ "ALTER DATABASE OPEN;" | LogStdIn
    fi

    DBSTATUS=$(OraDbStatus)
    [[ "$DBSTATUS" != "OPEN" ]] \
        && BailOut "Coudn't get $SID into \"OPEN\" state. State is now: \"$DBSTATUS\"" \
        || LogIt "$SID is now \"$DBSTATUS\""

  #
  # copy relevant portion of alert log to $OFA_MY_DB_BKP
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - alert log extract" && LogCons "$STEP_LABEL"
    [[ -f $ALERTLOG ]]                                                         \
        && LogIt "Committing relevant portion of $ALERTLOG to record"          \
        && eval $(echo sed -n \'$ALERTLOG_LINES_B4,\$p\' $ALERTLOG) > $OFA_MY_DB_BKP/alert$RMAN_TAG.log \
        || LogWarning "Alert log not captured (possibly couldn't find it)"

  #
  # list contents of backup destination directory
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - list files" && LogCons "$STEP_LABEL"
    ls -ldi $OFA_MY_DB_BKP/* | grep -v $OFA_MY_DB_BKP/to_be_deleted | LogStdIn

  #
  # commit log to $OFA_MY_DB_BKP
  #

  #
  # trap 3: cancel post-processing on exit
  #
    OFA_TRAP_XIT=""
  #
  # finish
  #
    let STEP+=1 && STEP_LABEL="Step: $STEPS/$STEPS - Completed" && LogCons "$STEP_LABEL"
    MailLogReport "$SID: $STEP_LABEL"
    RV=$?
    LogIt "Committing this log to record."
    cp -p $LOGFILE $OFA_MY_DB_BKP
    exit $RV
