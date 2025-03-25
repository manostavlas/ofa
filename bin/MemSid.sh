#!/bin/ksh

#
## 
## Name: MemSid.sh
##
## Synopsis: Display memary usage for on instance.
##
## Usage: MemSid.sh [ORACLE_SID] [long|columnar]
##
#


#Verify the parameter count
 if [ $# -lt 2 ]; then
 echo ""
 echo "Usage: MemSid.sh [ORACLE_SID] [long|columnar]" 
 echo ""
 exit 1
 fi

#Set variables
 export ORACLE_SID=$1
 output_type=$2

#determine if the instance is an ASM or db
 if [ "`echo $ORACLE_SID|cut -b1-4`" = "+ASM" ]; then
 export prefix="asm"
else
 export prefix="ora"
fi

#determine if the instance uses AMM on Linux (/dev/shm files for shared memory)
 export dev_shm_count=$(pmap `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'` | grep /dev/shm | wc -l)
 pmap `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'` | grep /dev/shm | awk '{print $1}' > shm_addresses

#running calculations.

export pids=`ps -elf|grep oracle$ORACLE_SID|grep -v grep|awk '{print $4}'`

if [ -n "$pids" ]; then
 export countcon=`print "$pids"|wc -l`

if [ "`uname -a|cut -f1 -d' '`" = "Linux" ]; then
 if [ $dev_shm_count -gt 0 ]; then
 export tconprivsz=$(pmap -x `print "$pids"`|grep " rw"|grep -Evf shm_addresses|awk '{total +=$2};END {print total}')
else
 export tconprivsz=$(pmap -x `print "$pids"`|grep " rw"|grep -Ev "shmid|deleted"|awk '{total +=$2};END {print total}')
fi
 else
 export tconprivsz=$(pmap -x `print "$pids"`|grep " rw"|grep -v "shmid"|awk '{total +=$2};END {print total}')
fi

export avgcprivsz=`expr $tconprivsz / $countcon`
 else
 export countcon=0
 export tconprivsz=0
 export avgcprivsz=0
 fi

if [ "`uname -a|cut -f1 -d' '`" = "Linux" ]; then
 if [ $dev_shm_count -gt 0 ]; then
 export instprivsz=$(pmap -x `ps -elf|grep ${prefix}_.*_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep " rw"|grep -Evf shm_addresses|awk '{total +=$2};END {print total}')
else
 export instprivsz=$(pmap -x `ps -elf|grep ${prefix}_.*_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep " rw"|grep -Ev "shmid|deleted"|awk '{total +=$2};END {print total}')
fi
 else
 export instprivsz=$(pmap -x `ps -elf|grep ${prefix}_.*_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep " rw"|grep -v "shmid"|awk '{total +=$2};END {print total}')
fi

if [ "`uname -a|cut -f1 -d' '`" = "Linux" ]; then
 if [ $dev_shm_count -gt 0 ]; then
 export instshmsz=$(pmap -x `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep -Ef shm_addresses|awk '{total +=$2};END {print total}')
else
 export instshmsz=$(pmap -x `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep -E "shmid|deleted"|awk '{total +=$2};END {print total}')
fi
 else
 export instshmsz=$(pmap -x `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep "shmid"|awk '{total +=$2};END {print total}')
fi

export binlibsz=$(pmap -x `ps -elf|grep ${prefix}_pmon_$ORACLE_SID|grep -v grep|awk '{print $4}'`|grep -v " rw"|  awk '{total +=$2};END {print total}')

export sumsz=`expr $tconprivsz + $instprivsz + $instshmsz + $binlibsz`

rm shm_addresses

if [[ "$output_type" = "long" ]]; then
 echo memory used by Oracle instance $ORACLE_SID as of `date`
 echo
 echo "Total shared memory segments for the instance......: "$instshmsz KB
 echo "Shared binary code of all oracle processes and shared libraries: "$binlibsz KB
 echo "Total private memory usage by dedicated connections....: "$tconprivsz KB
 echo "Total private memory usage by instance processes.....: "$instprivsz KB
 echo "Number of current dedicated connections..........: "$countcon
 echo "Average memory usage by database connection........: "$avgcprivsz KB
 echo "Grand total memory used by this oracle instance......: "$sumsz KB
 echo
 elif [ "$output_type" = "columnar" ]; then
 printf "%17s %10s %10s %10s %10s %10s %10s %10s %10s\n" "date" "ORACLE_SID" "instshmsz" "binlibsz" "tconprivsz" "instprivsz" "countcon" "avgcprivsz" "sumsz"
echo "...... ...- ...- ...- ...- ...- ...- ...- ...-"
printf "%17s %10s %10s %10s %10s %10s %10s %10s %10s\n" "`date +%y/%m/%d_%H:%M:%S`" $ORACLE_SID $instshmsz $binlibsz $tconprivsz $instprivsz $countcon $avgcprivsz $sumsz
 fi;

