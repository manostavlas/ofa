#!/bin/ksh
# -----------------------------------------------------------------------------------------
# Copyright 2012-2013-2013 OnoBase S.a.r.l. (ofa@onobase.com), FreeBSD copyright and disclaimer apply
# -----------------------------------------------------------------------------------------
#
  #
  ## Name: ofa_check.sh
  ##
  ## In:  n.a.
  ## Out: report
  ## Ret: n.a.
  ##
  ## Synopsis: checks compliance with regard to ofa
  ##
  ## Usage: ofa_check.sh <product> [<DB>]
  ##
  ## Description:
  ##
  ##    With "product" alone, only checks base compliance+product: 
  ##      
  ##    - All:	    
  ##        /ofa directory tree structure
  ##        /ofa FS
  ##        /ofa owner+permissions
  ##       
  ##    - Sybase: 
  ##        (nothing for now)
  ##       
  ##    - oracle: 
  ##       - "OFA" paths:
  ##           OFA_DB_ARCH=/arch
  ##           OFA_DB_BKP=/backup
  ##           OFA_DB_DATA=/DB
  ##           OFA_DB_VAR=/oracle
  ##        $ORATAB       is /etc/oratab or equivalent valid, with all running instances listed
  ##        $TNS_ADMIN    is /oracle/rdbms/admin/tns_admin and contains files (not just links)
  ##        $ORACLE_HOME  is /oracle/o<version#>
  ##
  ##    - Oracle: 
  ##        FS:
  ##          - /DB/<SID>           ....    mount point
  ##          - [/arch/<SID>]       ....    mount point  (/arch is not mandatory)
  ##          - /backup/[<SID>]     ....    mount point  ([<SID>] optional for non-prod)
  ##            /backup/<SID>/rman                sub-directory for rman backups
  ##            /backup/<SID>/datapump            sub-directory for datapump
  ##          - /dbvar/<SID>        ....    mount point  
  ##
  ##        DB:
  ##          Listener:
  ##              - listener naming     ....    LISTENER_<SID>
  ##              - local_listener      ....    LISTENER_<SID>
  ##          Directories:
  ##              - DATA_PUMP_DIR       ....    /backup/<SID>/datapump
  ##          Parameters:
  ##              - diagnostic_dest     ....    (>= 11g) /dbvar/<SID>
  ##                background_core_dump ...    (>= 11g) under "diag"
  ##                background_dump_dest ...    (>= 11g) under "diag", else /dvbar/<SID>/log/bdump
  ##                core_dump_dest       ...    (>= 11g) under "diag", else /dvbar/<SID>/log/cdump
  ##                user_dump_dest       ...    (>= 11g) under "diag", else /dvbar/<SID>/log/udump
  ##              - audit_file_dest      ...    (>= 11g) under "diag", else /dvbar/<SID>/log/adump
  ##              - remote_login_passwordfile   EXCLUSIVE
  ##              - log_archive_format
  ##              - spfile			/dbvar/<SID>/admin/pfile/spfile<SID>.ora
  ##          File naming:
  ##              - online redo log file names  *.rdo
  ##              - control file names          *.ctl
  ##              - data file names             *.dbf
  ##
  ## Workings:
  ##
  ##    <Description of how it works>

  
  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

    VolDn 
    SCOPE=$1
    SID=$2

    LoadProgEtc $HOSTNAME 
    CheckVar SCOPE SID || Usage

    [[ $SCOPE != "oracle" ]] && [[ $SCOPE != "sybase" ]] && BailOut "scope must be \"oracle\" or \"sybase\""

    CONF_COUNT_CORE=0
    CONF_OK_CORE=0
    CONF_COUNT_DB=0
    CONF_OK_DB=0

    function MatchItem {
        ITEM=$1
        VALUE=$(eval "echo \$$ITEM")
        EXP_V=$(eval echo \$___${ITEM})
        eval let CONF_COUNT_$SCOPE+=1
        if [[ "$VALUE" = "$EXP_V" ]]
        then
            RV=0
            eval let CONF_OK_$SCOPE+=1
            EXP_V=""
            STATUS="*"
        else
            STATUS="[KO]"
            RV=1
            EXP_V="($EXP_V)"
        fi
        printf "\n  %4s - %3d/%-2d %-25s %-40s %s" \
            "$STATUS" \
            "$(eval echo \$CONF_OK_$SCOPE)" \
            "$(eval echo \$CONF_COUNT_$SCOPE)"  \
            "$ITEM" \
            "$EXP_V" \
            "'$VALUE'"
    }

    function Head1 {
        printf "\n  %4s -  %-5s %-25s %-40s %s" \
             "Stat" \
             "Score" \
             "Item" \
             "(Expected)" \
             "Actual" 
        printf "\n  %4s -  %-5s %-25s %-40s %s" \
             "----" \
             "-----" \
             "----" \
             "----------" \
             "------" 
    }

    function QyMaParm {
        PARM=$1
        eval $PARM=$(DoSqlQ "select value from v\$parameter where name = '$PARM';")
        MatchItem $PARM
    }

    function CheckOracle {
        LittleBanner "Checking directories for $ORACLE_SID"
        Head1
        MatchItem OFA_MY_DB_VAR
        MatchItem OFA_MY_DB_BKP
        MatchItem OFA_MY_DB_DATA
        MatchItem OFA_MY_DB_ARCH
        echo ""
        echo ""
    
        LittleBanner "Checking parameters for $ORACLE_SID"

        Head1
        QyMaParm spfile
        QyMaParm log_archive_dest_1
        QyMaParm diagnostic_dest
        QyMaParm background_dump_dest
        QyMaParm user_dump_dest
        QyMaParm core_dump_dest
        QyMaParm audit_file_dest
        QyMaParm log_archive_format
        QyMaParm local_listener
        echo ""
        echo ""

    }

  #
  # report
  #
    if [[ "$OFA_GRAFT" = "oracle" ]]
    then
        OraEnv $SID
        ShowVar \
            ORACLE_SID \
            OFA_GRAFT \
            OFA_LOAD_SCR \
        | CartRidge
        CheckOracle
    else
        ShowVar \
            OFA_GRAFT \
            OFA_LOAD_SCR \
        | CartRidge
    fi






