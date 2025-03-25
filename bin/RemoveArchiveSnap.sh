#!/bin/ksh
#
##  
##  Usage: RemoveArchiveSnap.sh [SID] 
##
##  Delete all the archive files for the database, older than the second
##  CRM snapshot.
##
#

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

  #
  # Pattern for CheckConcurrentTask
  #
    export OFA_CONCURR_EXCL="rman_hot_bkp|rman_arch_bkp|rman_cold_bkp|rman_tape_bkp|refresh.duplicate.rc|DgAdm"


    OFA_MAIL_RCP_DFLT="no mail"
    OFA_MAIL_RCP_GOOD="no mail"
    OFA_MAIL_RCP_BAD="no mail"

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: RemoveArchiveSnap.sh  [SID]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##
##  Delete all the archive files for the database, older than the second
##  CRM snapshot.
##
#
__EOF
LogError "Missing or wrong parameter"
exit 1
}

#------------------------------------------------------
ArchiveFilesToDelAfterSnap ()
#------------------------------------------------------
{
	echo "Running function ArchiveFilesToDelAfterSnap"
	ArchiveDir=$(DoSqlQ "show parameter log_archive_dest;" | grep -w "log_archive_dest_1" | awk -F "=" '{print $2}')
  	ArchFileNameExt=$(DoSqlQ "show parameter log_archive_format;" | awk '{print $3}' | awk -F "." '{print $NF}')

  	LogCons "Archive file directory: $ArchiveDir"

        if [[ ! -d $ArchiveDir ]]
	then
		LogError "Directory: $ArchiveDir DON'T exist"
		exit 1
	fi

  	LogCons "Archive file extention name: .$ArchFileNameExt"

	LogCons "Getting Delete date...."
	LogCons "Log file:$SqlLog"

	sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off
	select TAG, to_char(min(COMPLETION_TIME),'DD MON YYYY HH24:MM')  as completion_time, min(COMPLETION_TIME) as min_time  
	from v\$backup_files where tag like '%ECX%' group by tag order by min_time desc fetch first 2 rows only;
__EOF


	ErrorMsg=$(grep ORA- $SqlLog)
      	if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Get archive date, Log file: $SqlLog"
		exit 1
        fi
	
	if [[ -s $SqlLog ]]
	then
		SnapInfo=$(tail -1 $SqlLog)
 		SnapName=$(echo $SnapInfo | awk '{print $1}')       
 		SnapDate=$(echo $SnapInfo | awk '{print $2,$3,$4,$5}')       

        	LogCons "Snapshot "name": $SnapName Snapshot date: $SnapDate. "
		LogCons "File(s) to be deleted list: $FilesToDelSnap"
		find $ArchiveDir -not -newermt  "$SnapDate" -ls | awk '{print $8,$9,$10,$11}' | grep "\.$ArchFileNameExt" | sort -k4 > $FilesToDelSnap
	else
		LogCons "No snapshot exist !"
		> $FilesToDelSnap
	fi
}
#------------------------------------------------------

FirstPara=$1

    LogCons "Check variable completeness"
    CheckVar                       \
        FirstPara                  \
     || usage

ORACLE_SID=$FirstPara
TimeStampLong=$(date +"%y%m%d_%H%M%S")
SqlLog=$OFA_LOG/tmp/SqlLog.$FirstPara.RemoveArchiveSnap.$$.$PPID.$TimeStampLong.log
FilesToDel=$OFA_LOG/tmp/FilesToDel.$FirstPara.RemoveArchiveSnap.$$.$PPID.$TimeStampLong.log
FilesToDelPrim=$OFA_LOG/tmp/FilesToDelPrim.$FirstPara.RemoveArchiveSnap.$$.$PPID.$TimeStampLong.log
FilesToDelSnap=$OFA_LOG/tmp/FilesToDelSnap.$FirstPara.RemoveArchiveSnap.$$.$PPID.$TimeStampLong.log
# DatabaseType=$(OraDBRole.sh $ORACLE_SID)
DatabaseType=$(OraDBRole | awk -F ":" '{print $1}')
RmanLog=$OFA_LOG/tmp/RmanLog.RemoveArchiveSnap.$$.$PPID.$TimeStampLong.log
  #
  # set Oracle environment
  #
    OraEnv $ORACLE_SID || BailOut "Failed OraEnv \"$ORACLE_SID\""

  #
  # check that no other rman task is running on the same target from ofa
  #
    ADD_FILTER=BlaBla_DUMMY
    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  LogCons "Removing archive files for DB: $ORACLE_SID"
  LogCons "Database type: $DatabaseType"

# set -xv
if [[ "$DatabaseType" == "PRIMARY" ]] || [[ "$DatabaseType" == "STANDALONE" ]]
then
  if [ "$(OraDbStatus)" != "OPEN" ] ; then
		LogWarning "Database ($ORACLE_SID) NOT in OPEN state"
                exit 1
  fi
elif [[ "$DatabaseType" == "PHYSICAL STANDBY" ]] 
then
  if [ "$(OraDbStatus)" != "MOUNTED" ] ; then
                LogWarning "Database ($ORACLE_SID) NOT in MOUNTED state"
                exit 1
  fi
fi

LogCons "Database: $ORACLE_SID Status: $(OraDbStatus) Type: $DatabaseType"

# Clenup v$archived_log for archive file ther don't exist
LogCons "Cleanup v\$archived_log table for archive file there don't exist"
LogCons "Log file: $RmanLog"
rman << ___EOF > $RmanLog 2>&1
connect target /
run {
allocate channel d1 type disk;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
}
___EOF

        ErrorMsg=$(grep RMAN- $RmanLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error cleanup v\$archived_log. Log file: $RmanLog"
                exit 1
        fi



if [[ "$DatabaseType" == "PHYSICAL STANDBY" ]]
then
        sqlplus -s "/as sysdba" << __EOF > $FilesToDel 
        set feedback off
        set echo off
        set timing off
        set heading off
	select name from v\$archived_log where applied = 'YES' and name like (select replace(value,'LOCATION=','')||'/%' from v\$parameter where name = 'log_archive_dest_1') order by name;
	-- select name from v\$archived_log where name like (select replace(value,'LOCATION=','')||'/%' from v\$parameter where name = 'log_archive_dest_1') order by name;
__EOF

        ErrorMsg=$(grep ORA- $FilesToDel)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Getting archive file to deleted." 
		LogError "Log file: $SqlLog"
                exit 1
        fi


elif [[ "$DatabaseType" == "PRIMARY" ]]
then
	LogCons "$DatabaseType"
        sqlplus -s "/as sysdba" << __EOF > $FilesToDelPrim
        set feedback off
        set echo off
        set timing off
        set heading off
        select name from v\$archived_log where name like (select replace(value,'LOCATION=','')||'/%' from v\$parameter where name = 'log_archive_dest_1') order by name;
__EOF

        ErrorMsg=$(grep ORA- $FilesToDelPrim)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Getting archive file to dataete. Log file: $SqlLog"
                exit 1
        fi

	ArchiveFilesToDelAfterSnap
	LogCons "Merge $FilesToDelPrim and $FilesToDelSnap to $FilesToDel"
	grep -Ff $FilesToDelPrim $FilesToDelSnap > $FilesToDel


elif [[ "$DatabaseType" == "STANDALONE" ]]
then
	LogCons "$DatabaseType"
	ArchiveFilesToDelAfterSnap
	cat $FilesToDelSnap > $FilesToDel
else
	LogCons "Wrong type: $DatabaseType"
fi

LogCons "List of archive to delete: $FilesToDel"

sed -i '/^$/d' $FilesToDel

# echo "*** READ ***"
# read




	while read -r i ;
	do
		FileNameRm=$(echo $i | awk '{print $NF}')
		LogCons "Deleting file: $FileNameRm"
		rm $FileNameRm
		RmError=$?
		if [[ $RmError -ne 0 ]] 
		then
			LogError "Error deleting file: $FileNameRm"
			exit 1
		fi
			
	# 	LogCons "file deleted: $FileNameRm"
	done < "$FilesToDel"

