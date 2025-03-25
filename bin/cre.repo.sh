#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: cre.repo.sh [SID]
##
## Create RMAN repository for the database [SID] [FUNCTION]
##
## Paramaters:
## SID:         SID of the database to backup
##
## Function:
##		CRE  Create repository and Register database.
##     		DROP (RECREATE) Will drop the old repository for the database.
##		REG  Register the database to the repository.
##
#


#
# Set var
#
OFA_MAIL_RCP_BAD="no mail"
NewDatabase=$1
Function=$2
RmanConfFile=$OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults
CreSchemaLog=$OFA_LOG/tmp/cre.repo.sh.CreSchemaLog.$$.$PPID.log
CreCatLog=$OFA_LOG/tmp/cre.repo.sh.CreCatLog.$$.$PPID.log
RegCatLog=$OFA_LOG/tmp/cre.repo.sh.RegCatLog.$$.$PPID.log
TnsPingLog=$OFA_LOG/tmp/cre.repo.sh.TnsPingLog.$$.$PPID.log

  LogCons "Checking variables."
  CheckVar                   \
        NewDatabase          \
  && LogCons "Variables OK!" \
  || Usage
#------------------------------------------------
SetRMAN_REPO ()
#------------------------------------------------
{
ListRmanRepo=$( grep RMAN_NAME_REPO $RmanConfFile  | awk -F '=' '{print $2}' | tr '\n' ' ' )
LogCons "RMAN repo DB's: $ListRmanRepo"

for i in $ListRmanRepo
do
	tnsping $i > $TnsPingLog 2>&1
	ErrorMess=$(grep "TNS-" $TnsPingLog)
	if [[ -z "$ErrorMess" ]]
	then
		LogCons "Connecting to RMAN repo: $i"
	 	RMAN_REPO=$i	
		break
	fi
done

if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error tnsping: $i"
        LogError "Error: $ErrorMess"
        LogError "Log file: $TnsPingLog"
        exit 1
fi

}
#------------------------------------------------
CheckVar ()
#------------------------------------------------
{

OraEnv $NewDatabase > /dev/null || BailOut "Failed OraEnv \"$NewDatabase\""

OraDbStatus > /dev/null || BailOut "Database $ORACLE_SID DOWN  OraEnv \"$NewDatabase\""

# RMAN_REPO=$(grep RMAN_REPO $RmanConfFile | awk -F '=' '{print $2}')
RMAN_CONN=$(grep RMAN_CONN $RmanConfFile | awk -F '=' '{print $2}')

if [[ -z "$RMAN_REPO" ]] || [[ -z "$RMAN_CONN" ]] 
then
	LogError "Error reading parameter: RMAN_REPO or RMAN_CONN from file: $RmanConfFile"
	exit 1
else
	LogCons "RMAN Repository database: $RMAN_REPO"
fi

SetRMAN_REPO

# tnsping $RMAN_REPO > $TnsPingLog 2>&1
# ErrorMess=$(grep "TNS-" $TnsPingLog)
# 
# if [[ ! -z "$ErrorMess" ]]
# then
#         LogError "Error tnsping: $RMAN_REPO"
#         LogError "Error: $ErrorMess"
#         LogError "Log file: $TnsPingLog"
#         exit 1
# fi
}
#------------------------------------------------
CreateSchema ()
#------------------------------------------------
{
LogCons "Create Schema: $NewDatabase in repository database: $RMAN_REPO"
LogCons "$DropUserMessage"
# LogCons "Please, Enter system password for DB $RMAN_REPO !!!!!"
#           printf "
# Password:      => "
# stty -echo
# read SystemPassword
# stty echo
# echo ""

RunMmDp

# sqlplus -s SYSTEM/$SystemPassword@$RMAN_REPO << ___EOF  >> $CreSchemaLog 2>&1
sqlplus -s SYSTEM/$MmDp@$RMAN_REPO << ___EOF  >> $CreSchemaLog 2>&1
$DropUser
CREATE USER $NewDatabase
  IDENTIFIED BY $RMAN_CONN
  DEFAULT TABLESPACE RECOVERY_CATALOG
  TEMPORARY TABLESPACE TEMP
  PROFILE DEFAULT
  ACCOUNT UNLOCK;
  -- 1 Role for DBATST1 
  GRANT RECOVERY_CATALOG_OWNER TO $NewDatabase;
  ALTER USER $NewDatabase DEFAULT ROLE ALL;
  -- 1 Tablespace Quota for $NewDatabase 
  ALTER USER $NewDatabase QUOTA UNLIMITED ON RECOVERY_CATALOG;
___EOF


ErrorMess=$(grep ORA- $CreSchemaLog)
if [[ ! -z "$ErrorMess" ]]
then
	LogError "Error create user:$NewDatabase In the database: $RMAN_REPO"
	LogError "Error: $ErrorMess"
	LogError "Log file: $CreSchemaLog"
	exit 1
else 
	LogCons "Log file: $CreSchemaLog"
fi
}
#------------------------------------------------
CreateCatalog ()
#------------------------------------------------
{

# Create catalog

LogCons "Create catalog for Database: $NewDatabase in repository database: $RMAN_REPO"
rman using $NewDatabase $RMAN_CONN $RMAN_REPO << ___EOF >> $CreCatLog 2>&1
CONNECT CATALOG &1/&2@&3 
CREATE CATALOG;
exit
___EOF

ErrorMess=$(grep "RMAN-" $CreCatLog)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error Creating catalog for database :$NewDatabase In the database: $RMAN_REPO"
	LogError "Error: $ErrorMess"
        LogError "Log file: $CreCatLog"
	exit 1
else 
	LogCons "Log file: $CreCatLog"
fi
}
#------------------------------------------------
RegisterDatabase ()
#------------------------------------------------
{
LogCons "Register Database: $NewDatabase in repository database: $RMAN_REPO"
rman using $NewDatabase $RMAN_CONN $RMAN_REPO << ___EOF >> $RegCatLog 2>&1
CONNECT TARGET / 
CONNECT CATALOG &1/&2@&3 
REGISTER DATABASE;
exit
___EOF

ErrorMess=$(grep "RMAN-" $RegCatLog)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error REGISTER database :$NewDatabase In the database: $RMAN_REPO"
	LogError "Error: $ErrorMess"
        LogError "Log file: $RegCatLog"
	exit 1
else 
	LogCons "Log file: $RegCatLog"
fi
}
#------------------------------------------------
# Main
#------------------------------------------------
SetRMAN_REPO
if [[ "$Function" == "CRE" ]]
then
	CheckVar
	CreateSchema
	CreateCatalog
	RegisterDatabase
elif [[ "$Function" == "DROP" ]]
then
	DropUser="DROP user $NewDatabase cascade;"
	DropUserMessage="Dropping user: $NewDatabase."
        CheckVar
        CreateSchema
        CreateCatalog
        RegisterDatabase
elif [[ "$Function" == "REG" ]]
then
        CheckVar
        RegisterDatabase
else
        LogError "Wrong FUNCTION! Function: $Function"
        Usage
        exit 1
fi

