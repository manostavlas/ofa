#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES




DatabaseName=$1
#---------------------------------------------
usage ()
#---------------------------------------------
{
echo ""
cat << __EOF
#
##
## Usage: MoveDB.sh [SID] <Option>
##
## [SID] name of database to move to this server.
## <Option> Option number from the menu, runs only this step.
##
#
__EOF
exit 
}

#---------------------------------------------

  CheckVar DatabaseName         \
  || usage

SqlLog=$OFA_LOG/tmp/MoveDB.sh.SqlLog.$$.$PPID.log
FsListSource=$OFA_LOG/tmp/MoveDB.sh.FsListSource.$$.$PPID.log
FsListTarget=$OFA_LOG/tmp/MoveDB.sh.FsListTarget.$$.$PPID.log
FileListSource=$OFA_LOG/tmp/MoveDB.sh.FileListSource.$$.$PPID.log
FileListTarget=$OFA_LOG/tmp/MoveDB.sh.FileListTarget.$$.$PPID.log
BackupLog=$OFA_LOG/tmp/MoveDB.sh.BackupLog.$$.$PPID.log
RestoreLog=$OFA_LOG/tmp/MoveDB.sh.RestoreLog.$$.$PPID.log
RestartDbLog=$OFA_LOG/tmp/MoveDB.sh.RestartDbLog.$$.$PPID.log
ArchStatusLog=$OFA_LOG/tmp/MoveDB.sh.ArchStatusLog.$DatabaseName

SourceServerName=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "hostname -s")
DatabaseName=$1
SourceHost=${DatabaseName}-vip
TargetServerName=$(hostname -s)
RepoServer=refresh_prod-vip
RepoUser=repodba



LogCons "Setting enviroment for $ORACLE_SID"

OraEnv $DatabaseName || BailOut "Failed OraEnv \"$DatabaseName\""

#---------------------------------------------
NumberOfCpu ()
#---------------------------------------------
{
LogCons "Check number of CPU's on : $TargetServerName"
if [[ $OSNAME == AIX ]]
then
	NumberCpu=$(bindprocessor -q | awk '{print $NF}')
	let NumberCpu=$NumberCpu+1
	LogCons "Number of CPU: $NumberCpu"
elif [[ $OSNAME == Linux ]]
then
	NumberCpu=$(nproc)
	LogCons "Number of CPU: $NumberCpu"
fi
}


#---------------------------------------------
CheckConnect ()
#---------------------------------------------
{
# set -xv
LogCons "Check ssh connection to Source server: $SourceHost"
if [[ ! -r ~/.ssh/id_rsa.pub ]]
then
	LogCons "Generate id_rsa.pub"
	echo -e "\n"|ssh-keygen -t rsa -N ""
fi


# SshStatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1 | grep "ok")
# echo "*$SshStatus*"
# SshStatusText=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1)


ErrorPW=$(echo $SshStatusText| grep "Permission denied")

if [[ ! -z "$ErrorPW" ]]
then
         LogCons "Copy the pub key to $SourceHost:"
         cat ~/.ssh/id_rsa.pub | ssh dba@$SourceHost "umask 077;cat >> ~/.ssh/authorized_keys"
fi

# SshStatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1 | grep "ok")
SshStatus=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost echo ok 2>/dev/null)
# echo "*$SshStatus*"

# SshStatusText=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1)
SshStatusText=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost echo ok  2>&1)
# echo "*$SshStatusText*"

# if [[ -z "$SshStatus" ]]
if [[ $SshStatus != "ok" ]]
then
	LogError "Can't connect to $SourceHost !"
        LogCons "SSH connection status: $SshStatusText"
        exit 1
else
        LogCons "SSH connection status: $SshStatus"
fi

export SourceServerName=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "hostname -s")
}
#---------------------------------------------
CheckConnectRepo ()
#---------------------------------------------
{
LogCons "Check ssh connection to Repo Server: $RepoServer, Repo User: ${RepoUser}"
NetworkNumber=$(hostname -I | awk -F "." '{print $1"."$2}')

if [[ $NetworkNumber == 172.17 ]]
then
        LogCons "Shenzo zone ($NetworkNumber) no connection the Repo server."
        return
fi

if [[ ! -r ~/.ssh/id_rsa.pub ]]
then
        LogCons "Generate id_rsa.pub"
        echo -e "\n"|ssh-keygen -t rsa -N ""
fi


SshStatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${RepoUser}@$RepoServer echo ok 2>&1 | grep "ok")
SshStatusText=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${RepoUser}@$RepoServer echo ok 2>&1)


ErrorPW=$(echo $SshStatusText| grep "Permission denied")

if [[ ! -z "$ErrorPW" ]]
then
         LogCons "Copy the pub key to $RepoServer"
	 LogCons "Password for ${RepoUser}@${RepoServer}"
         cat ~/.ssh/id_rsa.pub | ssh ${RepoUser}@${RepoServer} "umask 077;cat >> ~/.ssh/authorized_keys"
fi

# SshStatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${RepoUser}@$RepoServer echo ok 2>&1 | grep "ok")
SshStatus=$(ssh -q -o "StrictHostKeyChecking no" ${RepoUser}@$RepoServer echo ok 2>/dev/null)
# SshStatusText=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${RepoUser}@$RepoServer echo ok 2>&1)
SshStatusText=$(ssh -q -o "StrictHostKeyChecking no" ${RepoUser}@$RepoServer echo ok  2>&1)

# if [[ -z "$SshStatus" ]]
if [[ $SshStatus != "ok" ]]
then
        LogError "Can't connect to ${RepoUser}@$RepoServer !"
        LogCons "SSH connection status: $SshStatusText"
        exit 1
else
        LogCons "SSH connection status: $SshStatus"
fi
}
#---------------------------------------------
CheckDir ()
#---------------------------------------------
{
LogCons "Check directories."
$OFA_BIN/cre.dir.sh 19c
if [[ $? -ne 0 ]]
then
	LogError "Error in check directories...."
	exit 1
fi
}
#---------------------------------------------
CleanUp ()
#---------------------------------------------
{
LogCons "Cleanup on target server database: $DatabaseName"
LogCons "Shutdown abort: $DatabaseName"
	DoSqlQ "shutdown abort;"
LogCons "Cleanup old files....."
    find / -name "*$DatabaseName*" -group dba \( -type s -o -type f \) 2>/dev/null | grep -v ofa | grep -v emagent | xargs -r rm

    rm -f /DB/$DatabaseName/* > /dev/null 2>&1
    rm -f /arch/$DatabaseName/* > /dev/null 2>&1
    rm -f /backup/$DatabaseName/rman/* > /dev/null 2>&1
    rm -f $ORACLE_HOME/dbs/*$DatabaseName* > /dev/null 2>&1

}
#---------------------------------------------
CheckSize ()
#---------------------------------------------
{
LogCons "Check target FS size"
ssh -q -o "StrictHostKeyChecking no"  $SourceHost "df -k | grep $DatabaseName" | grep -v emagent | awk '{print $2,$3,$6}' | sort -k2 > $FsListSource
df -k | grep $DatabaseName | awk '{print $2,$6}'  | sort -k2 > $FsListTarget
 printf "%-20s %-20s %-20s %-20s %-20s\n" "FS name" "Source Size" "Source Used" "Target Size" "Size FS (Free)" 
 printf "%20s %20s %20s %20s %20s\n" "--------------------" "--------------------" "--------------------" "--------------------" "--------------------"
cat $FsListSource | while read line
do 
# echo $line
SourceSize=$(echo $line | awk '{print $1}')
SourceUsed=$(echo $line | awk '{print $2}')
SourceName=$(echo $line | awk '{print $3}')
TargetSize=$(grep $SourceName $FsListTarget | awk '{print $1}')

if [[ $TargetSize -ge $SourceSize ]]
then
	OkFS=OK
else 
	OkFS=KO
fi

if  [[ $TargetSize -ge $SourceUsed ]]
then
	OkUed="(OK)"
else 
	OkUed="(KO)"
fi

if [[ $OkUed == "(KO)" ]]
then
	NoSpace=1
fi

if [[ $OkFS == "KO" ]]
then
	FsToSmall=1
fi

	printf "%-20s %20s %20s %20s %20s\n" "$SourceName" "$SourceSize" "$SourceUsed" "$TargetSize" "$OkFS $OkUed"
done 

if [[ $NoSpace -eq 1 ]]
then
	LogError "One or more  FS's are to small...."
	exit 1
fi


if [[ $FsToSmall -eq 1 ]]
then
 	echo "One or more FS's to small, but free space OK...."
 	echo "Continue ?  (Y/N)"
 	read YesOrNo
 		if [[ $YesOrNo == Y ]] || [[ $YesOrNo == y ]]
 		then
 			LogCons "Continue: $YesOrNo"
 		else
 			LogCons "Continue: ${YesOrNo}"
 		exit 1
		fi
fi
}
#---------------------------------------------
CheckHome ()
#---------------------------------------------
{
LogCons "Checking Oracle homes...."
SourceHome=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName > /dev/null 2>&1 ; OraHomeDb")
TargetHome=$(OraHomeDb)
LogCons "Source Home: $SourceHome  Target Home: $TargetHome"

if [[ $SourceHome != $TargetHome ]]
then
	LogError "Source and target home is differant..."
	exit 1
fi
}
#---------------------------------------------
BackupDatabase ()
#---------------------------------------------
{
SourceServerName=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "hostname -s")
ArchStatusLog=$OFA_LOG/tmp/MoveDB.sh.ArchStatusLog.$DatabaseName.$SourceServerName

LogCons "Backup DB"
NumberOfCpu
LogCons "Check archive mode on: $SourceServerName, $DatabaseName"

if [[ ! -e $ArchStatusLog ]]
then
	LogCons "Create status file: $ArchStatusLog"
	ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ 'ARCHIVE LOG LIST;'" | grep "Database log mode" > $ArchStatusLog
else
	LogCons "Status file exist: $ArchStatusLog"
	ArchiveModeFull=$(cat $ArchStatusLog)
	LogCons "$ArchiveModeFull"
fi

ArchiveMode=$(cat $ArchStatusLog | awk '{print $4}')

LogCons "Archive mode: $ArchiveMode"

LogCons "Stop listener, restart database: $SourceServerName, $DatabaseName"
LogCons "Log file: $RestartDbLog"
ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; $OFA_BIN/ListStartStop.sh stop $DatabaseName" > $RestartDbLog 2>&1

# ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; $OFA_BIN/DbStartStop.sh stop $DatabaseName ; $OFA_BIN/DbStartStop.sh start $DatabaseName" > $RestartDbLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ $OFA_SQL/SwitchArcLogging.sql on" >> $RestartDbLog 2>&1

LogCons "Backup source database: $DatabaseName, Server:$SourceHost, $SourceServerName"
LogCons "Log file: $BackupLog"
ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; rman_hot_bkp.sh $DatabaseName backup CHANNELS=$NumberCpu SECTION_SIZE=20 BACKUP_TYPE=0" > $BackupLog 2>&1

if [[ $? -ne 0 ]]
then
	LogError "Error backup source database: $DatabaseName on serever: $SourceHost"
	LogError "Backup log: $BackupLog"
	exit 1
fi

if [[ $ArchiveMode == "No" ]]
then
	LogCons "Switch off Archiving on $DatabaseName, $SourceServerName"
	ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ $OFA_SQL/SwitchArcLogging.sql off"
fi
}
#---------------------------------------------
RestoreDatabase ()
#---------------------------------------------
{
SourceServerName=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "hostname -s")
ArchStatusLog=$OFA_LOG/tmp/MoveDB.sh.ArchStatusLog.$DatabaseName.$SourceServerName

LogCons "Restore database: $DatabaseName, on server: $TargetServerName"
LogCons "Log file: $RestoreLog"
rman_restore_bkp.sh Restore $DatabaseName Last > $RestoreLog 2>&1

if [[ $? -ne 0 ]]
then
        LogError "Error restore database: $DatabaseName on serever: $TargetServerName"
        LogError "Restore log: $RestoreLog"
        exit 1
fi

ArchiveMode=$(cat $ArchStatusLog | awk '{print $4}')
LogCons "Archive mode of source server: $ArchiveMode"

if [[ $ArchiveMode == "No" ]]
then
        LogCons "Switch off Archiving on $DatabaseName, $TargetServerName"
        OraEnv $DatabaseName ; DoSqlQ $OFA_SQL/SwitchArcLogging.sql off
fi

}
#---------------------------------------------
CopyFiles ()
#---------------------------------------------
{
LogCons "Copy files from $SourceHost to $TargetHost"
LogCons "Create new init file on Source database."
ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ ''create pfile from spfile\;''" 
# LogCons "Stopping Target database..."
# ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ ''shutdown immediate\;''" 

scp $SourceHost:$ORACLE_HOME/dbs/*${DatabaseName}.ora $ORACLE_HOME/dbs
if [[ $? -ne 0 ]]
then
         LogError "Error during copy files. ($SourceHost:$ORACLE_HOME/dbs/*${DatabaseName}.ora $ORACLE_HOME/dbs)"
         exit 1
fi


MgwExist=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "ls -l /oracle/rdbms/admin/mgw/$DatabaseName > /dev/null 2>&1; echo \$?")
if [[ $MgwExist -ne 0 ]]
then
	LogCons "No MGW installed..."
else
	LogCons "Copy MGW init file."
	mkdir -p /oracle/rdbms/admin/$DatabaseName
	scp -r $SourceHost:/oracle/rdbms/admin/$DatabaseName/* /oracle/rdbms/admin/$DatabaseName
                if [[ $? -ne 0 ]]
                then
                        LogError "Error during copy files. ($SourceHost:/oracle/rdbms/admin/$DatabaseName/*)"
                        exit 1
                fi

fi 

# FilesToCopy="$OFA_DB_DATA/$DatabaseName $OFA_DB_ARCH/$DatabaseName $OFA_SCR/mep/$DatabaseName $OFA_SCR/refresh/$DatabaseName $OFA_SCR/expl/$DatabaseName"
FilesToCopy="$OFA_DB_BKP/$DatabaseName/rman $OFA_SCR/mep/$DatabaseName $OFA_SCR/refresh/$DatabaseName $OFA_SCR/expl/$DatabaseName"


for i in $FilesToCopy
do
	LogCons "Check files in $i"
	AnyFiles=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost "ls -l $i/* > /dev/null 2>&1; echo \$?")
	if [[ $AnyFiles -eq 0 ]]
	then
		LogCons "Copy files in $i"
		scp -r $SourceHost:$i/* $i
		if [[ $? -ne 0 ]]
		then
			LogError "Error during copy files. ($SourceHost:$i/*)"
			exit 1
		fi

		ssh $SourceHost "ls -l $i/*" | awk '{print $5,$9}' > $FileListSource
		ls -l $i/* | awk '{print $5,$9}' > $FileListTarget
		echo ""
		LogCons "Check file size between source/target"
		cat $FileListSource | while read line
		do
		# echo $line
			SourceFileSize=$(echo $line | awk '{print $1}')
			SourceFileName=$(echo $line | awk '{print $2}')
			TargetFileSize=$(grep $SourceFileName $FileListTarget | awk '{print $1}')
			LogCons "File Name: $SourceFileName Source File Size: $SourceFileSize Target File Size: $TargetFileSize"
			if [[ $SourceFileSize -ne $TargetFileSize ]]
			then
				LogError "Error in file size !!!!!!!"
				exit 1
			fi
		done	
		echo ""

	else
		LogCons "No files directory: in $i"
	fi
done



}
#---------------------------------------------
StartDB ()
#---------------------------------------------
{
LogCons "Startup Database."
LogCons "Log file: $SqlLog"
DoSqlQ "create spfile from pfile;" | tee $SqlLog
DoSqlQ "startup;" | tee -a $SqlLog
ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; . ~/*/local/dba/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DatabaseName ; DoSqlQ ''startup\;''" | tee -a $SqlLog

ErrorMess=$(grep "ORA-" $SqlLog)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error Start databases. Log file: $SqlLog"
        exit 1
fi

}

#---------------------------------------------
MoveListConf ()
#---------------------------------------------
{
LogCons "Copy sqlnet configuration from $SourceServerName to $TargetServerName"
LogCons "Saving old configuration as [FileName].YYYY_MM_DD_HHMISS"
SqlnetFiles="listener.ora sqlnet.ora tnsnames.ora ldap.ora"
for i in $SqlnetFiles
do 
if [[ -r $OFA_TNS_ADMIN/$i ]]
then
	move_old.sh $OFA_TNS_ADMIN/$i | grep -v "FilesToDelete:"
fi
done

RemoteFiles=$(ssh -q -o "StrictHostKeyChecking no" $SourceHost ". .bash_profile ; cd $OFA_TNS_ADMIN ; ls -1 listener.ora sqlnet.ora tnsnames.ora ldap.ora 2>&1 | grep -v \"No such file or directory\"")
for i in $RemoteFiles
do
	LogCons "Copy $OFA_TNS_ADMIN/$i from $SourceServerName to $TargetServerName"
	scp $SourceHost:$OFA_TNS_ADMIN/$i $OFA_TNS_ADMIN/$i.$SourceServerName.$DatabaseName
	cp $OFA_TNS_ADMIN/$i.$SourceServerName.$DatabaseName $OFA_TNS_ADMIN/$i
	ln -sf $OFA_TNS_ADMIN/$i $ORACLE_HOME/network/admin
done
}
#---------------------------------------------
ConfListener ()
#---------------------------------------------
{
LogCons "Config listener/tnsname if not existing in listener.ora/tnsnames.ora"
ListExist=$(grep "LISTENER_${DatabaseName}" $OFA_TNS_ADMIN/listener.ora)
if [[ -z $ListExist ]]
then
	$OFA_BIN/RebSQLNet.sh ADD ${DatabaseName} NoRestart
else
	LogCons "Already in listener.ora/tnsnames.ora"
fi
}
#---------------------------------------------
# Main
#---------------------------------------------
# set -xv
typeset -r SLEEPTIME=2

REVON=$(tput smso)  # Reverse on.
REVOFF=$(tput rmso) # Reverse off.

Option=$2
selection=$Option

while :
do
if [[ -z $selection  ]]
then
    # clear
    print
    print
    print "$REVON Move database: $DatabaseName from $SourceServerName to $TargetServerName  $REVOFF"
    print
    print "\tOptions:"
    print "\t-----------------------------------------------------------------"
    print "\t1) Check Connect to source host: $SourceHost, $SourceServerName"
    print "\t2) Check directories on target server: $TargetServerName"
    print "\t3) Cleanup directories on target server: $TargetServerName"
    print "\t4) Check directory Size on target server: $TargetServerName"
    print "\t5) Check Oracle home source vs target server."
    print "\t6) Backup Database Source database: ${DatabaseName} on server: $SourceServerName"
    print "\t7) Copy files from $SourceServerName to $TargetServerName"
    print "\t8) Restore database: ${DatabaseName} on target server: $TargetServerName"
    print "\t9) Move sqlnet configuration from $SourceServerName to $TargetServerName."
    print "\t10) Check connection to Repo server: $RepoServer"
    print
    print "\t90) Run all steps"
    print
    print "\n\tOther Options:"
    print "\t----------------"
    print "\tr) Refresh screen"
    print "\tq) Quit"
    print
    print "\tEnter your selection: r\b\c"
    read selection
    if [[ -z "$selection" ]]
        then selection=r
    fi
fi
    case $selection in
        1)  print "\nYou selected option 1"
            CheckConnect
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        2)  print "\nYou selected option 2"
            CheckDir
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        3)  print "\nYou selected option 3"
            CleanUp
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        4)  print "You selected option 4"
            CheckSize
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        5)  print "You selected option 5"
            CheckHome
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        6)  print "You selected option 6"
            BackupDatabase
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        7)  print "You selected option 7"
            CopyFiles            
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        8)  print "You selected option 8"
            RestoreDatabase
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        9)  print "You selected option 9"
	    MoveListConf
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
        10)  print "You selected option 10"
             CheckConnectRepo
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;

        90) print "You selected option 90"
            CheckConnect
            CheckDir
            CleanUp
            CheckSize
            CheckHome
            BackupDatabase
            CopyFiles
            RestoreDatabase
            MoveListConf
            CheckConnectRepo
		if [[ ! -z $Option ]]; then exit; else unset selection; fi
            ;;
      r|R)  continue
            ;;
      q|Q)  print
            exit
            ;;
        *)  print "\n$REVON Invalid selection $REVOFF"
            read
            ;;
    esac
done

#---------------------------------------------
