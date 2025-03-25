#!/bin/ksh
#
##  
##  Usage: RemoveArchive.sh [SID] 
##
##  If [SID]= ALL the delete will be done on all OPEN DB's defined in oratab.
##  Delete all the archive files for the database.
##  (Leave the two newest archive files.)
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
## Usage: RemoveArchive.sh  [SID]
##
##
## Paremeter:
##
## SID:
##      Name of the database
##      or
##      "ALL" will run for all database on the server
##
## Delete all archive file for the Database. 
##
#
__EOF
LogError "Missing or wrong parameter"
exit 1
}
#---------------------------------------------

FirstPara=$1

    LogCons "Check variable completeness"
    CheckVar                       \
        FirstPara                  \
     || usage


     # && LogIt "Variables complete" \
if [[ "$FirstPara" == "ALL" ]]
then
	 # DbList=$(ListOraDbs | tr "\n" " ")
    DbList=$(ListOraDbs | grep -v OEMAGENT | sort | tr "\n" " ")
	LogCons "Database list for remove archive logs: $DbList"
else
	DbList=$FirstPara
fi


for i in $DbList
do
ORACLE_SID=$i

  #
  # set Oracle environment
  #
    OraEnv $ORACLE_SID || BailOut "Failed OraEnv \"$ORACLE_SID\""

  #
  # check that no other rman task is running on the same target from ofa
  #
# set -xv
    ADD_FILTER=BlaBla_DUMMY
    CheckConcurrentTask "$ORACLE_SID" && BailOut "Concurrency - cannot run (see warnings)"

  LogCons "Removing archive files for DB: $ORACLE_SID"

  if [ "$(OraDbStatus)" != "OPEN" ] ; then
	  if [ "$(OraStartupFlag)" == "D" ] ; then
		LogCons "$ORACLE_SID is a DUMMY database"
	  else
		LogWarning "Database ($ORACLE_SID) NOT in OPEN state"
          fi
  else

  	# ArchiveDir=$(DoSqlQ "show parameter log_archive_dest;" | grep -v "log_archive_dest_state_" | awk '{print $3}')
	ArchiveDir=$(DoSqlQ "show parameter log_archive_dest;" | grep -w "log_archive_dest_1" | awk -F "=" '{print $2}')
  	ArchFileNameExt=$(DoSqlQ "show parameter log_archive_format;" | awk '{print $3}' | awk -F "." '{print $NF}')
  	LogCons "Archive file directory: $ArchiveDir"
  	LogCons "Archive file ext: $ArchFileNameExt"

  	FileNames=$(ls -1rt $OFA_MY_DB_ARCH/*${ArchFileNameExt} 2>/dev/null | grep -v "No such file or directory" | sed '$d')
        # echo "**** $FileNames ****"

  #
  # For standby databases 
  #

        DbType=$(OraDBRole | awk -F ":" '{print $1}')

        LogCons "Database type: $DbType"
        if [[ $DbType == PHYSICAL ]] || [[ $DbType == PRIMARY ]]
	then
                LogCons "Checking for file not added to the standby DB."
		ArcNotAdded=$(DoSqlQ "select name from v\$archived_log a, (select sequence# from v\$archived_log where dest_id = 2 and applied ='NO') b where a.sequence# = b.sequence# and dest_id = 1;")

                # LogCons "Not Added arch files: $ArcNotAdded"

		for i in $ArcNotAdded
		do
			FileNames=$(echo $FileNames | grep -v $i)
		done
                echo "File names to delete: $FileNames"
	fi

        # echo "**** $FileNames ****"

  	for i in $FileNames
  	do
		if [ ! -w $i ] ; then
			LogError "Files: $i are NOT writable for current process"
       		 else
			LogCons "Deleting file: $i"
			rm $i 
	
        	fi
  	done
  fi
done
