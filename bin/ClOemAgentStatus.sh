#! /bin/bash
#
# emagentoracle      Stop/Start emagent for DB
#
# chkconfig: 2345 10 90
# description: Activates/Deactivates EM Agent oracle 
#              
#
SID=$1
ORACLE_HOME=`cat /etc/oratab | grep $SID | grep "#" | grep emagent | awk -F ":" '{print $2}'`

$ORACLE_HOME/bin/emctl status agent | grep -v grep | grep "Agent is Running and Ready"
exit $? 
