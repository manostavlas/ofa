#!/bin/ksh

  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

  #
  # Pattern for CheckConcurrentTask
  #

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
##  Usage: FormatSql.sh [FUNCTION] [see function]
##
## Paremeter:
##
## SID:
##      Name of the database
##
## Function:            Parameters:
##
## SqlId                [SID] Database name
##                      [SQL_ID] all TS's (None system TS's)
##
## File                 [SOURE_FILE] [TARGET_FILE]
##
##
#
__EOF
LogError "Missing or wrong parameter"
exit 1
}
#---------------------------------------------

FuncToDo=$1
TimeStamp=$(date +"%y%m%d_%H%M%S")
MainLog=$OFA_LOG/tmp/$(basename $0).MainLog.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/$(basename $0).SqlLog.$$.$PPID.$TimeStamp.log

#---------------------------------------------
Sqlid ()
#---------------------------------------------
{

    LogIt "Check variable completeness"
    CheckVar                    \
        DbName                  \
        FuncToDo                \
	SqlIdNumber		\
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbName
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi

LogCons "Getting sql from Database: $DbName, SQL_ID:$SqlIdNumber"
LogCons "Log File: $SqlLog"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1

set timing off;
set feedback off;

DECLARE
V_SQLID VARCHAR2 (128);
begin
	select sql_id into V_SQLID from dba_hist_sqltext b where b.sql_id = '$SqlIdNumber';
end;
/

col sql_text form a50000
set long 500000;
set longchunksize 200000;
set trimout on;
set trim on;
set pagesize 0;
set linesize 32767;

select '-- '||b.sql_id||' --'||chr(10), b.SQL_TEXT||chr(10)||';' as sql_text from dba_hist_sqltext b
where sql_id = '$SqlIdNumber';
__EOF
        ErrorMsg=$(grep ORA- $SqlLog | head -n 1)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting sql text, Error: $ErrorMsg Log file: $SqlLog"
                exit 1
        fi
SourceFile=$SqlLog
TargetFile=${SqlLog}.new
File 
}
#---------------------------------------------
File ()
#---------------------------------------------
{
    LogIt "Check variable completeness"
    CheckVar                    \
        SourceFile              \
        TargetFile              \
	FuncToDo                \
     && LogIt "Variables complete" \
     || usage
LogCons "Format sql file: $SourceFile to file: $TargetFile"
perl $OFA_BIN/sql_format_standalone.pl $SourceFile > $TargetFile
}
#---------------------------------------------
# Main
#---------------------------------------------

FuncToDo1=$(echo "$FuncToDo" | sed 's/\(.\).*/\1/' | tr "[a-z]" "[A-Z]")
FuncToDo2=$(echo "$FuncToDo" | sed 's/.\(.*\)/\1/' | tr "[A-Z]" "[a-z]")
FuncToDo=${FuncToDo1}${FuncToDo2}

if [[ "$FuncToDo" == "File" ]]
then
	SourceFile=$2
	TargetFile=$3
	File 
elif [[ "$FuncToDo" == "Sqlid" ]]
then
	DbName=$2
	SqlIdNumber=$3
        Sqlid
else
        usage
fi


