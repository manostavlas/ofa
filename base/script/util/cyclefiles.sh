#!/bin/ksh
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

DIR_NAME=$(dirname $0)
cd $DIR_NAME
#
# scenario for logmaint.sh
#

  #
  # ofa logs
  #
  ## Synopsis: Purge ofa log files and runs cyclefiles_$OFA_GRAFT.sh 
  ##
  ## Usage: cyclefiles.sh
  #


    CycleFileS "$OFA_LOG" "Remove" '*' 30

  #
  # if there is a product specific script in place, run that
  #
  LogCons "Starting ${DIR_NAME}/cyclefiles_${OFA_GRAFT}.sh"
#    cyclefiles_$OFA_GRAFT.sh 1>/dev/null 2>/dev/null
   ${DIR_NAME}/cyclefiles_${OFA_GRAFT}.sh
        ERROR_CODE=$?
        if [ $ERROR_CODE -ne 0 ] ; then
                LogError "Error running ${DIR_NAME}/cyclefiles_${OFA_GRAFT}.sh (..logs/cyclefiles_${OFA_GRAFT})"
        fi
