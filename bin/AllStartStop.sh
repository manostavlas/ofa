#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

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
## 	start 
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

	LogCons "Running AgentStartStop.sh $WhatToDo"
	$OFA_BIN/AgentStartStop.sh $WhatToDo >> $LOGFILE
	Error=$?
	if [ $Error -ne 0 ] ; then
		LogError "Error running $OFA_BIN/AgentStartStop.sh $WhatToDo"
	fi

	LogCons "Running ListStartStop.sh $WhatToDo"
	$OFA_BIN/ListStartStop.sh $WhatToDo >> $LOGFILE
	Error=$?
	if [ $Error -ne 0 ] ; then
		LogError "Error running $OFA_BIN/ListStartStop.sh $WhatToDo"
	fi

        LogCons "Running DbStartStop.sh $WhatToDo"
        $OFA_BIN/DbStartStop.sh $WhatToDo >> $LOGFILE
        Error=$?
        if [ $Error -ne 0 ] ; then
                LogError "Error running $OFA_BIN/DbStartStop.sh $WhatToDo"
        fi
	
	OmsExist=$(ShowOraDbsQuick | grep -w OMS | awk '{print $1}')
	if [ ! -z $OmsExist ] ; then
        	LogCons "Running OmsStartStop.sh $WhatToDo"
        	$OFA_BIN/OmsStartStop.sh $WhatToDo >> $LOGFILE
        	Error=$?
        	if [ $Error -ne 0 ] ; then
                	LogError "Error running $OFA_BIN/OmsStartStop.sh $WhatToDo"
        	fi
	fi

        ObsExist=$(ShowOraDbsQuick | grep OBSERVER | awk '{print $1}')
        if [ ! -z $ObsExist ] ; then
                LogCons "Running ObsStartStop.sh $WhatToDo"
                $OFA_BIN/ObsStartStop.sh $WhatToDo >> $LOGFILE
                Error=$?
                if [ $Error -ne 0 ] ; then
                        LogError "Error running $OFA_BIN/ObsStartStop.sh $WhatToDo"
                fi
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
