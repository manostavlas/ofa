#!/bin/ksh
#                                                     
## Name: rsql.sh
##                                                    
## In:  sql script
## Out: n.a.
## Ret: 0/1
##                                                    
## Synopsis: run script against one or several targets.
##                                                    
## Usage: rsql.sh <script (in_line or file))> [<filter>]
##                                                    
## Description:                                       
##                                                    
##  - Runs sql script or command supplied in arg1 against DBs $RORATAB, filtered by <filter>
##  - Uses MmDp credentials.
##  Note: pre-set using "mdp <username>"
##  - Takes default oracle environment (often last in oratab) unless ORACLE_SID is exported. 
## 
## Note:
##    Interactive only
##    
## Workings:                                          
##                                                    
##  - Uses DoSqlLoggedVerbose
##  - TWO_TASK to appended to connection string.
##    I.e. this script always uses SQL*Net, even locally.
##   
#  ------------------------------------------------------------------------------                                                   
# set -xv
UserId=$(id -u)
OraDbTestCnxOutputTmpFile=/tmp/OraDbTestCnxOutput_${UserId}.log

function OraDbTestCnxOutput {
  #
  # Name: OraDbTestCnx
  #
  # In:  n.a.
  # Out: n.a.
  # Ret: 0/1
  #
  # Synopsis: attempts a connection with select at an instance.
  #
  # Usage: OraDbTestCnx
  #
  # Description:
  #
  #   - Disables any login.sql path by pointing to a path that does nothing.
  #   - runs "sqlplus -S" against the current instance
  #     - Sets WHENEVER SQLERROR EXIT FAILURE pragma.
  #     - Performs a "select 1 from dual".
  #     - Returns return code from sqlplus session.
  #

    typeset _SQLPATH=$SQLPATH
    typeset SQLPATH=$OFA_SQL/ofa/login/nothing
    ORACLE_PATH=$SQLPATH
    sqlplus -S $OFA_DBCNX_STRING  << EOF > $OraDbTestCnxOutputTmpFile 2>&1
       WHENEVER SQLERROR EXIT FAILURE
       SELECT 1 FROM DUAL;
EOF
    typeset _RV=$?
    SQLPATH=$_SQLPATH
    ORACLE_PATH=$SQLPATH
 	ErrorTextSql=$(grep -e ORA- -e SP $OraDbTestCnxOutputTmpFile | head -1 )
	echo "** ${ErrorTextSql} **"
    return $_RV
}

  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22
  #
  # Check Oracle Environment
  #
    ! OraEnv && LogError "Need Oracle Environment"

  #
  # Check Interactive
  #
    # asg ! IsInterActive && "BailOut -- interactive only"

  #
  # syntax
  #
    [[ $# -lt 1 ]] && Usage "args, pls."

  #
  # input file
  #
    typeset _TO_RUN="$1"
    VolSet 1
    if [[ ! -r "$_TO_RUN" ]] && [[ "$_TO_RUN" != *" "* ]]
    then
        Usage "first arg. must be sql input (file or inline)"
    else
        if [[ -r "$_TO_RUN" ]] 
        then
            ls -l "$_TO_RUN" | LogCartRidge
        else
            echo "$_TO_RUN" | LogCartRidge
        fi
        shift 1
    fi
    VolPrv
    Prompt GO "Correct Input ? [Y] => "
    [[ "$GO" != [Yy]* ]] && ExitGently "Canceled by $USER"

  # 
  # initialize iterator "BOB"
  #
    ! IterInit BOB $RORATAB $@ \
        && ExitGently "Not targets found (args \"$@\")" \
    ;

    Prompt GO "Good to GO ? [Y] => "
    [[ "$GO" != [Yy] ]] && VolSet 1 && ExitGently "Canceled by $USER"

  #
  # connection string
  #
    OFA_DBCNX_STRING=$InIts/$MmDp
# asg     MmDp && OFA_DBCNX_STRING=$InIts/$MmDp

OFA_DBCNX_STRING=$InIts/$MmDp

    function GoNoGo {
      #
      # recursive loop
      #
        Prompt GO "run \"$_TO_RUN\" against $InIts@$sid ? [$CONT_DFLT] => "
        if [[ "$GO" = "?" ]]
        then
            help_cmd
            GoNoGo
        elif [[ "$GO" = "!" ]]
        then
            FORCE=1
            GO="Y"
            LogIt "Switch to FORCE THROUGH NON-STOP"
        elif [[ "$GO" != [\<\>0123456789YyNniSsQqLl]* ]] 
        then
            LogCons "Unknown Action : \"$GO\""
            GoNoGo
        fi
        echo "" 1>&2
    }

    function help_cmd {
         VolSet 1
         echo '
             ## -- ============================
             ## -- Interactive Controls Summary
             ## -- ============================
             ## ""    - (nothing) => default command
             ## "Y"   - Proceed with task
             ## "Q"   - Abort
             ## "L"   - List Records
             ## ">"   - Skip task, prompts at next [SsNn]
             ## "<"   - Previous task, prompts again
             ## "#"   - Jump to Task (# being a task number)
             ## "!"   - Force through nonstop
             ## "?" - Help
             ##
         ' | CartRidge
         VolPrv
    }
    echo "Start Work" | LogCartRidge

    RECORD_FORMAT=" sid version startup_flag user host env zone created creator active application comments"
    typeset CARRION=1 
    typeset FORCE=0 
    while IterFetch BOB
    do
        [[ ! -n "$sid" ]] && LogError "No SID -- skip on" && IterNext && continue
        OFFSET=$(LogLineCount)   
        [[ $CARRION -eq 1 ]] && CONT_DFLT="Y" || CONT_DFLT="?"
        [[ $FORCE -ne 1 ]] && GoNoGo || GO="Y"
        if [[ "$GO" = [SsNn\>] ]] 
        then
            echo "" 1>&2
            LogWarning "(skip $sid)" 
            IterNext BOB
            CARRION=1
            continue
        elif [[ "$GO" = [Ll] ]]
        then
            echo "" 1>&2
            LogInfo "List Records"
            IterList BOB
            continue
        elif IsInteger $GO
        then
            echo "" 1>&2
            LogWarning "Jump to step $GO"
            IterJump BOB $GO
            CARRION=1
            continue
        elif [[ "$GO" = "<" ]]
        then
            echo "" 1>&2
            LogInfo "Go back one step"
            IterBack BOB
        elif [[ "$GO" = [Qq] ]] 
        then
            echo "" 1>&2
            ExitGently "User Abort"
        elif [[ "$GO" = [Yy] ]] 
        then

            TWO_TASK="$sid"
            OFA_DBCNX_STRING="$InIts/$MmDp@$sid"

# asg       if  OraDbTestCnx 
	    if OraDbTestCnxOutput
            then
                DoSqlLoggedVerbose "$_TO_RUN"
                echo "" 1>&2
                LogCons "\"$_TO_RUN\" @ $sid - checking log ...)"
                VolSet 1
                if Probe4Error $OFFSET 
                then
                    LogError "Target \"$sid\" failed" 2>&1 | CartRidge
                    CARRION=0
                else
                    LogInfo  "Target \"$sid\" succeeded" 2>&1 | CartRidge
                    CARRION=1 
                fi
                VolPrv
            else
                echo "" 1>&2
                LogError "Check connection $InIts@$sid failed - skipping on !"
		LogError "Error message: ${ErrorTextSql}"
                CARRION=1
            fi
            IterNext BOB
        else
            ExitGently "Unknown Action: \"$GO\""
        fi
    done
