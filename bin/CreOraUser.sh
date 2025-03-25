#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#
##
## Usage: CreOraUser.sh [SID] [USER_NAME] <TABLE_SPACE_NAME>
##
## Create UBP standard oracle user.
##
## Paramaters:
## SID:
##	SID of the database
##       
## USER_NAME:	
##	Name of new user.
##       
## TABLE_SPACE_NAME: 
##	Will be used as default TS for the schema.
##	Table space must exist !!!!!
##       
#


#
# Set var
#
OFA_MAIL_RCP_BAD="no mail"
DatabaseName=$1
UserName=$2

typeset -u TableSpaceNameInput
TableSpaceNameInput=$3

#
typeset -u TableSpaceNameData
export TableSpaceNameData=${UserName}_DATA

typeset -u TableSpaceNameIdx
export TableSpaceNameIdx=${UserName}_INDEX
#

RmanConfFile=$OFA_ETC/rman_tape_bkp/rman_tape_bkp.defaults
CreSchemaLog=$OFA_LOG/tmp/cre.user.sh.CreSchemaLog.$$.$PPID.log
CreTSLog=$OFA_LOG/tmp/cre.user.sh.CreTSLog.$$.$PPID.log
CheckTSLog=$OFA_LOG/tmp/cre.user.sh.CheckTSLog.$$.$PPID.log

  LogCons "Checking variables."
  CheckVar                   \
        DatabaseName         \
        UserName             \
  && LogCons "Variables OK!" \
  || Usage

#------------------------------------------------
CheckVar ()
#------------------------------------------------
{

OraEnv $DatabaseName > /dev/null || BailOut "Failed OraEnv \"$DatabaseName\""

OraDbStatus > /dev/null || BailOut "Database $DatabaseName DOWN  OraEnv \"$DatabaseName\""
}
#------------------------------------------------
CreateSchema ()
#------------------------------------------------
{
LogCons "Create Schema: $UserName in database: $DatabaseName"


if [[ ! -z $TableSpaceNameInput ]]
then
        TableSpaceNameIdx=$TableSpaceNameInput
fi


sqlplus -s "/as sysdba"  << ___EOF  >> $CreSchemaLog 2>&1
$DropUser
CREATE USER $UserName
  IDENTIFIED BY "blaBLA123+" 
  DEFAULT TABLESPACE $TableSpaceNameData
  TEMPORARY TABLESPACE TEMP
  PROFILE DEFAULT
  ACCOUNT UNLOCK;
  -- Grant
  GRANT CONNECT TO $UserName;
  GRANT RESOURCE TO $UserName;
  GRANT APP_OWNER TO $UserName;
  -- 1 Tablespace Quota for $DatabaseName 
  ALTER USER $UserName QUOTA UNLIMITED ON $TableSpaceNameData;
  ALTER USER $UserName QUOTA UNLIMITED ON $TableSpaceNameIdx;
___EOF


ErrorMess=$(grep ORA- $CreSchemaLog)
if [[ ! -z "$ErrorMess" ]]
then
	LogError "Error create user:$UserName In the database: $DatabaseName"
	LogError "Error: $ErrorMess"
	LogError "Log file: $CreSchemaLog"
	exit 1
else 
	LogCons "Log file: $CreSchemaLog"
fi

LogCons "Set password for user: $UserName"
UserPassword=$(DoSqlQ $OFA_SQL/SetPass.sql $UserName | grep "Instance name: ")
LogCons "$UserPassword"
}
#------------------------------------------------
CreTableSpace ()
#------------------------------------------------
{

# Create tablespace
typeset -u TableSpaceNameData 
TableSpaceNameData=${UserName}_DATA

typeset -u TableSpaceNameIdx
TableSpaceNameIdx=${UserName}_INDEX

typeset -l FileNameData
FileNameData=${UserName}_DATA01.dbf

typeset -l FileNameIdx
FileNameIdx=${UserName}_INDEX01.dbf


LogCons "Create"
LogCons "Tablespace: $TableSpaceNameData, Data file: $FileNameData"
LogCons "Tablespace: $TableSpaceNameIdx, Data file: $FileNameIdx"
LogCons "Log file: $CreTSLog"
sqlplus -s "/as sysdba" << ____EOF >> $CreTSLog 2>&1
whenever sqlerror exit 1
whenever oserror exit 1
CREATE BIGFILE TABLESPACE $TableSpaceNameData DATAFILE
  '/$OFA_DB_DATA/$DatabaseName/$FileNameData' SIZE 1G AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED
LOGGING
ONLINE
EXTENT MANAGEMENT LOCAL AUTOALLOCATE
-- BLOCKSIZE 8K
SEGMENT SPACE MANAGEMENT AUTO
FLASHBACK ON;


CREATE BIGFILE TABLESPACE $TableSpaceNameIdx DATAFILE
  '/$OFA_DB_DATA/$DatabaseName/$FileNameIdx' SIZE 1G AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED
LOGGING
ONLINE
EXTENT MANAGEMENT LOCAL AUTOALLOCATE
-- BLOCKSIZE 8K
SEGMENT SPACE MANAGEMENT AUTO
FLASHBACK ON;
____EOF

ErrorMess=$(grep "ORA-" $CreTSLog)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error Creating tablespace:$TableSpaceName "
        LogError "Error: $ErrorMess"
        LogError "Log file: $CreTSLog"
	# exit 1
else 
	LogCons "Log file: $CreTSLog"
fi

}
#------------------------------------------------
CheckTableSpace ()
#------------------------------------------------
{
sqlplus -s "/as sysdba" << ____EOF >> $CheckTSLog 2>&1
select TABLESPACE_NAME from dba_tablespaces where TABLESPACE_NAME='$TableSpaceNameInput';
____EOF

Output=$(grep "no rows selected" $CheckTSLog)
if [[ ! -z "$Output" ]]
then
        LogError "Table space: $TableSpaceNameInput don't exist"
	exit 1
fi

ErrorMess=$(grep "ORA-" $CheckTSLog)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Error checking tablespace:$TableSpaceName "
        LogError "Error: $ErrorMess"
        LogError "Log file: $CreTSLog"
        exit 1
fi

TableSpaceNameData=$TableSpaceNameInput

}
#------------------------------------------------
# Main
#------------------------------------------------
CheckVar

if [[ ! -z "$TableSpaceNameInput" ]]
then
	CheckTableSpace
else
	CreTableSpace
fi

CreateSchema
