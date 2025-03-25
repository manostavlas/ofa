#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES




DatabaseName=$1

#---------------------------------------------
usage ()
#---------------------------------------------
{
echo ""
cat << __EOF
#
##
## Usage: ReNamePDB.sh [SID] 
##
## Renaming the PDB
##
#
__EOF
exit 
}

#---------------------------------------------

  CheckVar DatabaseName         \
  || usage

SqlLogBacDropPDB=$OFA_LOG/tmp/ReNamePDB.sh.SqlLogBacDropPDB.$$.$PPID.log
SqlLogPlugNewXml=$OFA_LOG/tmp/ReNamePDB.sh.SqlLogPlugNewXml.$$.$PPID.log
SqlLogAddTemp=$OFA_LOG/tmp/ReNamePDB.sh.AddTemp$$.$PPID.log

OraEnv $DatabaseName || BailOut "Failed OraEnv \"$DatabaseName\""

OraDbStatus > /dev/null || BailOut "Database $ORACLE_SID DOWN  OraEnv \"$DatabaseName\""


OldPdbSid=$(DoSqlQ "select name from v\$pdbs where name like '%_PDB%';")
CdbSid=$(DoSqlQ "select name from v\$database;")
NewPdbSid=$(DoSqlQ "select name||'_PDB' from v\$database;")
XmlFileName="/backup/${NewPdbSid}/datapump/${NewPdbSid}.xml"

LogCons "Old PBD_SID: $OldPdbSid"
LogCons "New PDB_SID: $NewPdbSid"
LogCons "CDB_SID: $CdbSid"
LogCons "XML file: $XmlFileName"



#------------------------------------------------
BacDropPDB ()
#------------------------------------------------
{

LogCons "Start Unplug and Drop"

rm -f ${XmlFileName}

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLogBacDropPDB 2>&1
set serveroutput on;

DECLARE
	OLD_PDB_SID	VARCHAR2(128);
	NEW_PDB_SID	VARCHAR2(128);
	CDB_SID		VARCHAR2(512);
	sql_stm		VARCHAR2(512);

BEGIN

select name into OLD_PDB_SID from v\$pdbs where name like '%_PDB%';
select name into CDB_SID from v\$database;
select name||'_PDB' into NEW_PDB_SID from v\$database;

DBMS_OUTPUT.put_line(OLD_PDB_SID);
DBMS_OUTPUT.put_line(NEW_PDB_SID);
DBMS_OUTPUT.put_line(CDB_SID);


-- Close PDB
sql_stm := 'ALTER PLUGGABLE DATABASE '|| OLD_PDB_SID ||' close immediate';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

-- OPEN READ ONLY
sql_stm := 'ALTER PLUGGABLE DATABASE '|| OLD_PDB_SID ||' OPEN READ ONLY';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

-- Close PDB
sql_stm := 'ALTER PLUGGABLE DATABASE '|| OLD_PDB_SID ||' close immediate';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

-- Unplug PDB
sql_stm := 'ALTER PLUGGABLE DATABASE '|| OLD_PDB_SID ||' unplug into ''/backup/'||NEW_PDB_SID||'/datapump/'||NEW_PDB_SID||'.xml''';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

-- Drop PDB
sql_stm := 'DROP PLUGGABLE DATABASE '|| OLD_PDB_SID;

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;


END;
/
___EOF

ErrorMess=$(grep ORA- $SqlLogBacDropPDB)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLogBacDropPDB"
        exit 1
else
        LogCons "Log file: $SqlLogBacDropPDB"
fi
}
#------------------------------------------------
SetNewName ()
#------------------------------------------------
{
# set -vx
	LogCons "Change XML file: $XmlFileName"
	LogCons "${OldPdbSid} -> ${NewPdbSid}"
scp ${XmlFileName} ${XmlFileName}.orig
sed -i s/$OldPdbSid/$NewPdbSid/g ${XmlFileName}
}
#------------------------------------------------
PlugNewXml ()
#------------------------------------------------
{
# set -xv
LogCons "Start Plug new XML"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLogPlugNewXml 2>&1
set serveroutput on;
DECLARE
        OLD_PDB_SID     VARCHAR2(128) := '$OldPdbSid';
        NEW_PDB_SID     VARCHAR2(128) := '$NewPdbSid';
        CDB_SID         VARCHAR2(512) := '$CdbSid';
        sql_stm         VARCHAR2(512);

BEGIN

-- select name into OLD_PDB_SID from v\$pdbs where name like '%_PDB%';
-- select name into CDB_SID from v\$database;
-- select name||'_PDB' into NEW_PDB_SID from v\$database;

DBMS_OUTPUT.put_line(OLD_PDB_SID);
DBMS_OUTPUT.put_line(NEW_PDB_SID);
DBMS_OUTPUT.put_line(CDB_SID);


-- Close PDB
-- sql_stm := 'create pluggable database '|| NEW_PDB_SID ||' using ''/backup/'||NEW_PDB_SID||'/datapump/'||NEW_PDB_SID||'.xml'' NOCOPY PATH_PREFIX = ''/backup''';
sql_stm := 'create pluggable database '|| NEW_PDB_SID ||' using ''/backup/'||NEW_PDB_SID||'/datapump/'||NEW_PDB_SID||'.xml'' NOCOPY PATH_PREFIX = none';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

-- OPEN New PDB
sql_stm := 'ALTER PLUGGABLE DATABASE '|| NEW_PDB_SID ||' OPEN';

dbms_output.put_line('sql_stm: '||sql_stm);

EXECUTE IMMEDIATE sql_stm;

end;
/
exit
___EOF

ErrorMess=$(grep ORA- $SqlLogPlugNewXml)
if [[ ! -z "$ErrorMess" ]]
then
        LogError "Log file: $SqlLogPlugNewXml"
        exit 1
else
        LogCons "Log file: $SqlLogPlugNewXml"
fi

}
#------------------------------------------------
DbStatus ()
#------------------------------------------------
{
PdbStatus=$(DoSqlQ "select name, open_mode from v\$pdbs where name = '$NewPdbSid';")
LogCons "New PDB status: $PdbStatus"
}
#------------------------------------------------
AddTemp ()
#------------------------------------------------
{
LogCons "Add temp TS's Log file: $SqlLogAddTemp"

sqlplus -s "/as sysdba"  << ___EOF  >> $SqlLogAddTemp 2>&1

ALTER TABLESPACE TEMP ADD TEMPFILE '/DB/$CdbSid/temp01.dbf'
     SIZE 1024M REUSE AUTOEXTEND ON NEXT 104857600  MAXSIZE 10240M;

ALTER SESSION SET CONTAINER = PDB\$SEED;

ALTER TABLESPACE TEMP ADD TEMPFILE '/DB/${CdbSid}/pdbseed/temp01.dbf'
     SIZE 1024M REUSE AUTOEXTEND ON NEXT 104857600  MAXSIZE 10240M;

ALTER SESSION SET CONTAINER = ${NewPdbSid};

ALTER TABLESPACE TEMP ADD TEMPFILE '/DB/${NewPdbSid}/temp01.dbf'
     SIZE 1024M REUSE AUTOEXTEND ON NEXT 104857600  MAXSIZE 10240M;

ALTER TABLESPACE TEMPDB1 ADD TEMPFILE '/DB/${NewPdbSid}/tempdf1.dat'
     SIZE 641728512  REUSE AUTOEXTEND ON NEXT 8192  MAXSIZE 32767M;

ALTER SESSION SET CONTAINER = CDB\$ROOT;

___EOF
}
#------------------------------------------------
# Main
#------------------------------------------------
BacDropPDB
SetNewName
PlugNewXml
AddTemp
DbStatus
