#!/bin/ksh
#set -x
  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
WhatToDo=$1

#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: AllStartStop.sh [ACTION]
##
## Start/stop All oracles services (DB, listeners, agent).
##
## Parameters:
##      start
##      stop
##
#
_EOF
LogError "Wrong parameter....."
exit 1
}
#----------------------------------------------------------------------------------------
StartStop ()
#----------------------------------------------------------------------------------------
{

        LogCons "Running HERE DbStartStop.sh $WhatToDo"
        $OFA_BIN/DbStartStop.sh $WhatToDo >> $LOGFILE
        Error=$?
        if [ $Error -ne 0 ] ; then
                LogError "Error running $OFA_BIN/DbStartStop.sh $WhatToDo"
        fi


}


#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [ $WhatToDo == start ] || [ $WhatToDo == stop ] ; then
        StartStop
else
        Usage
fi


