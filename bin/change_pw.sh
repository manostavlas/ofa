#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


#
##
## Usage: change_pw.sh [USER_NAME]
##
## parameters:
## USER_NAME:   Name of user to change password on all oracle databases
##
## Description:
##
##  Changing password for user [USER_NAME] on all database registered in the 
##  GRID database $OFA_GRID_DB
##
#

DbaUser=$1


  #
  # Check var
  #
  LogCons "Checking variables."
  CheckVar                    \
        DbaUser               \
  && LogCons "Variables OK!"  \
  || Usage

 







# echo "Enter User name and Password for User to change the password." | LogCartRidge
#         LogCons "Please, Enter the user name !!!!!"
#           printf "
# Username:      => "
#         read DbaUser
# 

        LogCons "Please, Enter the password for the user: $DbaUser !!!!!"
          printf "
Password:      => "
        stty -echo
        read DbaUserPw
        stty echo
        echo ""


TimeStamp=$(date +"%H%M%S")
TmpLogFile=$OFA_LOG/tmp/change_pw.tmp.$$.$PPID.$TimeStamp.log
SqlExecFile=$OFA_LOG/tmp/change_pw.SqlExecFile.$$.$PPID.$TimeStamp.sql


cat << __EOF  > $SqlExecFile

set echo off;
set serveroutput on;
set long 50000;
set longchunksize 20000;

declare
	VV_DBA_NAME varchar2(64) := UPPER('$DbaUser');
	VV_DBA_PASSWD varchar2(64) := '$DbaUserPw';
	sqlstring varchar2(1024);
	CountUser number;

BEGIN

select count(*) into CountUser from dba_users where username = upper('$DbaUser');

  IF CountUser = 0 THEN
	sqlstring := 'create user $DbaUser identified by "$DbaUserPw"';
	dbms_output.put_line('SQL: create user $DbaUser identified by ........');
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'alter user $DbaUser default tablespace "USERS"';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'alter user $DbaUser profile DEFAULT';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant ALTER SESSION to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant CREATE TABLE to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant CREATE SESSION to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant CONNECT to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant DBA to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'grant UNLIMITED TABLESPACE to $DbaUser';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;

	sqlstring := 'alter user $DbaUser default role all';
	dbms_output.put_line('SQL: '|| sqlstring);
	EXECUTE IMMEDIATE sqlstring;
  ELSE
	sqlstring := 'alter user $DbaUser identified by "$DbaUserPw"';
	dbms_output.put_line('SQL: alter user $DbaUser identified by .......');
	EXECUTE IMMEDIATE sqlstring;
		
  END IF;
END;
/

__EOF


LogCons "Running: $SqlExecFile"

$OFA_BIN/rsql_ora.sh $SqlExecFile "not in ('PRD_DB_SECURE','ATLAS_OFFSHORE')" 

rm $SqlExecFile
