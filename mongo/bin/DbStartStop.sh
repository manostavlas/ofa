#!/bin/ksh
#set -x
##
## Script:       DbStartStop.sh
## Description: Start or Stop a specific database 
## Input:    start|stop        --> Action to be done 
##           INSTANCE|SIDNAME          -->  SERVERNAME 
## Output:
## Updates:  23-02-2015 - tms - Creation
## version:  1.0


  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
WhatToDo=$1
DbList=$2


Start ()
{

		LogCons "Running DbStartStop.s ${MONGO_INSTANCE}"
		echo "START ${MONGO_INSTANCE}"
	nohup 	/mongodb/product/bin/mongod -f /mongodb/admin/${MONGO_INSTANCE}/etc/${MONGO_INSTANCE}.conf & 


}


Stop ()
{
	echo "STOP"
}

#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
if [ -z $DbList ] ; then
        DbList=${MONGO_INSTANCE}
fi


echo $WhatToDo

if [ $WhatToDo == start ] ; then
        Start
elif [ $WhatToDo == stop ] ; then
        Stop
else
        Usage
fi
 
