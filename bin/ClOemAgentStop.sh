#! /bin/bash
#
# emagentoracle      Stop/Start emagent for DB
#
# chkconfig: 2345 10 90
# description: Activates/Deactivates EM Agent oracle 
#              
#
SID=$1
ORACLE_HOME=`cat /etc/oratab | grep $SID | grep emagent | awk -F ":" '{print $2}'`

su  dba -c "$ORACLE_HOME/bin/emctl stop agent"
rm /var/run/emagentoracle_$SID.pid

