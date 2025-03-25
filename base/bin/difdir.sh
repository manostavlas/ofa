#!/bin/ksh
# -----------------------------------------------------------------------------------------
# Copyright 2012-2013-2013 OnoBase S.a.r.l. (ofa@onobase.com), FreeBSD copyright and disclaimer apply
# -----------------------------------------------------------------------------------------
#                                                     
## Name: difdir.sh
##                                                    
## In:  2 directory trees
## Out: report
## Ret: 0/1
##                                                    
## Synopsis: compares same-named files in directories
##                                                    
## Usage: difdir.sh <dir1> <dir2>
##                                                    
## Description:                                       
##                                                    
##    Produces a report of 
##    - matching pairs
##    - differing pairs
##    - differing lines
##    - misses left
##    - misses right
##   Report is included with the standard log file.
##                                                    
## Workings:                                          
##                                                    
##    DIFF_PROG can be adjusted in parfile
#                                                     
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22
    
    CheckVar IGNORE || IGNORE="__nothing__"

    [[ ! -d "$1" ]] && BailOut "\"$1\": not a directory" || _P1="$(RealPath $1)"
    [[ ! -d "$2" ]] && BailOut "\"$2\": not a directory" || _P2="$(RealPath $2)"

    dLEFT="$(RealPath $_P1)"
    dRIGH="$(RealPath $_P2)"

    REPORT=$OFA_TMP_DIR/$(WhosTalking).REPORT.$(Tmsp)
    touch $REPORT || BailOut "cannot create tempfile"
    touch $REPORT.singletonsLEFT
    touch $REPORT.singletonsRIGH
    touch $REPORT.diffs
    
    CNT_TOTAL=0
    CNT_FILES=0
    CNT_SINGLETONS_RIGH=0
    CNT_SINGLETONS_LEFT=0
    CNT_MISSS=0
    CNT_DIFFS=0
    CNT_TWINS=0
    DIFF_LINES=0
    DIFF_LINES_B4=0
    DIFF_PROG=${DIFF_PROG:-"sdiff"}
    echo "
        Left:  $_P1 ($dLEFT)
        Right: $_P2 ($dRIGH)
    " | tee -a $REPORT | LogStdIn


    cd $dLEFT || BailOut "failed \"cd $dLEFT\""
    for itm in $(find . -type f|egrep -v "$IGNORE");do
        let CNT_TOTAL+=1
        iLEFT=$PWD/$itm
        iRIGH=$dRIGH/$itm
        VolMax
        echo "$CNT_TOTAL: file $(basename $itm)" | CartRidge | LogStdIn
        VolMin
        if [[ ! -f $iRIGH ]]
        then
            LogCons "(Singleton: $dLEFT/$itm)"
            let CNT_MISSS+=1
            let CNT_SINGLETONS_LEFT+=1
            echo "$itm" >> $REPORT.singletonsLEFT
        else
            let CNT_FILES+=1
            let DIFF_LINES+=$($DIFF_PROG -s $iLEFT $iRIGH|awk 'END{print NR}')
            if [[ $DIFF_LINES -gt $DIFF_LINES_B4 ]] 
            then
                LogCons "!= Different:"
                LogCons "!= $(ls -ld $iLEFT)"
                LogCons "!= $(ls -ld $iRIGH)"
                let CNT_DIFFS+=1
                echo "$itm" >> $REPORT.diffs
            else
                LogCons "== Identical:"
                LogCons "== $(ls -ld $iLEFT)"
                LogCons "== $(ls -ld $iRIGH)"
                let CNT_TWINS+=1
            fi
            DIFF_LINES_B4=$DIFF_LINES
            $DIFF_PROG -s $iLEFT $iRIGH 2>&1 | tee -a $LOGFILE
        fi
        LogCons " "
    done
    LogCons "[-·- comparison over -·-··-··]"

# ---
    cd $dRIGH || BailOut "failed \"cd $dRIGH\""
    
    for itm in $(find . -type f|egrep -v "$IGNORE");do
        iRIGH=$PWD/$itm
        iLEFT=$dLEFT/$itm
        if [[ ! -f $iLEFT ]]
        then
            let CNT_MISSS+=1
            let CNT_SINGLETONS_RIGH+=1
            let CNT_TOTAL+=1
            echo "$itm" >> $REPORT.singletonsRIGH
        fi
    done
# ---
    
    echo "
        Files listed:       $CNT_TOTAL
        Files compared:     $CNT_FILES
        Files missed:       $CNT_MISSS
        Singletons Left:    $CNT_SINGLETONS_LEFT
        Singletons Right:   $CNT_SINGLETONS_RIGH
        Differing pairs:    $CNT_DIFFS
        Identical pairs:    $CNT_TWINS
        Delta (lines):      $DIFF_LINES
    " >> $REPORT
    
    echo "
        DIFFS:
    " >> $REPORT
    cat $REPORT.diffs >> $REPORT
    
    echo "
        SINGLETONS LEFT:
    " >> $REPORT
    cat $REPORT.singletonsLEFT >> $REPORT
    
    echo "
        SINGLETONS RIGH:
    " >> $REPORT
    cat $REPORT.singletonsRIGH >> $REPORT
    
    VolSet 1
    cat $REPORT | CartRidge | LogStdIn
   
    LogCons "Complete log at" 
    LogCons "$LOGFILE"
    
    rm -f $REPORT*

    unset OFA_TRAP_XIT
