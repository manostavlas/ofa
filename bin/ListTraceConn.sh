#!/bin/ksh

  #
  # load lib
  #
#  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

# OFA_MAIL_RCP_BAD="no mail"





OnHost=$(uname -n)
TimeStamp=`date +%Y_%m_%d_%H%M%S`
OutPutLog=$OFA_LOG/tmp/ListTraceConn.${OnHost}.$$.$PPID.$TimeStamp.log

#
##
## Usage: ListTraceConn.sh
##
## Parameters: NONE
##
## Genereate a list of all server there have being 
## connected to the database(s) from all running listener.
##
##
#


IFS=$'\n' 

ListenerList=$(ps -ef | grep LISTENER | awk '{print $8, $9}' | sed 's/tnslsnr/lsnrctl status/g' | grep -v grep)
for i in $ListenerList
do
#	echo "Command:$i"
	TraceFileDir=$(eval $i | grep "Listener Log File" | awk '{print $4}' | sed 's/alert\/log.xml/trace/g')
#	echo "Trace file Dir:$TraceFileDir"
# 	grep -h "(CONNECT_DATA=(CID=(PROGRAM=" ${TraceFileDir}/* | grep -v "(COMMAND=status)" | grep -v "(COMMAND=stop)" | grep -v "(COMMAND=services)"| tail -10
IFS='='
# 	grep -h "establish" ${TraceFileDir}/*  | grep -v "PROTOCOL=ipc" | sed 's/(CONNECT_DATA=//g' | tail -10 | awk '{print $3 $4 $5 $6}' | sort -u
#	grep -h "establish" ${TraceFileDir}/*  | grep -v "PROTOCOL=ipc" | sed 's/(CONNECT_DATA=//g' | awk -F 'HOST=' '{print $1 $3}' |  awk -F "*" '{print $2 $4}' | sort -u
	grep -h "establish" ${TraceFileDir}/* 2>/dev/null  | grep -v "PROTOCOL=ipc" | sed 's/(CONNECT_DATA=//g' | awk -F 'HOST=' '{print $1 $3}' |  awk -F "*" '{print $2 $4}' | awk -F "(" '{print $(NF-1), $NF}' | awk '{print $1 $3}' | sed 's/)/ /g' | sort -u | grep -v "__" | tee -a $OutPutLog
done

echo  "Output file: $OutPutLog"
