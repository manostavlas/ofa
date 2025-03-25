#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

FuncToDo=$1
DbName=$2
Para3=$3
Para4=$4

ScriptName=$(basename $0)
TimeStampLong=$(date +"%y%m%d_%H%M%S")

SqlScript=$OFA_LOG/tmp/Script.$ScriptName.$DbName.$$.$PPID.$TimeStampLong.sql
SqlLog=$OFA_LOG/tmp/SqlLog.$ScriptName.$DbName.$$.$PPID.$TimeStampLong.log


#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ChangeUser.sh [FUNCTION] [DATABASE_NAME] [see function]
##
## parameters:
##
## DATABASE_NAME:
##	Name of the database.
##
## Function:		Parameter:
##
## Unlock		[DATABASE_NAME] [USERNAME]
##			Unlock user
##
## ChangePw		[DATABASE_NAME] [USERNAME] <PASSWORD>
##			Change password for the user to a random password, if [PASSWORD] is NOT set
##
## Info			[DATABASE_NAME]
##                      List all users.
##
## Remark:
##	   Can't change password in production DB's or on users there have DBA role !!! 
##
#
__EOF
exit 1
}

    CheckVar                       \
        FuncToDo                   \
        DbName                     \
     && LogIt "Variables complete" \
     || usage
RunMmDp
#---------------------------------------------
ChangePw ()
#---------------------------------------------
{
LogCons "Change password user: $Para3 Database: $DbName"
LogCons "Log file: $SqlLog"

PrdDb=$(echo $DbName | grep -i PRD)
if [[ ! -z $PrdDb ]]
then 
	LogError "Can't change password on production !!!!"
	exit 1
fi


RunMmDp

sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLog
set timing off
select GRANTEE from dba_role_privs where granted_role='DBA' and GRANTEE = upper('$Para3');
___EOF

typeset -u NameGrantee

NameGrantee=$(grep -i -w $Para3 $SqlLog)

ErrorCode=$(grep ORA- $SqlLog)

if [[ ! -z $ErrorCode ]]
then
        LogError "Error unlock user: $ErrorCode"
        LogError "Log file: $SqlLog"
fi


if [[ ! -z $NameGrantee ]]
then
	LogError "Can't change password users there have DBA role....."
	exit 1
fi


# tnsping $DbName
if [[ -z $Para4 ]]
then
	sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLog
	set timing off
	@$OFA_SQL/SetPass.sql $Para3
___EOF
else
	sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLog
	set timing off
	alter user $Para3 identified by "$Para4";
___EOF

fi
ErrorCode=$(grep ORA- $SqlLog)
if [[ ! -z $ErrorCode ]]
then
        LogError "Error unlock user: $ErrorCode"
        LogError "Log file: $SqlLog"
fi

echo ""
grep "Instance name:" $SqlLog

}
#---------------------------------------------
Unlock ()
#---------------------------------------------
{
LogCons "Unlock user: $Para3"
LogCons "Log file: $SqlLog"

RunMmDp

# tnsping $DbName

sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLog
set timing off
alter user $Para3 account unlock;
___EOF

ErrorCode=$(grep ORA- $SqlLog)
if [[ ! -z $ErrorCode ]]
then
	LogError "Error unlock user: $ErrorCode"
	LogError "Log file: $SqlLog"
fi

}
#---------------------------------------------
Info ()
#---------------------------------------------
{

LogCons "List users"
LogCons "Log file: $SqlLog"

RunMmDp

# tnsping $DbName

sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLog
set feedback off
set timing off
prompt 
prompt ******* Oracle maintained users ******* 
col username form a50
select username from all_users where oracle_maintained = 'Y' order by 1;
prompt 
prompt ******* NONE oracle maintained users ******* 
col username form a50
select username from all_users where oracle_maintained = 'N' order by 1;
___EOF

cat $SqlLog
}
#---------------------------------------------
CheckConn ()
#---------------------------------------------
{
SqlLogConn=$OFA_LOG/tmp/SqlLog.$ScriptName.$DbName.CheckConn.$$.$PPID.$TimeStampLong.log

LogCons "Check connection"
LogCons "log file: $SqlLogConn"
Ldap=$(Ldaping ${DbName} | grep TNS-)

if [[ ! -z $Ldap ]]
then
	LogError "Database don't exist in LDAP: ${Ldap}"
	exit 1
fi

export TNS_ADMIN=/tmp

ErrorCode=$(grep ORA- $SqlLogConn)
if [[ ! -z $ErrorCode ]]
then
        LogError "Error unlock user: $ErrorCode"
        LogError "Log file: $SqlLogConn"
fi

}
#---------------------------------------------
CheckUser ()
#---------------------------------------------
{
LogCons "Check User"
LogCons "log file: $SqlLogConn"
sqlplus -s SYSTEM/"$MmDp"@${DbName} << ___EOF > $SqlLogConn
col username format a40;
select username from dba_users where oracle_maintained = 'N' and username=upper('$Para3'); 
___EOF

typeset -u UserName
UserName=$(grep -i ${Para3} ${SqlLogConn})

if [[ -z $UserName ]]
then
	LogError "User: $Para3 don't exist or a Oracle maintained user...."
	exit 1
fi


ErrorCode=$(grep ORA- $SqlLogConn)
if [[ ! -z $ErrorCode ]]
then
        LogError "Error unlock user: $ErrorCode"
        LogError "Log file: $SqlLogConn"
fi

}
#---------------------------------------------
# Main
#---------------------------------------------
CheckConn
if [[ "$FuncToDo" == "Info" ]]
then
	Info
elif [[ "$FuncToDo" == "Unlock" ]]
then
    CheckVar                       \
        Para3                      \
     && LogIt "Variables complete" \
     || usage
	CheckUser
	Unlock
elif [[ "$FuncToDo" == "ChangePw" ]]
then
    CheckVar                       \
        Para3                      \
     && LogIt "Variables complete" \
     || usage
	CheckUser
        ChangePw
else
        usage
fi


