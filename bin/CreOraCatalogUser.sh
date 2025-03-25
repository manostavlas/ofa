#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: CreOraCatalogUser.sh [DATABASE_NAME] 
##
## Create oracle for the rman backup catalog.
##
## Paramaters:
##       
## DATABASE_NAME:	
##	The database Name that you want to add on the catalog.
##       
##       
#


#
# Set var
#
OFA_MAIL_RCP_BAD="no mail"
DatabaseName=$1

#
#

RmanConfFile=$OFA_ETC/rman_tape_hot_bkp/rman_tape_hot_bkp.defaults
CreSchemaLog=$OFA_LOG/tmp/cre.catalog.user.sh.CreCatalogUserLog.$$.$PPID.log

  LogCons "Checking variables."
  CheckVar                   \
        DatabaseName         \
  && LogCons "Variables OK!" \
  || Usage


#------------------------------------------------
CheckExtistingUser ()
#------------------------------------------------
{

RESULT=$(sqlplus -s "/as sysdba" <<EOF
SET HEADING OFF 
SET PAGESIZE 0 
SET TIMING OFF
SET FEEDBACK OFF
select count(*) from dba_users where username=UPPER('${DatabaseName}'); 
EXIT;
EOF
)

if [ "$RESULT" -gt 0 ]; then
    LogCons "User already exists."
else
    LogCons "User does not exist."
fi

}

#------------------------------------------------
CreateSchema ()
#------------------------------------------------
{
LogCons "Create Schema: $DatabaseName"

RunMmDp

RESULT=$(sqlplus -s "/as sysdba" <<EOF
SET HEADING OFF 
SET PAGESIZE 0 
SET TIMING OFF
SET FEEDBACK OFF
select  count(*) from dba_users where username=UPPER('${DatabaseName}'); 
EXIT;
EOF
)

if [ "$RESULT" -gt 0 ]; then
    echo "User already exists."
else

sqlplus -s "/as sysdba"  << ___EOF  >> $CreSchemaLog 2>&1
    CREATE USER $DatabaseName IDENTIFIED BY "$RMAN_CONN"
      DEFAULT TABLESPACE RECOVERY_CATALOG
      TEMPORARY TABLESPACE TEMP
      PROFILE DEFAULT ACCOUNT UNLOCK;
      GRANT RECOVERY_CATALOG_OWNER TO $DatabaseName;
      ALTER USER $DatabaseName DEFAULT ROLE ALL;
      ALTER USER $DatabaseName QUOTA UNLIMITED ON RECOVERY_CATALOG;
    EXIT;
___EOF

fi

ErrorMess=$(grep ORA- $CreSchemaLog)
if [[ ! -z "$ErrorMess" ]]
then
	LogError "Error create user:$DatabaseName  "
	LogError "Error: $ErrorMess"
	LogError "Log file: $CreSchemaLog"
	exit 1
else 
	LogCons "Log file: $CreSchemaLog"
fi

}

#------------------------------------------------
CreateDBCatalog ()
#------------------------------------------------
{

rman  << ___EOF
CONNECT CATALOG  $DatabaseName/$RMAN_CONN@RCDPRD
CREATE CATALOG;
exit
___EOF

    if [[ $? -eq 0 ]]; then
        LogCons "The catalog for $DatabaseName created successfully."
        LogCons "Now you should connect on $DatabaseName and run a register database on rman"

    else
        LogCons "Failed to create the catalog catalog."

    fi

}

#------------------------------------------------
# Main
#------------------------------------------------
LogCons "${RMAN_CONN}"

LogCons "${RMAN_CONN}"
#CreateSchema

#CreateDBCatalog
