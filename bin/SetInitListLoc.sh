#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22 > /dev/null 2>&1

OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"
OFA_MAIL_RCP_BAD="no mail"


Usage ()
{
#
##
## Usage: TestDbLink.sh [SID]
##
## If no parameter set it will run on all databases with status OPEN
## 
## Setting the local_listener parameter to '' in the database and
## updating the ../refresh/[SID]/init[SID].ora file with 
## "*.local_listener=''.
##
#
exit 1
}


if [ ! -z $1 ]; then
	DbList=$1
else
	DbList=$(ListOraDbs | grep -v OEMAGENT | sort | tr "\n" " ")
fi

LogCons "-----------------------------------------------------------------------------"
LogCons "Database List: $DbList "

for i in $DbList
do 

	OraEnv $i  > /dev/null 2>&1
	LogCons "-----------------------------------------------------------------------------"
	LogCons "Database: $ORACLE_SID status: $(OraDbStatus)"
	LogCons "-----------------------------------------------------------------------------"
	if [ "$(OraDbStatus)" == "OPEN" ] ; then
	InitRefDir=$OFA_SCR/refresh/$ORACLE_SID
	InitRefFile=$InitRefDir/init$ORACLE_SID.ora
	InitRefFileTmp=/tmp/init$ORACLE_SID.ora.tmp
		LogCons "Connecting to Database: $ORACLE_SID"

		MessageSql=$(DoSqlV "alter system set local_listener = '' scope=both;" | grep ORA)
		LogCons "Setting paramater: local_listener = ''"

		if [ ! -z "$MessageSql" ]; then
			LogError "Error by set parameter: $MessageSql" 
		else
			[[ ! -d  $InitRefDir ]] && mkdir -p $InitRefDir 
			if [ -r $InitRefFile ] ; then
				cat  $InitRefFile | grep -v "local_listener" > $InitRefFileTmp
				echo "*.local_listener=''" >> $InitRefFileTmp
				mv $InitRefFileTmp $InitRefFile
			else
				echo "*.local_listener=''" > $InitRefFile
			fi
		LogCons "Updated $InitRefFile"
		fi
	else
        	LogError "Can't connect to database $ORACLE_SID database is NOT in OPEN "mode""
        fi
done



VolSet -10000
