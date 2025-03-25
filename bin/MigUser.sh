#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

SourceDB=$1
TargetDB=$2
ParameterFile=$3
ActionPara=$4

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"


#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
## 
##
## Version: v0.7
##
## New function: IMP_PARAMETER=
##               REMAP_FILE_NAME=
##
## Usage: MigSchemas.sh [SOURCE_SID] [TARGET_SID] [PARAMETER_FILE] <ACTION_PARAMATER>
##
##
## Parameter file directory:  $OFA_SCR/refresh/[TARGET_SID]/
## 
## Paremeter:
## 
## SOURCE_SID: 		Source database
## TARGET_SID: 		target database
## PARAMETER_FILE: 	Contain schema names of schemaes to migrate.
## ACTION_PARAMETER:	DROP: 		The schema and tablespaces for the user will be deleted,
##					in the target database will be deleted.
##			
##			TS_SCRIPT:	Will only create tablespace create script.
##
##                      TABLES          If exp/imp table only via parameter IMP_PARAMETER=TABLES=
##
## Target database must be a local DB
##
## For connection to source database first trying via tnsping if failed, trying via Ldaping.
##
## Parameter File:
##
## Mandatory Parameters:
## 
##  ALL PARAMETERS HAVE TO BE IN UPPER CASE !!!!!!!:
##
## SCHEMA= 
##    (Schema name separated with blanks) 
##
## CONVERT_FS_TARGET=
## CONVERT_FS_SOURCE=
##    (Convert tablespace directory names)
##
## Optional Parameters:
##
## IMP_PARAMETER=
##    (Set standard impdb paramater, one parameter per line)
##    (IMP_PARAMETER=[Oracle import parameter])
##
## REMAP_FILE_NAME=
##    (To remap tablespace file names, one line per rename)
##
## e.g. Parameter file:
## SCHEMA=PBRISK PBRISK_ADMIN PBRISK_READ
## CONVERT_FS_TARGET=/DB/BTPPRD
## CONVERT_FS_SOURCE=/ODB/PBRSKPRD
## REMAP_FILE_NAME=pbrisk_dat_01.dbf pbrisk_dat01.dbf
## REMAP_FILE_NAME=pbrisk_idx_01.dbf pbrisk_idx01.dbf
## 
#
__EOF
exit 1
}
#---------------------------------------------
    RunMmDp
    LogIt "Check variable completeness"
    CheckVar                       \
        SourceDB                   \
        TargetDB                   \
        ParameterFile              \
     && LogIt "Variables complete" \
     || usage 

    CheckVar          \
        MmDp          \
    || BailOut "Missings setting of password. Run 'mdp system'"


ParameterDir=$OFA_SCR/refresh/$TargetDB
ParameterFile=$ParameterDir/$ParameterFile
UserParameter=$(grep "SCHEMA=" $ParameterFile | grep -v IMP_PARAMETER | sed 's/SCHEMA=//g' | sed ':a;N;$!ba;s/\n/ /g')
# Create user list in "Oracle" format 'user_name','user_name'
for i in $(echo $UserParameter)
do
  OraUserList=$(echo "$OraUserList'$i',")
done
OraUserList=${OraUserList%?}






DbLinkName=DATA_PUMP_$$_$PPID
ConvertFS_Source=$(grep "CONVERT_FS_SOURCE=" $ParameterFile | sed 's/CONVERT_FS_SOURCE=//g' | sed ':a;N;$!ba;s/\n/ /g')
ConvertFS_Target=$(grep "CONVERT_FS_TARGET=" $ParameterFile | sed 's/CONVERT_FS_TARGET=//g' | sed ':a;N;$!ba;s/\n/ /g')




SqlLog=$OFA_LOG/tmp/SqlLog.$SourceDB.$TargetDB.$$.$PPID.log
SqlTSFile=$OFA_LOG/tmp/CreTS.$SourceDB.$TargetDB.$$.$PPID.sql
SqlTSFileLog=$SqlTSFile.log
SqlDropFile=$OFA_LOG/tmp/Drop.$SourceDB.$TargetDB.$$.$PPID.sql
SqlSymFile=$OFA_LOG/tmp/Sym.$SourceDB.$TargetDB.$$.$PPID.sql
SqlDropFileLog=$SqlDropFile.log
SqlCreDBLinkFileLog=$OFA_LOG/tmp/CreDbLink.$SourceDB.$TargetDB.$$.$PPID.log

ImpParallel=20
ImpParaFile=$OFA_LOG/tmp/ImpParaFile.$SourceDB.$TargetDB.$$.$PPID.par
ImpParaFileRemote=$OFA_LOG/tmp/ImpParaFile.Remote.$SourceDB.$TargetDB.$$.$PPID.par

#--------------------------------------------------------
CreTSScript ()
#--------------------------------------------------------
{
# set -xv
LogCons "Tablespace creation file: $SqlTSFile"

for i in $(echo $UserParameter) 
do

TablespacesNamesTarget=$(DoSqlQ "select ''''|| tablespace_name ||'''' from dba_tablespaces;" | sed -e 'H;${x;s/\n/,/g;s/^,//;p;};d')

sqlplus -s $CONNECT__STRING@$SourceDB << __EOF >> $SqlTSFileLog 2>&1 

SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set echo off;
set heading off;
set timing off;

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT 

begin DBMS_METADATA.SET_TRANSFORM_PARAM (
DBMS_METADATA.SESSION_TRANSFORM,
'SQLTERMINATOR',
TRUE);
end;
/

spool $SqlTSFile append

select 
-- 'prompt Create TS: '||a.tablespace_name||chr(10)|| replace(dbms_metadata.get_ddl('TABLESPACE',a.tablespace_name),instance_name,'$TargetDB')
'prompt Create TS: '||a.tablespace_name||chr(10)|| replace(dbms_metadata.get_ddl('TABLESPACE',a.tablespace_name),'$ConvertFS_Source','$ConvertFS_Target')
from (
	select a.tablespace_name, b.instance_name
	from
	(select distinct tablespace_name, owner from dba_tables
	where owner = upper('$i') and temporary='N' and iot_type is null and partitioned <> 'YES' order by 1) a, v\$instance b
union
	select a.tablespace_name, b.instance_name
	from
	(select distinct tablespace_name, owner from dba_indexes
	where owner = upper('$i') and temporary='N' and partitioned <> 'YES' order by 1) a, v\$instance b
union
	select default_tablespace,c.instance_name 
	from dba_users, v\$instance c where username = upper('$i')
union
	select tablespace_name ,c.instance_name
	from dba_ts_quotas, v\$instance c where username = upper('$i')
union
        select distinct tablespace_name ,c.instance_name
        from dba_segments, v\$instance c where owner = upper('$i')
) a, dba_tablespaces b
where a.tablespace_name not in ($TablespacesNamesTarget) and a.tablespace_name=b.tablespace_name
;

spool off
__EOF


    if [[ $? -ne 0 ]]
    then
        LogError "ERROR: Creation of Tablespace script. Log file: $SqlTSFileLog"
	ErrorExit
    fi

    LogCons "Tablespace creation for user $i added to $SqlTSFile"

done
    LogCons "Log file: $SqlTSFileLog"
}
#---------------------------------------------------------
RunCreTSScript ()
#---------------------------------------------------------
{
LogCons "Running: $SqlTSFile"
sqlplus -s "/as sysdba" << __EOF >> $SqlTSFileLog 2>&1

-- WHENEVER SQLERROR EXIT SQL.SQLCODE
-- WHENEVER OSERROR EXIT 
@$SqlTSFile

__EOF

ErrorMsg=$(grep ORA- $SqlTSFileLog | grep -v ORA-01543 | grep -v ORA-03297 | grep -v ORA-03214 ) 

    if [[ ! -z  "$ErrorMsg" ]]
    then
        LogError "ERROR: Running script: $SqlTSFile Log: $SqlTSFileLog"
        exit 1
    fi

}

#---------------------------------------------------------
DropUsrTSLoop ()
#---------------------------------------------------------
{

>$SqlDropFile

LogCons "Drop tablespaces and Schemas"
LogCons "Log file: $SqlDropFile"
LogCons "Log file: $SqlDropFileLog"
for i in $(echo $UserParameter)
do
sqlplus -s "/as sysdba" << __EOF > $SqlDropFileLog 2>&1
SET serveroutput on;
-- SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
-- set echo off;
-- set heading off;
set echo on;
set heading on;
set timing off;

WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR EXIT;

spool $SqlDropFile append;

DECLARE
  open_count integer;
  vv_username VARCHAR(64) := UPPER('$i');

BEGIN
	DBMS_OUTPUT.put_line ('User Name: '||vv_username);
	FOR yy IN (select upper(username) as v_username from dba_users where username = vv_username)
LOOP
-- Remove Tablespace owner and the tablespace.
        BEGIN
        for xx IN (
                select b.TABLESPACE_NAME as V_TABLESPACE_NAME
                from
                (select
                TABLESPACE_NAME
                from (
                select a.tablespace_name, b.instance_name
                from
                (select distinct tablespace_name, owner from dba_tables
                where
                owner = yy.v_username and
                temporary='N' and iot_type is null and partitioned <> 'YES' order by 1) a, v\$instance b
                union
                select a.tablespace_name, b.instance_name
                from
                (select distinct tablespace_name, owner from dba_indexes
                where
                owner = yy.v_username and
                temporary='N' and partitioned <> 'YES' order by 1) a, v\$instance b
                union
                select default_tablespace,c.instance_name
                from dba_users, v\$instance c where username = yy.v_username
                union
                select tablespace_name ,c.instance_name
                from dba_ts_quotas, v\$instance c where username = yy.v_username
		union
                select distinct tablespace_name ,c.instance_name
                from dba_segments, v\$instance c where owner = yy.v_username
                ) a) b
                ----------------
                minus
                ----------------
                select b.TABLESPACE_NAME from
                (select
                TABLESPACE_NAME
                from (
                select a.tablespace_name, b.instance_name
                from
                (select distinct tablespace_name, owner from dba_tables
                where
                owner <> yy.v_username and
                temporary='N' and iot_type is null and partitioned <> 'YES' order by 1) a, v\$instance b
                union
                select a.tablespace_name, b.instance_name
                from
                (select distinct tablespace_name, owner from dba_indexes
                where
                owner <> yy.v_username and
                temporary='N' and partitioned <> 'YES' order by 1) a, v\$instance b
                union
                select default_tablespace,c.instance_name
                from dba_users, v\$instance c where username <> yy.v_username
                union
                select tablespace_name ,c.instance_name
                from dba_ts_quotas, v\$instance c where username <> yy.v_username
                union
                select distinct tablespace_name ,c.instance_name
                from dba_segments, v\$instance c where owner <> yy.v_username
                ) a) b
                )
           LOOP

		for zz in (select username from dba_users where username = yy.v_username)
		LOOP
		  DBMS_OUTPUT.put_line ('DROP USERNAME: '||yy.v_username);
		  -- prevent any further connections
		  BEGIN
		  EXECUTE IMMEDIATE 'alter user '||yy.v_username||' account lock';
		  END;
		  --kill all sessions
		  FOR session IN (SELECT sid, serial#
		                  FROM  v\$session
		                  WHERE username = yy.v_username)
		  LOOP
		    -- the most brutal way to kill a session
		    EXECUTE IMMEDIATE 'alter system disconnect session ''' || session.sid || ',' || session.serial# || ''' immediate';
		  END LOOP;
		  -- killing is done in the background, so we need to wait a bit
		  LOOP
		    SELECT COUNT(*)
		      INTO open_count
		      FROM  v\$session WHERE username = yy.v_username;
		    EXIT WHEN open_count = 0;
		    dbms_lock.sleep(0.5);
		  END LOOP;
		  -- finally, it is safe to issue the drop statement
		  EXECUTE IMMEDIATE 'drop user '||yy.v_username||' cascade';
		END LOOP;

                DBMS_OUTPUT.put_line ('DROP TABLESPACE: '||xx.V_TABLESPACE_NAME);
                EXECUTE IMMEDIATE 'DROP TABLESPACE '||xx.V_TABLESPACE_NAME||' INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
            END LOOP;


                for zz in (select username from dba_users where username = yy.v_username)
                LOOP
                  DBMS_OUTPUT.put_line ('DROP USERNAME: '||yy.v_username);
                  -- prevent any further connections
                  BEGIN
                  EXECUTE IMMEDIATE 'alter user '||yy.v_username||' account lock';
                  END;
                  --kill all sessions
                  FOR session IN (SELECT sid, serial#
                                  FROM  v\$session
                                  WHERE username = yy.v_username)
                  LOOP
                    -- the most brutal way to kill a session
                    EXECUTE IMMEDIATE 'alter system disconnect session ''' || session.sid || ',' || session.serial# || ''' immediate';
                  END LOOP;
                  -- killing is done in the background, so we need to wait a bit
                  LOOP
                    SELECT COUNT(*)
                      INTO open_count
                      FROM  v\$session WHERE username = yy.v_username;
                    EXIT WHEN open_count = 0;
                    dbms_lock.sleep(0.5);
                  END LOOP;
                  -- finally, it is safe to issue the drop statement
                  EXECUTE IMMEDIATE 'drop user '||yy.v_username||' cascade';
                END LOOP;
        END;
END LOOP;
END;
/

spool off

__EOF

    if [[ $? -ne 0 ]]
    then
        LogError "ERROR: Drop schema $i Log files: $SqlDropFileLog, $SqlDropFile"
        exit 1
    fi

done

}
#---------------------------------------------------------
CreDBLink ()
#---------------------------------------------------------
{
LogCons "Running: $create public database link $DbLinkName ....."
sqlplus -s "/as sysdba" << __EOF > $SqlCreDBLinkFileLog 2>&1
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT

create public database link "$DbLinkName" connect to $InIts identified by $MmDp using '$ConnectionString'; 

select * from v\$instance@$DbLinkName;
__EOF


    if [[ $? -ne 0 ]]
    then
        LogError "ERROR: Creation of DB Link. Log file: $SqlCreDBLinkFileLog"
        exit 1
    else
	LogCons "DB link $DbLinkName created. (logfile: $SqlCreDBLinkFileLog)"
    fi

}
#---------------------------------------------------------
DropDBLink ()
#---------------------------------------------------------
{
LogCons "Running: drop public database link "$DbLinkName""

sqlplus -s "/as sysdba" << __EOF > $SqlCreDBLinkFileLog 2>&1
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT

drop public database link "$DbLinkName";
__EOF

    if [[ $? -ne 0 ]]
    then
        LogError "ERROR: Drop of DB Link. Log file: $SqlCreDBLinkFileLog"
        exit 1
    else 
	LogCons "DB link $DbLinkName dropped. (logfile: $SqlCreDBLinkFileLog)"
    fi

}
#---------------------------------------------------------
ErrorExit ()
#---------------------------------------------------------
{
DropDBLink
UnRunMmDp
unset TNS_ADMIN
LogError "Exit with error"
exit 1
}
#---------------------------------------------------------
RemapFileName ()
#---------------------------------------------------------
{
LogCons "Runing remapping file name."
LogCons "Work/Error file: $SqlTSFile.work"
> $SqlTSFile.work

while read line
do
	RemapName=$(echo $line | grep "REMAP_FILE_NAME=" | sed 's/REMAP_FILE_NAME=//g')
	if [ ! -z $RemapName ]; then
		> $SqlTSFile.work
			RemapFrom=$(echo $RemapName | awk '{print $1}')
			RemapTo=$(echo $RemapName | awk '{print $2}')
			LogCons "Rename file: $RemapFrom -> $RemapTo"
		while read line01
		do
			echo $line01 | sed "s/${RemapFrom}/${RemapTo}/g" >> $SqlTSFile.work
		done < $SqlTSFile
		cp $SqlTSFile.work $SqlTSFile
	fi
done < $ParameterFile
}
#---------------------------------------------------------
CrePubSym ()
#---------------------------------------------------------
{
LogCons "Runing create public synonyms"
LogCons "Sql file: $SqlSymFile"
LogCons "Log file: $SqlLog"
sqlplus -s $CONNECT__STRING@$SourceDB << __EOF > $SqlLog 2>&1


SET serveroutput on;
SET feedback off;
set long 50000;
set longchunksize 20000;
set trimout on;
set trim on;
set linesize 1000;
set echo off;
set heading off;
set timing off;

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT

begin DBMS_METADATA.SET_TRANSFORM_PARAM (
DBMS_METADATA.SESSION_TRANSFORM,
'SQLTERMINATOR',
TRUE);
end;
/

spool $SqlSymFile

BEGIN
   FOR tt in
	(SELECT DBMS_METADATA.get_ddl ('SYNONYM', synonym_name, owner) as DDL_SYM, synonym_name 
         from dba_synonyms where TABLE_OWNER IN ($OraUserList) and owner = 'PUBLIC')
   LOOP
        DBMS_OUTPUT.put_line ('prompt Create symonym: '||tt.synonym_name);
        DBMS_OUTPUT.put_line (tt.DDL_SYM);
   END LOOP;
END;
/
spool off
__EOF

Error=$?

if [ $Error -ne 0 ]; then
        LogError "ERROR: Creation of synonyms script."
        DropDBLink
        exit 1
fi

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT
@$SqlSymFile

__EOF

Error=$?

if [ $Error -ne 0 ]; then
        LogError "ERROR: Runing of synonyms script."
        DropDBLink
        exit 1
fi


}

#---------------------------------------------------------
ImpUsers ()
#---------------------------------------------------------
{

LogCons "OraUserList: $OraUserList"
LogCons ""

 LongTableUserTmp=$(
sqlplus -s "/as sysdba" << __EOF
set echo off;
set feedback off;
set heading off;
set timing off;
select ''''||owner||'.'||a.table_name||'''' from dba_tab_columns@$DbLinkName a where a.data_type like 'LONG%' and a.owner in ($OraUserList) 
minus 
select ''''||owner||'.'||object_name||'''' from dba_recyclebin@$DbLinkName where owner in ($OraUserList);
__EOF
)

LongTableUser=$(echo $LongTableUserTmp | sed 's/ /,/g')

 LongTable=$(
sqlplus -s "/as sysdba" << __EOF
set timing off;
set echo off;
set feedback off;
set heading off;
select owner, a.table_name from dba_tab_columns@$DbLinkName a where a.data_type like 'LONG%' and a.owner in ($OraUserList)
minus
select owner, object_name from dba_recyclebin@$DbLinkName where owner in ($OraUserList);
__EOF
)
LogCons "Tables contaning LONGS are NOT imported !!!!!"
LogCons "LongTable: $LongTable"
LogCons "LongTableUser: $LongTableUser"

LogCons "Starting Import......"
LogCons "Parameter file: $ImpParaFile"
SchemaListImp=$(echo $UserParameter)


DoSql $OFA_SQL/directory.sql > $SqlLog
SqlLog=$(grep "ORA-" $SqlLog)
if [ ! -z "$SqlLog" ]; then
	LogError "ERROR: Create 'CREATE or REPLACE DIRECTORY DATA_PUMP_DIR AS...'"
        LogCons "Log file: $SqlLog"
	exit 1
fi 

# Start NETWORK IMPORT.

# Create the ParFile

echo "# Start of IMP_PARAMETER parameter from $ParameterFile"  > $ImpParaFile
while read line
do
    echo $line | grep "IMP_PARAMETER=" | sed 's/IMP_PARAMETER=//g' >> $ImpParaFile
done < $ParameterFile
echo "# End of IMP_PARAMETER parameter from $ParameterFile"  >> $ImpParaFile

echo "DIRECTORY=DATA_PUMP_DIR" >> $ImpParaFile
echo "LOGFILE=impdp_$SourceDB.$TargetDB.$$.$PPID.log" >> $ImpParaFile
echo "PARALLEL=$ImpParallel" >> $ImpParaFile
echo "NETWORK_LINK=$DbLinkName" >> $ImpParaFile
echo "CLUSTER=NO" >> $ImpParaFile

if [ "$ActionPara" != "TABLES" ]; then
	echo "SCHEMAS=$SchemaListImp" >> $ImpParaFile
fi


if [[ $OracleVersionTarget -lt 12 ]]
then
# Oracle version less than 12
LogCons "Oracle version less than 12"

else
# Oracle Version 12 or higher 
LogCons "Oracle version higher than 12"

# echo "EXCLUDE=TABLE:\"IN (select table_name from dba_recyclebin@$DbLinkName where owner in ($OraUserList) and TYPE='TABLE'\"" >> $ImpParaFile
# echo "EXCLUDE=TABLE:\"IN (select table_name from dba_recyclebin where owner in ($OraUserList) and TYPE='TABLE'\"" >> $ImpParaFile
# echo "EXCLUDE=TABLE:\"NOT LIKE 'BIN\$%'\"" >> $ImpParaFile
# echo "EXCLUDE=TABLE:\"IN ('FISH.TANK.T_FISHTANK_ODS_CLIENTS_4RETRO_')\"" >> $ImpParaFile
# echo "EXCLUDE=TABLE:\"IN ($LongTableUser)\"" >> $ImpParaFile

# If STATISTICS not excluded the IMP dump crash !!!!!
echo "EXCLUDE=STATISTICS" >> $ImpParaFile
echo "LOGTIME=ALL" >> $ImpParaFile
# If DISABLE_ARCHIVE_LOGGING are used IMP dump crash !!!!!
# echo "TRANSFORM=DISABLE_ARCHIVE_LOGGING:Y" >> $ImpParaFile 

fi

LogCons "Start import using impdp with parameter file:$ImpParaFile"
LogCons "Paramaters:"
cat $ImpParaFile

impdp \'/ as sysdba\'  parfile=$ImpParaFile
Error=$?

if [ $Error -ne 0 ]; then 
	LogError "ERROR: Import Logfile:impdp_$SourceDB.$TargetDB.$$.$PPID.log"
	DropDBLink
	exit 1
fi 
}
#---------------------------------------------------------
# Main
#---------------------------------------------------------
if [ ! -r $ParameterFile ]; then
	LogError "Parameter file: $ParameterFile are NOT readable"
	exit 1
fi

LogCons "Getting connect string to Source database.."

LogCons "Tnsping .............."
tnsping $SourceDB > /dev/null 2>&1
    if [[ $? -ne 0 ]]
    then
        LogCons "Warning: Connection to $SourceDB via tnsping failed..."
	LogCons "Trying via Ldap now"
	LogCons "Connecting to LDAP"
	Ldaping $SourceDB > /dev/null 2>&1
    	if [[ $? -ne 0 ]]
    	then
        	LogCons "ERROR: Connection to $SourceDB via LDAP"
		exit 1
    	else
        	ConnectionString=$(Ldaping $SourceDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
               	if [[ ! -z "$ConnectionString" ]]
               	then
                       	export TNS_ADMIN=/tmp
               	else
                       	LogError "ERROR: Connection string to $SourceDB"
			unset TNS_ADMIN
                       	exit 1
		fi
	fi
    else
	ConnectionString=$(tnsping $SourceDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
    fi




# LogCons "Connecting to LDAP"
# $SourceDB > /dev/null 2>&1
#if [[ $? -ne 0 ]]
#then
#LogCons "ERROR: Connection to $SourceDB via LDAP"
#else
#ConnectionString=$(Ldaping $SourceDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
#if [[ -z "$ConnectionString" ]]
#then
#LogCons "ERROR: Getting connect string via LDAP"
#LogCons "Connection via TNS"
#ConnectionString=$(tnsping $SourceDB | grep "Attempting to contact" | sed 's/Attempting to contact //g')
#if [[ ! -z "$ConnectionString" ]]
#then
#unset TNS_ADMIN
#else
#LogError "ERROR: Connection string to $SourceDB"
#exit 1
#fi
#else
#export TNS_ADMIN=/tmp
#fi
#fi


OraEnv  $TargetDB >/dev/null || Usage "$OFA_ERR Failed OraEnv"

CONNECT__STRING=$InIts/$MmDp

OracleVersionTarget=$(OraDbGetVersion | awk -F "." '{print $1}')

LogCons "Connect String: $ConnectionString"
LogCons "Source DB: $SourceDB"
LogCons "Target DB: $TargetDB"
LogCons "Parameter file: $ParameterFile"
## LogCons "InIts: $InIts"
## LogCons "MmDp: $MmDp"
LogCons "Action parameter: $ActionPara"
LogCons "Oracle Version (Target): $OracleVersionTarget"
LogCons "Parameter SCHEMA:$UserParameter"
LogCons "Parameter CONVERT_FS_TARGET: $ConvertFS_Target" 
LogCons "Parameter CONVERT_FS_SOURCE: $ConvertFS_Source"
LogCons "Main logfile:"
LogCons ""
	
CreDBLink

if [ "$ActionPara" == "DROP" ]; then
 	DropUsrTSLoop
fi

CreTSScript
RemapFileName
if [[ "$ActionPara" == "TS_SCRIPT" ]]
then
	LogCons "Create TS script: $SqlTSFile"
	exit 0
fi
CrePubSym
RunCreTSScript
ImpUsers
DropDBLink
UnRunMmDp
unset TNS_ADMIN
