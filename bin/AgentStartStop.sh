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
## Usage: AgentStartStop.sh [ACTION]
##
## Start/stop of GRID Agent.  
##
## Parameters:
## 	start (start agent, config in ../oratab as OEMAGENT)
##      stop  (stop agent, config in ../oratab as OEMAGENT)
##      status (Show agent, config in ../oratab as OEMAGENT)
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
  for i in $Agents
  do
	LogCons "$WhatToDo OEM agent: $i"  
	OraEnv $i
	Error=$?


	OsOwner=$(OraOsOwner)
	WhoAmI=$(whoami)

	if [ "$OsOwner" != "$WhoAmI" ] ; then
                 LogError "Not owner of the AGENT, Owner: $OsOwner, WhoAmI: $WhoAmI"
        else
		if [ $Error -ne 0 ] ; then
			LogCons "Error setting ENV for AGENT: OEMAGENT"
		else
			LogCons "$WhatToDo AGENT"
			emctl $WhatToDo agent	
			ErrorLs=$?
		fi

		echo "ErrorLs: $ErrorLs"
 
		if [ "$ErrorLs" -ne "0" ] ; then
			LogError "Error $WhatToDo AGENT"
		fi 
	fi
  done	
}
#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------

  Agents=$(ListOraDbs | grep OEMAGENT)
  if [[ -z $Agents ]]
  then
	  LogCons "No agent installed on the server....."
	  exit
  fi	  
	
if [ $WhatToDo == start ] || [ $WhatToDo == stop ] || [ $WhatToDo == status ] ; then
	StartStop
else
	Usage
fi
