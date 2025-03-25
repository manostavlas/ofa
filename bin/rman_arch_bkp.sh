#!/bin/ksh -p
#
# rman_arch_bkp.sh: perform database backups
#
# Modifications: 
#    20120329 ols - création du fichier
#
# ------------------------------------------------------------------------------
  #
  ## Name: rman_arch_bkp.sh
  ##
  ## In:  Oracle Archive Log Files
  ## Out: Rman Backup ofa Archive Log Files
  ## Ret: 0/1
  ##
  ## Synopsis: backup and delete archived redo log files.
  ##
  ## Usage: rman_arch_bkp.sh <SID> [<name>=<value>]
  ##
  ## Description:
  ## 
  ##   Performs rman backup of archived redo log files.
  ## 
  ##   Backup location
  ##   ===============
  ##   The standard path where the dump lands is $OFA_DB_BKP/<SID>/rman. 
  ##
  #
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
    STEPS=16
    STEP=1
    STEP_LABEL="Step: $STEP/$STEPS - basic settings" && LogCons "$STEP_LABEL"
                LogCons "           - Using template: $RMAN_BKP_GENSCR"

  #
  # The SID: $1 
  #
    STEP=2
    STEP_LABEL="Step: $STEP/$STEPS - setting SID" && LogCons "$STEP_LABEL"
    [[ ! -n $1 ]] \
        && Usage "Supply SID pls" \
        || SID=$1

    RMAN_TAG=$(echo ${SID}_$(Tmsp)|tr [[:lower:]] [[:upper:]])


  #
  # Verify args and connectivity, else fail with Usage
  #
    STEP=4
    STEP_LABEL="Step: $STEP/$STEPS - check connectivity" && LogCons "$STEP_LABEL"
    [[ ! -n $SID ]] && Usage "$OFA_ERR No SID!"
    OraEnv  $SID || Usage "$OFA_ERR Failed OraEnv" 
    OraDbTestCnx    || Usage "$OFA_ERR Failed connection test to $SID"

  #
  # Check variable completeness 
  #
    STEP=9
    STEP_LABEL="Step: $STEP/$STEPS - check variable completeness" && LogCons "$STEP_LABEL"
    LogIt "Check variable completeness"
    CheckVar                    \
           CHANNELS            \
           OFA_ERR_PAT         \
           OFA_MY_DB_BKP           \
           PIECESIZE           \
           RMAN_BKP_GENSCR     \
        && LogIt "Variables complete" \
        || Usage "$OFA_ERR Variables vides ci-avant - fournir les valeurs manquantes"

  # ----------------------------------------------------------------------------
  # All pre-requisites are checked okay. 
  # Proceed.
  # ----------------------------------------------------------------------------

  #
  ## The "TAG" feature
  ## =================
  ## The $TAG variable, if supplied, extends the $OFA_MY_DB_BKP path, which is the default
  ## backup destination. The tag may be itself a path of any permissible depth.
  #
    STEP=11
    STEP_LABEL="Step: $STEP/$STEPS - custom backup tag" && LogCons "$STEP_LABEL"
    if [[ -n $TAG ]];then
        LogIt "Extpanding RMAN backup dump path \"$OFA_MY_DB_BKP\" by \"$TAG\""
        RMAN_DUMP_PATH=$(StraightPath $OFA_MY_DB_BKP/$TAG)
    else
        RMAN_DUMP_PATH=$OFA_MY_DB_BKP
        LogIt "RMAN backup dump path is $RMAN_DUMP_PATH"
    fi
    mkdir -p $RMAN_DUMP_PATH 
    [[ ! -d $RMAN_DUMP_PATH ]] && Usage "Error: Failed to create direcroy $RMAN_DUMP_PATH"
    LogIt "RMAN backup dump path is $RMAN_DUMP_PATH"
    [[ ! -w $RMAN_DUMP_PATH ]] && Usage "Error: direcroy $RMAN_DUMP_PATH is not writeable"

  #
  # Generate backup script
  #
    STEP=13
    STEP_LABEL="Step: $STEP/$STEPS - generate backup script" && LogCons "$STEP_LABEL"
    LogIt "setting up generation of RMAN BACKUP script from template script $RMAN_BKP_GENSCR"
    [[ ! -r $RMAN_BKP_GENSCR  ]] && RMAN_BKP_GENSCR=$OFA_MY_ETC/$RMAN_BKP_GENSCR 
    [[ -r $RMAN_BKP_GENSCR ]]  || Usage "$OFA_ERR Failed read of file: \"$RMAN_BKP_GENSCR\""
    RUNFILE_BKP_RCV=$RMAN_DUMP_PATH/RUNFILE_BKP_${RMAN_TAG}.rcv
    touch $RUNFILE_BKP_RCV || Usage "$OFA_ERR Failed touch of file \"$RUNFILE_BKP_RCV\""
    LogIt "Generating RMAN script to file \"$RUNFILE_BKP_RCV\""
    . $RMAN_BKP_GENSCR | tee $RUNFILE_BKP_RCV | LogStdIn

  # 
  # Run the backup
  #
    STEP=14
    STEP_LABEL="Step: $STEP/$STEPS - run backup" && LogCons "$STEP_LABEL"
    LogIt "Runnung the RMAN ARCHIVE BACKUP script \"$RUNFILE_BKP_RCV\""
    . $RUNFILE_BKP_RCV  2>&1 | LogStdIn
    rm -f $RUNFILE_BKP_RCV 

  #
  # trap 2: Cancel Trap
  #
    trap '' INT TERM EXIT
  #
  # finish
  #
    STEP=16
    STEP_LABEL="Step: $STEPS/$STEPS - Completed" && LogCons "$STEP_LABEL"
    MailLogReport "$SID: $STEP_LABEL"
    RV=$?
    LogIt "Committing this log to record."
    LogIt "END"
    exit $RV


