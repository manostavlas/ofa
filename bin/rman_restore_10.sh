#!/bin/ksh
#
  # ------------------------------------------------------------------------------
  ##
  ## Name: rman_restore_RAC.sh
  ## 
  ## Synopsis: Restore ASM/RAC database from backup
  ## 
  ## Usage: rman_restore_RAC.sh <SID> <SOURCE_SID>
  ##
  # ------------------------------------------------------------------------------



  #
  # load ofa
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

 # set -vx
  #
  # The SID: $1
  #
    [[ -z $1 ]] \
        && LogError "Usage: rman_restore_RAC.sh <SID> <SOURCE_SID>" && exit 1

  #
  # The SID: $2
  #
    [[ -z $2 ]] \
        && LogError "Usage: rman_restore_RAC.sh <SID> <SOURCE_SID>" && exit 1


  #
  # must be sysdba
  #
    ImaSysDba || BailOut "Backup of $ORACLE_SID requires sysdba"

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
    [[ -z $1 ]] \
        && Usage "Supply SID pls" \
        || SID=$1


  #
  # Verify args and connectivity, else fail with Usage
  # SID
  #
    let STEP+=1 && STEP_LABEL="Step: 3/$STEPS - check connectivity" && LogCons "$STEP_LABEL"
    [[ ! -n $SID ]] && Usage "$OFA_ERR No SID!"
    OraEnv  $SID 2>&1 >/dev/null || Usage "$OFA_ERR Failed OraEnv"

  #
  # check that no other rman task is running on the same target from ofa
  #
    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  #
  # The SID_SOURCE: $2
  #
    let STEP+=1 && STEP_LABEL="Step: 4/$STEPS - setting SID_SOURCE" && LogCons "$STEP_LABEL"
    [[ ! -n $2 ]] \
        && Usage "Supply SID_SOURCE pls" \
        || SID_SOURCE=$2

  #
  # Verify args and connectivity, else fail with Usage
  # SID_SOURCE
  #
    let STEP+=1 && STEP_LABEL="Step: 5/$STEPS - check connectivity" && LogCons "$STEP_LABEL"
    [[ ! -n $SID_SOURCE ]] && Usage "$OFA_ERR No SID!"
    OraEnv  $SID_SOURCE 2>&1 >/dev/null || Usage "$OFA_ERR Failed OraEnv"

  #
  # check that no other rman task is running on the same target from ofa
  #
    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  #
  # Check variable completeness
  #
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - check variable completeness" && LogCons "$STEP_LABEL"
    CheckVar \
           CHANNELS \
           DB_STOP_COMMAND \
           OFA_ERR_PAT \
           FILESPERSET \
           OFA_MY_DB_BKP \
           PIECESIZE \
           CLEAR_TO_DEL_INCL_ARC \
           RMAN_BKP_GENSCR \
           RMAN_RECO_GENSCR \
           OFA_DB_DATA \
           OFA_DB_BKP \
        && LogCons "Variables check complete" \
        || Usage "$OFA_ERR Variables missing"

  #
  # Check if restore script exist
  #


    if [ -r /$OFA_DB_BKP/$SID_SOURCE/rman/RestoreParam_rst_${SID_SOURCE}.rman ]; then
       SourceRestoreParam=/$OFA_DB_BKP/$SID_SOURCE/rman/RestoreParam_rst_${SID_SOURCE}.rman
    else
       SourceRestoreParam=/$OFA_DB_BKP/$SID_SOURCE/RestoreParam_rst_${SID_SOURCE}.rman
    fi

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Check if restore parameter file exist ($SourceRestoreParam)" && LogCons "$STEP_LABEL"
    [[ -r $SourceRestoreParam ]] || BailOut "$SourceRestoreParam not readable"

  #
  # Set Variables
  #
  export NLS_DATE_FORMAT="DD-MM-YYYY_HH24MISS"
  export RestoreDir=$OFA_SCR/refresh/$SID

  #
  # Check Dir
  #

  [[ ! -d  $RestoreDir ]] && mkdir -p $RestoreDir

  # ----------------------------------------------------------------------------
  # All pre-requisites are checked okay.
  # Proceed with interaction now.
  # ----------------------------------------------------------------------------

#------------------------------------------------------------------------
RestoreDatabase()
#------------------------------------------------------------------------
{
  #
  # Shutdow DB's
  #
    OraEnv $SID 2>&1 >/dev/null
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Shutdown abort $ORACLE_SID" && LogCons "$STEP_LABEL"
        LogCons "running $DB_STOP_COMMAND"
        eval $DB_STOP_COMMAND | LogStdIn

    OraEnv $SID_SOURCE 2>&1 >/dev/null
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Shutdown abort $ORACLE_SID" && LogCons "$STEP_LABEL"
        LogCons "running $DB_STOP_COMMAND"
        eval $DB_STOP_COMMAND | LogStdIn

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Remove old database files ${OFA_DB_DATA}/${SID}/*" && LogCons "$STEP_LABEL"
    rm /${OFA_DB_DATA}/${SID}/* > /dev/null 2>&1 
    LogCons "Delete /${OFA_DB_DATA}/${SID}/*"
    rm /arch/${SID}/* > /dev/null 2>&1 
    LogCons "Delete /arch/${SID}/*"

  #
  # Put DB into NoMounted state
  #

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Startup nomount $ORACLE_SID" && LogCons "$STEP_LABEL"
    DBSTATUS=$(OraDbStatus)
    LogIt "$ORACLE_SID is in \"$DBSTATUS\" state. Starting it into mount exclusive state"
    DoSqlQ "STARTUP NOMOUNT EXCLUSIVE;" | LogStdIn

    DBSTATUS=$(OraDbStatus)
    [[ "$DBSTATUS" != "STARTED" ]] && BailOut "Coudn't get $ORACLE_SID into \"STARTED\" state. State is now: \"$DBSTATUS\""
    LogIt "$ORACLE_SID is in \"$DBSTATUS\" state. Proceeding."

  #
  #  Restore the control file
  #
     let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Finding the control file" && LogCons "$STEP_LABEL"
     # ControlFileName=controlfile_*.before.ctl
     # ControlFileName=bck_control_file_*-00.ctl
     ControlFileName=controlfile_*.after.ctl
     ControlFile=$(ls -1 ${OFA_DB_BKP}/${SID_SOURCE}/${ControlFileName} 2> /dev/null)
     
    if [ -r "${ControlFile}" ]; then
       LogCons "Using control file ${ControlFile}"
    else 
       ControlFile=$(ls -1 ${OFA_DB_BKP}/${SID_SOURCE}/rman/${ControlFileName} 2> /dev/null)
       if [ -r "${ControlFile}" ]; then
          LogCons "Using control file ${ControlFile}"
       fi
    fi

    if [ -z "${ControlFile}" ];then
        LogError "Control file not found ${OFA_DB_BKP}/${SID_SOURCE}/${ControlFileName}"
	exit 1
    fi

     let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Restore control file" && LogCons "$STEP_LABEL"

     rman << EOF 2>&1 | LogStdIn
     connect target /
     restore controlfile from '${ControlFile}'; 
     alter database mount;
EOF

     ErrorMessage=$(tail -n 10 $LOGFILE | grep "RMAN-" )

    if [ ! -z "${ErrorMessage}" ];then
        LogError "Error restore Control File"
        exit 1
    fi

  #
  # Create restore file.
  #

    RmanDatabaseRestore=$RestoreDir/RestoreDatabase_$SID_SOURCE.rman

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Create database restore file ($RmanDatabaseRestore)." && LogCons "$STEP_LABEL"


    # Set connect

    echo "
    connect target /
    run
    { " > $RmanDatabaseRestore
  
    # Allocate channels
  
    i=$CHANNELS
    while [[ $i -gt 0 ]];do
       echo "    allocate channel c$i type disk;"  
       let i-=1
    done | sort >> $RmanDatabaseRestore
    
    DatabaseDir="\\${OFA_DB_DATA}\/$SID"
    
    # Set Datbase dir.

    while read line
    do
    echo $line | sed "s/DATABASE_PATH/$DatabaseDir/g" >> $RmanDatabaseRestore

    done < "$SourceRestoreParam"

    # Set Restore command

    echo "
    restore database;
    switch datafile all;
    switch tempfile all; " >> $RmanDatabaseRestore

    # Release channels

    i=$CHANNELS
    while [[ $i -gt 0 ]];do
       echo "    release channel c$i;"  
       let i-=1
    done | sort >> $RmanDatabaseRestore

    echo "    }" >> $RmanDatabaseRestore

  #
  # Start restore of database
  # 

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Start restore of database $SID_SOURCE Logfile: $LOGFILE" && LogCons "$STEP_LABEL"

    OraEnv $SID_SOURCE 2>&1 >/dev/null

    rman < $RmanDatabaseRestore 2>&1 | LogStdIn


     ErrorMessage=$(grep "RMAN-" $LOGFILE | grep -v "OFA_ERR_PAT")

    if [ ! -z "${ErrorMessage}" ];then
        LogError "Error restore Database"
        exit 1
    fi
}
#------------------------------------------------------------------------
RecoverDatabase()
#------------------------------------------------------------------------
{
  #
  # Get archive backup list.
  # 
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Get archive backup list." && LogCons "$STEP_LABEL"

    BackupList=$RestoreDir/BackupList_$SID_SOURCE.lst

    rm $BackupList 2>/dev/null   

 
    rman << EOF > $BackupList
    connect target /
    list backup summary;
    exit
EOF


    RecoverScript=$RestoreDir/RecoverScript_$SID_SOURCE.rman
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Create Recover script ($RecoverScript) " && LogCons "$STEP_LABEL"
    RestoreTime=$(cat $BackupList | grep DISK | tail -n 1 | awk '{print $6}')

    LogCons "Restore Completion Time: $RestoreTime"


    # Set connect

    echo "
    connect target /
    run
    { " > $RecoverScript

    # Allocate channels

    i=$CHANNELS
    while [[ $i -gt 0 ]];do
       echo "    allocate channel c$i type disk;"
       let i-=1
    done | sort >> $RecoverScript

    sqlplus -s "/as sysdba" << EOF >> $RecoverScript
    WHENEVER SQLERROR exit 1
    set echo off;
    set feedback off;
    set timing off;
    set heading off;
    select 'set until sequence '||a.SEQUENCE#||' thread '||THREAD#||';'||chr(10)||'recover database;' 
       from V\$LOG_HISTORY a 
      where FIRST_TIME = 
         ( SELECT MAX(b.FIRST_TIME) 
             FROM V\$LOG_HISTORY b
            WHERE b.FIRST_TIME < to_date('$RestoreTime', 'DD-MM-YYYY_HH24MISS') 
         ) ;
EOF

    if [ $? -ne 0 ];then
        LogError "Error create Recover Script ($RecoverScript)"
        exit 1
    fi

    # Release channels

    i=$CHANNELS
    while [[ $i -gt 0 ]];do
       echo "    release channel c$i;"
       let i-=1
    done | sort >> $RecoverScript

    echo "    }" >> $RecoverScript

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Recover Database " && LogCons "$STEP_LABEL"

    rman < $RecoverScript 2>&1 | LogStdIn

     ErrorMessage=$(tail -n 10 $LOGFILE | grep "RMAN-" )

    if [ ! -z "${ErrorMessage}" ];then
        LogError "Error Recover Database running: $RecoverScript"
        exit 1
    fi
}
#----------------------------------------------
OpenDatabase()
#----------------------------------------------
{

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Open database reset log." && LogCons "$STEP_LABEL"

    sqlplus -s "/as sysdba" << EOF 2>&1 | LogStdIn
    WHENEVER SQLERROR exit 1
    set echo off;
    set feedback off;
    set timing off;
    set heading off;
    prompt Running: alter database open resetlogs;
    alter database open resetlogs;     
    prompt Running: shutdown immediate;
    shutdown immediate;
    exit 
EOF

    if [ $? -ne 0 ];then
        LogError "Error Open database reset log."
        exit 1
    fi


}
#----------------------------------------------
RenameDatabase()
#----------------------------------------------
{

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Rename Database ${SID_SOURCE} -> ${SID}." && LogCons "$STEP_LABEL"

    # Mount exclusive

    sqlplus -s "/as sysdba" << EOF 2>&1 | LogStdIn
    WHENEVER SQLERROR exit 1
    set echo off;
    set feedback off;
    set timing off;
    set heading off;
    startup mount exclusive;
    exit;

EOF
    if [ $? -ne 0 ];then
        LogError "Error by startup mount."
        exit 1
    fi

    # Rename DB
    echo Y > /tmp/replay
    nid target=/ dbname=$SID setname=y  < /tmp/replay 2>&1 | LogStdIn

    ErrorMessage=$(tail -n 10 $LOGFILE | grep "Completed succesfully")
    if [ -z "$ErrorMessage" ];then
        LogError "Error by nid target=/ dbname=$SID setname=y"
        exit 1
    fi
}
#----------------------------------------------
StopJobs()
#----------------------------------------------
{
    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Stop all jobs" && LogCons "$STEP_LABEL"

    # Set new SID

    OraEnv  $SID 2>&1 >/dev/null || Usage "$OFA_ERR Failed OraEnv"

    # Startup restrict

    sqlplus -s "/as sysdba" << EOF 2>&1 | LogStdIn
    WHENEVER SQLERROR exit 1
    set echo off;
    set feedback off;
    set timing off;
    set heading off;
    -- Startup
    STARTUP FORCE RESTRICT;
    -- Stop jobs
    SET serveroutput on;
    SET feedback off;
    set long 500000;
    set longchunksize 200000;
    set linesize 500;
    set trimout on;
    set trimspool on;
    spool $RestoreDir/mvjob_stop_rst_restore.sql
    prompt WHENEVER SQLERROR exit 1
    DECLARE
    v_sql_stop      VARCHAR2 (4000);
    BEGIN
    -- Stop Job
       FOR tt IN (SELECT 'exec dbms_ijob.next_date('||a.job||',null);'||chr(10)||'commit;' as SQL_INDEX, RNAME
       from dba_jobs a, all_refresh b
       where a.job=b.job order by 1)


       LOOP
         DBMS_OUTPUT.put_line ('--Stop Job '||tt.rname||' SQL: '||chr(10)||tt.SQL_INDEX);
       END LOOP;
    END;
    /
    spool off;
    @$RestoreDir/mvjob_stop_rst_restore.sql
    exit;
EOF
    if [ $? -ne 0 ];then
        sqlplus -s "/as sysdba" << EOF 2>&1 | LogStdIn
        set echo off;
        set feedback off;
        set timing off;
        set heading off;
        shutdown abort;
        exit;
EOF

        LogError "Error by Stop jobs"
        exit 1
    fi

    let STEP+=1 && STEP_LABEL="Step: $STEP/$STEPS - Create spfile " && LogCons "$STEP_LABEL"

    # Restart DB 

    sqlplus -s "/as sysdba" << EOF 2>&1 | LogStdIn
    WHENEVER SQLERROR exit 1
    set echo off;
    set feedback off;
    set timing off;
    set heading off;
    shutdown immediate;
    create spfile from pfile;
    STARTUP;
    exit;

EOF
    if [ $? -ne 0 ];then
        LogError "Error by create spfile / STARTUP"
        exit 1
    fi

}
#----------------------------------------------
# MAIN
#----------------------------------------------

RestoreDatabase
RecoverDatabase
OpenDatabase
RenameDatabase
StopJobs
