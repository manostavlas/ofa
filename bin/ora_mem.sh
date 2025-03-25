#!/bin/ksh

 ##
 ## Check the memory usage of all oracle process on a Server
 ##

  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

echo ""

TotSize=0
TotProcSizeMB=0

for i in $(cat /etc/oratab | awk -F ":" '{print $1}' | grep -v "#") 
do  
	OraEnv $i > /dev/null 2>&1 
	StatusDB=$(OraDbStatus $i)

        if [ "$StatusDB" = "OPEN" ] ; then
		Size=$(GetSGA | grep [0-9] | grep -v ORA- | grep -v ERROR | grep -v select)
		ProcessSize=$(ps aux | grep -v grep | grep "oracle$ORACLE_SID" | awk '{print $6}')
		TotProcSize=0
		for b in $ProcessSize
		do
			TotProcSize=$(($b+$TotProcSize))
		done
		SidTotProcSizeMB=$(($TotProcSize/1024))
        	printf "%-18s %10s %5s %10s %11s %10s\n" "Memory used by DB:" "$ORACLE_SID," "SGA:" "$Size MB," "Connection:" "$SidTotProcSizeMB MB"
	else
		OldTotProcSize=$TotProcSize
 		OldSidTotProcSizeMB=$SidTotProcSizeMB
        	TotProcSize=n.a
		SidTotProcSizeMB=n.a
		Size=n.a
        	printf "%-18s %10s %5s %10s %11s %10s\n" "Memory used by DB:" "$ORACLE_SID," "SGA:" "$Size MB," "Connection:" "$SidTotProcSizeMB MB"
		TotProcSize=0
		SidTotProcSizeMB=$OldSidTotProcSizeMB
		Size=0
		SidTotProcSizeMB=0
	fi

	TotSize=$(($Size+$TotSize))
        TotProcSizeMB=$(($SidTotProcSizeMB+TotProcSizeMB)) 
done
 TotMemUsage=$(($TotSize+$TotProcSizeMB))
 echo ""
 echo "Total Memory size used by Oracle DB's"
 echo "Total: $TotMemUsage MB, SGA: $TotSize MB, Connection: $TotProcSizeMB MB (ps aux, RSS - The Real memory (resident set) size of the process.)"
 echo ""
 if [ -r /proc/meminfo ]; then
 	echo "System Memory:" 
	 cat /proc/meminfo | head -4
	 echo ""
 fi

