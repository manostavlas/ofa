#!/bin/ksh

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
## Usage: OmsStartStop.sh [ACTION]
##
## Start/stop of GRID Oms.  
##
## Parameters:
## 	start (start oms, config in ../oratab as OMS)
##      stop  (stop oms, config in ../oratab as OMS)
##      status (Show oms, config in ../oratab as OMS)
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

	OraEnv OMS
	Error=$?


	OsOwner=$(OraOsOwner)
	WhoAmI=$(whoami)

	if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the OMS, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
		if [ $Error -ne 0 ] ; then
			LogCons "Error setting ENV for OMS: OMS"
		else
			LogCons "$WhatToDo OMS"
			emctl $WhatToDo oms	
			ErrorLs=$?
		fi

		echo "ErrorLs: $ErrorLs"
 
		if [ "$ErrorLs" -ne "0" ] ; then
			LogError "Error $WhatToDo OMS"
		fi 
	fi 
}
#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [ $WhatToDo == start ] || [ $WhatToDo == stop ] || [ $WhatToDo == status ] ; then
	StartStop
else
	Usage
fi
