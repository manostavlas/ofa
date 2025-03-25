#!/bin/ksh -p
# -----------------------------------------------------------------------------------------
# Copyright 2012-2013-2013 OnoBase S.a.r.l. (ofa@onobase.com), FreeBSD copyright and disclaimer apply
# -----------------------------------------------------------------------------------------
  #
  ## Name: ofa_step.sh
  ##
  ## In: Commands File
  ## Out: Output from Commands in Commands File
  ## Ret: 0/1
  ##
  ## Synopsis: 
  ##        Interactive / Batch Launcher
  ##        Run tasks from file (STEPLIST)
  ##
  ## Usage: ofa_step.sh <STEPLIST> [<override assignments>]
  ##     
  ## - SHOW=Y: Only show variables, do not run (as with any ofa script)
  ## - FORCE=Y: Keeps "continue"-flag to "Y" even after a failure. 
  ## .          In batch, inhibits the bailout that would otherwise ensue. 
  ## . LOG_DIR=[DIRECTORY_NAME] Set a new log directory. A copy will be
  ## 		create in the ofa default logs directory.
  ##          
  ## Description:
  ##        - Tasks are one-liners in STEPLIST file
  ##        - Tasks may be chained with semi-colons on the same line.
  ##        - Tasks may be piped on the same line.
  ##        - Tasks cannot be interactive (no "user prompts"). 
  ##        - Everything is logged to the same LOGFILE
  ##        - Error handling is performed after each task.
  ##        - Automatic switch from Interactive to Batch Mode  (e.g. in Control-M)
  ##     
  ## Caveats & Advice:
  ## =================
  ##    * Quotes in in-line commands might cause unpredicted behaviour:
  ##      To avoid this pitfall, 
  ##       - Test in interactive mode (carefully, of course)
  ##       - prefer file-based steps whenever practical.
  ##      E.g.:
  ##           DoSqlQ "select status from v$instance;"  # might fail
  ##           DoSqlQ select status from v$instance;    # might work
  ##           DoSqlQ SCRIPT_THAT_DOES_THE_SELECT.sql   # works as expected
  ##      
  ##    * In EVAL mode (default) Steps cannot communicate with one another
  ##      This means that any variable assigments, return codes, directory
  ##      changes e.a., are lost between one step and the next. 
  ##      Conversely, all variables loaded during the initialization phase, 
  ##      i.e. from the parameter files, are guaranteed to be the same at 
  ##      entering each step. 
  ##      In non-EVAL mode, this is not true (this mode is not generally recommended)
  ##
  #  
  #  ================
  #  FOR MAINTAINERS: 
  #  ================
  #  A Note On PIPES:
  #  ---------------------------------
  #   - A pipe eats everything: input, output and variable assignments. 
  #   - The truth is they create CLOSURES. 
  #   - I.e. 
  #     - Anything produced left a pipe and not written to disk is LOST FOREVER. 
  #       e.g. variable assignments, changes directory (cd), ...
  #     - Tasks have no access to Stdin !
  #     - each eval expression creates such a closure
  #     - steps are generally executed inside an "eval" (default of EVAL_FLG is "1")
  #   - Understand this and you will fare safely. 
  #  A Note On Thse Big Main Loop:
  #  ---------------------------------
  #  I'm dreadfully sorry for the big main loop. 
  #  It would have stayed elegantly small, had there not been my urge to include 
  #  the "previous task"-feature. 
  #  I hope that feature will make up for the ugliness of the loop. 
  # 
  # ------------------------------------------------------------------------------
# set -xv
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

 YesNo $(basename $0) || exit 1 && export RunOneTime=YES


    CheckFile \
        LOGFILE \
    || BailOut "no LOGFILE (make sure you're running with OFA_SCRIPT_AUTO_INIT=1)"

  #
  # Check variable completeness
  #
    STEP_LABEL="check variable completeness" && LogCons "$STEP_LABEL"
    LogIt "Check variable completeness"
    CheckVar                      \
        OFA_SCR                   \
        EVAL                      \
        FIRST                     \
        FORCE                     \
        LAST                      \
        SKIP                      \
        STEPLIST                  \
        STEP_PROMPT               \
     && LogIt "Variables complete" \
     || Usage "$OFA_ERR Mandatory Variables Empty - warnings"

  RunMmDp

  #----------------------------------------------------------------------
  # functions
  #----------------------------------------------------------------------
    function set_new_log {
	if [[ ! -z $LOG_DIR ]]
	then
	 	if [[ -d $LOG_DIR ]] && [[ -r $LOG_DIR ]] && [[ -w $LOG_DIR ]]
		then
			LOGFILE_SHORT=$(echo $LOGFILE | awk -F "/" '{print $NF}')
			LOGFILE_OLD=$LOGFILE
			LOGFILE=${LOG_DIR}/${OFA_WHOSTALKING}/${LOGFILE_SHORT}
			mkdir -p ${LOG_DIR}/$OFA_WHOSTALKING || BailOut "Can't write to directory: ${LOG_DIR}/$OFA_WHOSTALKING"
			LogCons "Log file name: $LOGFILE_SHORT"
			LogCons "Default log file: $LOGFILE_OLD"
			LogCons "New Log file: $LOGFILE"
            >$LOGFILE
            chmod 777 $LOGFILE

		else 
			BailOut "Log directory don't exist or can't read or write: $LOG_DIR"
		fi
  	fi 
    }
    
    function copy_log_to_default {
        if [[ ! -z $LOG_DIR ]]
        then
		cp $LOGFILE $LOGFILE_OLD >/dev/null 2>&1
	fi
    } 

    function list_tasks {
        egrep -vi "^ *$|^ *#|^ *REM|^ *\-\-" $STEPLIST
        [[ $PROMPT_MODE = "ON" ]] && echo Finish
    }

    function Finish {
        return
    }

    function get_task {
        if [[ ! -n "$TASK_CNT" ]] 
        then
            LogCons "Empty Task Number" 
            CURRENT_TASK=""
        elif [[ $TASK_CNT -lt 1 ]] 
        then
            CURRENT_TASK=""
        elif [[ $TASK_CNT -gt $TASK_TOT ]]
        then
            CURRENT_TASK=""
        else
            CURRENT_TASK="$(list_tasks | sed -n "${TASK_CNT}p")"
        fi
        [[ -n "$CURRENT_TASK" ]] && echo "$CURRENT_TASK" || return 1
    }

    function get_task_total {
        list_tasks|awk 'END{print NR}'
    }

    function iter_task_nums {
        TASK_TOT=$(get_task_total)
        typeset n=0
        while [[ $n -lt $TASK_TOT ]]
        do
            let n+=1
            echo $n
        done
    }

    function is_skip {
        RV=1
        [[ $FIRST -gt $TASK_CNT ]] && RV=0
        [[ $LAST  -le $TASK_CNT ]] && RV=0
        echo "$TASK_CNT" | egrep "$SKIP" >/dev/null && RV=0
        return $RV
    }

    function get_prev_task_num {
        TASK_CNT_SVE=$TASK_CNT
        for TASK_CNT in $(iter_task_nums)
        do
            is_skip && continue
            if [[ $TASK_CNT -eq $TASK_CNT_SVE ]]
            then
                previous=${previous:-"$TASK_CNT"}
                [[ $previous -eq $TASK_CNT_SVE ]] && echo "No Previous Task" | CartRidge | LogStdIn
                echo $previous
                break
            fi
            previous=$TASK_CNT
        done
    }

    function get_max_task_num {
        for i in $(iter_task_nums)
        do
            is_skip && continue
            previous=${previous:-"$i"}
            previous=$i
        done
        echo $previous
    }

    function help_cmd {
         echo '
             ## -- ============================
             ## -- Interactive Controls Summary
             ## -- ============================
             ## ""    - (nothing) => default command
             ## "Y"   - Proceed with task
             ## "Q"   - Abort
             ## "P"   - Peek (see interpolated command)
             ## ">"   - Skip task, prompts at next
             ## "<"   - Previous task, prompts again
             ## "!"   - Switch to Batch Mode
             ## "#"   - Jump to Task (# being a task number)
             ## "H|?" - Help
             ##
         ' | CartRidge | LogStdIn
    }
  #-------------------------------------------------------------------
  # Main 
  #-------------------------------------------------------------------

  #
  # Change log directory parameter LOG_DIR
  #

    set_new_log 

  #
  # Base settings
  #
    LOG_OFFSET=1
    SKIP_CNT=0
    PREV_CNT=0

  #
  # If STEPLIST has a slash in it, it must be a file under the current path
  #
       [[ "$STEPLIST" = *"/"* ]] \
    && [[ ! -s $STEPLIST ]]     \
    && BailOut "not a file: $STEPLIST"
  #
  # If STEPLIST is a file, it may be an absolute or relative path, 
  # and it might contain slashes or not.
  #
    if [[ -s "$STEPLIST" ]]
    then
        if [[ "$STEPLIST" = "/"* ]] 
        then
          #
          # STEPLIST starting with "/" means an absolute path
          #
            RUN_DIR="$(StraightPath $(dirname $STEPLIST))"
            LogIt "RUN_DIR: $RUN_DIR (absolute)"
        else 
          #
          # STEPLIST _not_ starting with "/" means a relative path
          #
            RUN_DIR="$(StraightPath $(pwd)/$(dirname $STEPLIST))"
            LogIt "RUN_DIR: $RUN_DIR (relative)"
        fi
        STEPLIST=$(basename $STEPLIST)
    else
  #
  # If STEPLIST is not a file, attempt to find it under the $OFA_SCR path
  # and it might contain slashes or not.
  #
    LogIt "$STEPLIST is not a file - attempting to locate it"
      #
      # Attempt to find a file matching $STEPLIST.
      # This is only an option when exactly one match is found. 
      #
        STEPLIST_MATCHES=$(find $OFA_SCR $OFA_SQL $OFA_BIN $OFA_ETC -type f -name "$STEPLIST" | awk 'END{print NR}')
        if [[ $STEPLIST_MATCHES -gt 1 ]]
        then
            BailOut "Am-${STEPLIST_MATCHES}-guous: more than 1 file matches \"$STEPLIST\""
        elif [[ $STEPLIST_MATCHES -eq 1 ]] 
        then
          #
          # Bingo, there was exactly one match. 
          # Repeat the search using the same "find" expression as above, but this time getting the file path and name,
          # rather than the count.
          #
            LogIt "Bingo - there is exactly one match for $STEPLIST -- repeat the find to assign path"
            LogIt "find $OFA_SCR $OFA_SQL $OFA_BIN $OFA_ETC -type f -name $STEPLIST"
            STEPLIST="$(find $OFA_SCR $OFA_SQL $OFA_BIN -type f -name $STEPLIST)"
            RUN_DIR="$(dirname $STEPLIST)"
            STEPLIST="$(basename $STEPLIST)"
            LogIt "RUN_DIR: $RUN_DIR (found)"
        # else
            # nothing happens - no file named $STEPLIST.
            # Path to STEPLIST might yet be indicated in ETC file
        fi
    fi

  # 
  # - Parse contents of SKIP parameter and
  #   make its commas and spaces into pipes "|".
  #   Note that there are not meant to be any spaces 
  #   but it can handle them should one insist.
  #
    if [[ "$SKIP" = *","* ]] || [[ "$SKIP" = *" "* ]]
    then
        LogIt "Parsing SKIP parameter"
        SKIP="$(echo $SKIP | sed 's@^[, ]*@@;s@[, ]$@@')"  # strip front & trailing spaces & commas
        SKIP="^$SKIP"                                      # pre-pend caret
        SKIP="$(echo $SKIP | sed 's/[, ][, ]*/\$|\^/g')"   # make all commas and/or spaces into separators for egrep 
        SKIP="${SKIP}\$"                                   # append a dollar sign
        CheckVar SKIP                                      # Log information about SKIP variable contents
    fi

  #
  # FORCE flag
  # keeps CONT_DFLT to "Y" at all times.
  #
    [[ "$FORCE" = [1yY]* ]] && FORCE_FLG=1 || FORCE_FLG=0
    LogIt "FORCE flag is \"$FORCE_FLG\""
  #
  # EVAL MODE: 1 or 0
  #
    [[ "$EVAL" = [1yY]* ]] && EVAL_FLG=1 || EVAL_FLG=0
    LogIt "EVAL flag is \"$EVAL_FLG\""

  # 
  # - Change directory to the working directory 
  # - Retrieve Steplist from there
  #
    cd $RUN_DIR || BailOut "Failed cd $RUN_DIR"
    [[ ! -s "$STEPLIST" ]] || [[ ! -r "$STEPLIST" ]] && BailOut "Cannot read STEPLIST file $STEPLIST"

  #
  # Set PROMPT_MODE (test is entered only if interactive)
  #
    if IsInterActive
    then
       if [[ $STEP_PROMPT = [1yYoO]* ]] 
       then
           CONT_DFLT="Y" 
           PROMPT_MODE="ON" 
       else
           PROMPT_MODE="OFF"
       fi
    else
       PROMPT_MODE="OFF"
       [[ $STEP_PROMPT = [1yYoO]* ]] && LogCons "Batch Mode: Prompt Mode switched OFF"
    fi

  #
  # loop over STEPLIST BUT DON'T RUN
  #
    STEP_LABEL="Display Task List" && LogCons "$STEP_LABEL"
    TASK_TOT=$(get_task_total)
    VolUp 2
    for TASK_CNT in $(iter_task_nums)
    do
        CURRENT_TASK="$(get_task)"
        if $(is_skip)
            then
            echo "SKIP: [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK"
        else
            echo "DO : [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK"
        fi
    done | CartRidge | LogStdIn
    VolDn 2
    LogCons "Interactive Step Prompt is \"$PROMPT_MODE\""
    LogCons "Eval-flag is \"$EVAL_FLG\""
    LogCons "FORCE flag is \"$FORCE_FLG\""

  # ----------------------------------------------------------------------------
  # All pre-requisites are checked okay.
  # Proceed with interaction now.
  # ----------------------------------------------------------------------------

  #
  # Loop over STEPLIST and RUN
  #
    STEP_LABEL="Process Task List \"$STEPLIST\"" && LogCons "$STEP_LABEL"
    TASK_TOT=$(get_task_total)
    LOG_OFFSET=$(LogLineCount)
    SUCCESS=1
    TASK_CNT=1
    TASK_MAX=$(get_max_task_num)
    FAIL_CNT=0
    SUCC_CNT=0
    [[ $PROMPT_MODE = "ON" ]] && VolSet 1
    CURRENT_TASK="$(get_task)"
    while [[ -n "$CURRENT_TASK" ]]
    do
        if is_skip
        then
            LogCons "SKIPPING (PER \"SKIP\" PARM): [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK"
            let TASK_CNT+=1
            [[ $TASK_CNT -le $TASK_TOT ]] && CURRENT_TASK="$(get_task)" || CURRENT_TASK=""
            continue
        else
            if [[ $PROMPT_MODE = "ON" ]]
            then
              # --
              # PROMPT ENABLED
              #
                if [[ $SUCCESS -eq 0 ]]
                then
                    printf "\t%s\n" "Now: [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK" | CartRidge | LogStdIn
                    printf "\n\tREALLY Continue ? (Y|Q|P|<|>|!|?|#) [%s] => " "$CONT_DFLT"
                else
                    printf "\n\t%s\n\n" "Now: [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK" | CartRidge | LogStdIn
                    printf "\n\tContinue ? (Y|Q|P|<|>|!|?|#) [%s] => " "$CONT_DFLT"
                fi
                read $OFA_READ_TIME_OUT ans
                ans=${ans:-"$CONT_DFLT"}
                if [[ $ans = [YyoO]* ]]
                then
                    echo "Interactive Response was \"$ans\" - Proceed with task [$TASK_CNT/$TASK_TOT]" | CartRidge | LogStdIn
                elif [[ $ans = [qQ]* ]]
                then
                    LogWarning "Interactive Response was \"$ans\" - ABORT"
                    TASK_CNT=$TASK_MAX
                    CURRENT_TASK="$(get_task)"
                elif [[ $ans = "!" ]]
                then
                    echo "Interactive Response was \"$ans\" - ENTERING BATCH MODE" | CartRidge | LogStdIn
                    PROMPT_MODE="OFF"
                elif [[ $ans = ">" ]]
                then
                    let SKIP_CNT+=1
                    echo "Interactive Response was \"$ans\" - SKIP [$TASK_CNT/$TASK_TOT]" | CartRidge | LogStdIn
                    LogCons "SKIPPING (PER REQUEST): [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK"
                    let TASK_CNT+=1
                    [[ $TASK_CNT -le $TASK_TOT ]] && CURRENT_TASK=$(get_task) || CURRENT_TASK=""
                    continue
                elif [[ $ans = "<" ]]
                then
                    let PRIV_CNT+=1
                    TASK_CNT=$(get_prev_task_num)
                    CURRENT_TASK="$(get_task)"
                    echo "Interactive Response was \"$ans\" - PREVIOUS [$TASK_CNT/$TASK_TOT] - CONFIRM AT PROMPT" | CartRidge | LogStdIn
                    continue
                elif [[ $ans = [pP]* ]]
                then
                    echo "Interactive Response was \"$ans\" - PEEK [$TASK_CNT/$TASK_TOT]" | CartRidge | LogStdIn
                    if [[ $EVAL_FLG -eq 1 ]]
                    then
                        SHO="$(echo "$CURRENT_TASK"|sed 's@\(["\;|&\\]\)@\\\1@g;s@\\\;\\\"@\\\;\\"@g;s@(@\\(@g;s@)@\\)@g;s@^\`@@'|sed "s@\'@\\\'@g"|sed "s/'$//")"
                        LogCons "$(eval echo \"$SHO\")"
                    else
                        LogCons "$CURRENT_TASK"
                    fi
                    continue
                elif [[ -n "$(echo $ans|sed -n '/^[123456789][0123456789]*$/p')" ]] 
                then
                    if [[ $ans -le $TASK_TOT ]]
                    then
                        echo "Interactive Response \"$ans\" - Jump to Task #$ans" | CartRidge | LogStdIn
                        TASK_CNT=$ans
                        CURRENT_TASK=$(get_task) || CURRENT_TASK=""
                        continue
                    else
                        echo "Interactive Response \"$ans\" - OUT OF RANGE" | CartRidge | LogStdIn
                        continue
                    fi
                elif [[ $ans = [hH?] ]]
                then
                    echo "Interactive Response was \"$ans\" - Display Command Summary [$TASK_CNT/$TASK_TOT]" | CartRidge | LogStdIn
                    help_cmd
                    continue
                else
                    echo "Interactive Response \"$ans\" - NOT RECOCNIZED" | CartRidge | LogStdIn
                    continue
                fi
            fi
          # --
          # RUN THE TASK
          # This point is only reached in these cases:
          # - In Batch Mode, always
          # - In Interactive Mode, only when a task was actually run
          #   (i.e. none of the "continue" conditions was verified) 
          #
            LogCons "RUNNING: [$TASK_CNT/$TASK_TOT] - $CURRENT_TASK"
            SHO="$(echo "$CURRENT_TASK"|sed 's@\(["\;|&\\]\)@\\\1@g;s@\\\;\\\"@\\\;\\"@g;s@(@\\(@g;s@)@\\)@g;s@^\`@@'|sed "s@\'@\\\'@g"|sed "s/'$//")"
            LogItQ "I.e.: $(eval echo \"$SHO\")"
            if [[ $EVAL_FLG -eq 1 ]]
            then
                eval "$CURRENT_TASK" 2>&1 | LogStdIn
            else
                     $CURRENT_TASK 2>&1 | LogStdIn
            fi
            LogCons "checking ..."
            Probe4Error $LOG_OFFSET
            SUCCESS=$?
            if [[ $SUCCESS -eq 0 ]]
            then
              #
              # FAILED
              #
                let FAIL_CNT+=1
                LogError "Failed: $TASK_CNT/$TASK_TOT: $CURRENT_TASK" 2>&1 | CartRidge | LogStdIn
                [[ $FORCE_FLG -eq 1 ]] && CONT_DFLT="Y" || CONT_DFLT="Q"
                if [[ $PROMPT_MODE != "ON" ]] && [[ $FORCE_FLG -eq 0 ]]
                then
                  #
                  # batch, with force flag at 0
                  #
                    BailOut "Failed: $TASK_CNT/$TASK_TOT: $CURRENT_TASK"
                fi
            else
              #
              # SUCCEEDED
              #
                echo "Succeeded: $TASK_CNT/$TASK_TOT" | CartRidge | LogStdIn
                let SUCC_CNT+=1
                if [[ $PROMPT_MODE = "ON" ]]
                then
                  #
                  # prompt mode
                  #
                    CONT_DFLT="Y"
                fi
           fi
           
          # --
          # Get next task from list
          #
            let TASK_CNT+=1
            CURRENT_TASK="$(get_task)"
          #
          # Get new offset from log file
          #
            LOG_OFFSET=$(LogLineCount)
        fi
    done

  #
  # finish
  #
    [[ $SKIP_CNT -gt 0 ]] && LogWarning "Number of skips forward: $SKIP_CNT" 
    [[ $PREV_CNT -gt 0 ]] && LogWarning "Number of skips back: $PREV_CNT" 

    if [[ $PROMPT_MODE = "ON" ]] 
    then
        if [[ $FAIL_CNT -gt 0 ]] 
        then
            (
                LittleBanner "See errors below"
                Probe4Error 
            ) | CartRidge | LogStdIn
            printf "\n\There were %d failures - STATUS will be \"%s\"\n\n" "$FAIL_CNT" "$OFA_ERR" | CartRidge | LogStdIn
            STATUS_PROSPECT="$OFA_ERR"
            MAIL_TO="$OFA_MAIL_RCP_BAD"
        else
            STATUS_PROSPECT="$OFA_SUC"
            MAIL_TO="$OFA_MAIL_RCP_GOOD"
        fi
        printf "\n\tType status at prompt or accept default [$STATUS_PROSPECT] => " 
        read $OFA_READ_TIME_OUT ans
        [[ -n $ans ]] && OFA_STATUS_MANUAL="$ans (manual)" || OFA_STATUS_MANUAL=""
        if [[ "$MAIL_TO" = *"@"* ]] && [[ -n "$OFA_MAIL_PROG" ]]
        then
            printf "\n\n\tMail %s ? (Y|N) [Y] => " "$MAIL_TO"
            read $OFA_READ_TIME_OUT ans
            if [[ $ans = *[Nn]* ]] 
            then
                LogCons "Mail Canceled"
                OFA_MAIL_RCP_GOOD="Mail canceled by user"
                OFA_MAIL_RCP_BAD="Mail canceled by user"
            fi
        else
            OFA_MAIL_RCP_GOOD="Mail unavailable"
            OFA_MAIL_RCP_BAD="Mail unavailable"
        fi
    fi
    STEP_LABEL=" - Completed" && LogCons "$STEP_LABEL"
  #
  # de-activate trap as Log Checker is now called explicitely before exit
  #
    OFA_TRAP_XIT=""
    MailLogReport "$STEPLIST: $STEP_LABEL"
    RV=$?
    LogIt "END"
    copy_log_to_default
    exit $RV




