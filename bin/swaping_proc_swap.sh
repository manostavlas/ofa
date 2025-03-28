#!/bin/bash
#
##
## Usage: swaping_proc_swap.sh
## Shows swap usage of all processes 
## there are using swap space
##
#

 SUM=0
 OVERALL=0
 for DIR in `find /proc/ -maxdepth 1 -type d | egrep "^/proc/[0-9]"` ; do
 PID=`echo $DIR | cut -d / -f 3`
 PROGNAME=`ps -p $PID -o comm --no-headers`
 for SWAP in `grep Swap $DIR/smaps 2>/dev/null| awk '{ print $2 }'`
 do
 let SUM=$SUM+$SWAP
 done
 if [ 0 -ne $SUM ] ; then
 echo "PID=$PID - Swap used: $SUM - ($PROGNAME )"
 ps -ef | grep $PID | grep -v grep
 fi
 let OVERALL=$OVERALL+$SUM
 SUM=0

done
 echo "Overall swap used: $OVERALL"

