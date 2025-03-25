#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22 > /dev/null 2>&1

VolSet -10000

#
##
## Usage: "Conn.sh [SID]
##
## Connect to the server where the DB is running.
##
#

Usage ()
{
echo ""
echo  "Usage: Conn.sh [SID]"
echo "" 
echo  "Connect to the server where the DB is running."
echo ""
exit 1
}

#----------------------------------
# Main
#----------------------------------

 [[ ! -n $1 ]] \
        && Usage "Database SID parameter missing" \
        || TargetDatabaseSid=$1

which tnsping > /dev/null 2>&1
if [ $? -ne 0 ] ; then
        echo ""
        echo "Error: Can't find tnsping......"
        echo ""
        exit 1
fi

export HOST_NAME=$(Ldaping $TargetDatabaseSid | grep HOST | awk -F "HOST" '{print $2}' | awk -F ")" '{print $1}' | sed 's/=//g') 
if [ -z $HOST_NAME ] ; then
	echo ""
	echo "Error: No HOST found......"
	echo ""
	exit 1 
fi

ssh-keygen -q -R $HOST_NAME

echo ""
echo  "Connection to Host: $HOST_NAME"
echo ""
if [ ! -d  $HOME/.ssh ] ; then
echo  "Create dir: $HOME/.ssh"
  mkdir -p $HOME/.ssh
  chmod 700 $HOME/.ssh
fi

if [ ! -f $HOME/.ssh/config ] ; then
	echo "Create to config"
	echo "ServerAliveInterval 120" > $HOME/.ssh/config
	chmod 600 $HOME/.ssh/config
else
	ReadParameter=$(grep -i "ServerAliveInterval" $HOME/.ssh/config)
	# echo "ReadParameter: $ReadParameter"
	if [ -z "$ReadParameter" ] ; then
		echo "Add parameter to config"
		echo "ServerAliveInterval 120" >> $HOME/.ssh/config
	fi
fi

ssh -q -o "StrictHostKeyChecking no" $HOST_NAME 

if [ $? -ne 0 ] ; then
	echo ""
	echo "Error: connecting to $HOST_NAME"
	echo ""
	exit 1
fi
