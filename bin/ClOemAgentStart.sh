#! /bin/bash
#
# emagentoracle      Stop/Start emagent for DB
#
# chkconfig: 2345 10 90
# description: Activates/Deactivates EM Agent oracle 
#              
#
SID=$1
ORACLE_HOME=`cat /etc/oratab | grep -v "#" | grep $SID | grep emagent | awk -F ":" '{print $2}'`

su  dba -c "$ORACLE_HOME/bin/emctl start agent"
ps -ef | grep dba | grep $SID | grep emwd.pl | awk '{print $2 }' > /var/run/emagentoracle_$SID.pid
