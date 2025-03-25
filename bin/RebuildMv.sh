#!/bin/ksh
  #
  # load ofa
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

YesNo $(basename $0) || exit 1 && export RunOneTime=YES


#---------------------------------------------
usage ()
#---------------------------------------------
{
echo ""
cat << __EOF
#
##
## Usage: RebuildMv.sh [FUNCTION] [see function]
##
##   Paremeter:
##
##   DbName:
##        Name of the database
##
##   Function:            Parameters:
##
##   Schema		  [DB_NAME]
##			  [SCHEMA_NAME] Schema name of the MV's to rebuild.
##		          <CREATE> Set to Only the script(s) will be created.
##			  	e.g RebuildMv.sh Schema DBATST02 ODSCRO Only
##
##   Database		  [DB_NAME]
##			  [NAME_OF_SOURCE_DB] Name of the source database of which MV's to rebuild.
##		          <CREATE> Set to Create only the script(s) will be created.
##
##   Mview		  [DB_NAME]
##			  [OWNER] Owner of the MV(s)
##			  [MV_NAME] can be a comma separated list.
##		          <CREATE> Set to Create only the script(s) will be created.
##
##
#
__EOF
exit
}

FuncToDo=$1
DbName=$2
TimeStamp=$(date +"%Y%m%d_%H%M%S")

    CheckVar                       \
        DbName                        \
        FuncToDo                   \
     && LogIt "Variables complete" \
     || usage

MainErorLog=$OFA_LOG/tmp/RebuildMvMainError.$$.$PPID.$TimeStamp.log

OFA_MAIL_RCP_BAD="no mail"
OFA_IGN_PAT="$OFA_IGN_PAT|ERROR"


#---------------------------------------------
RebuildDatabaseName ()
#---------------------------------------------
{
MvList=$OFA_LOG/tmp/RebuildMv.MvList.tmp.$DatabaseName.$$.$PPID.$TimeStamp.log
MvLink=$OFA_LOG/tmp/RebuildMv.MvLink.tmp.$DatabaseName.$$.$PPID.$TimeStamp.log

LogCons "Rebuild MV's from database: $DatabaseName"
DatabaseNameTest=$(DoSqlQ "select distinct host from dba_db_links where host = '$DatabaseName';")
if [[ -z $DatabaseNameTest ]]
then
        LogError "Error No DB links connection to this database: $DatabaseName"
	exit 1
fi

LogCons "Getting MV list for DB: $DatabaseName"
LogCons "LogFile: $MvList"

sqlplus -s "/as sysdba" << __EOF >> $MvList 2>&1
@$OFA_SQL/ofa/$LOGIN_DIR/db_quiet/login.sql
select
-- host,
-- trim(TRAILING '"' from substr(a.master_link, instr(a.master_link,'"')+1))  as link_name,
a.OWNER,
a.MVIEW_NAME
 from dba_mviews a, dba_db_links b where 
 b.host = '$DatabaseName'
 and b.db_link=trim(TRAILING '"' from substr(a.master_link, instr(a.master_link,'"')+1)) order by 1,2;
__EOF


ErrorMsg=$(grep ORA- $MvList)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error Getting MV list Logfile: $MvList"
        cat $MvList >> $MainErorLog
        exit 1
fi

LogCons "Getting LINK name(s)"
LogCons "Logfile: $MvLink"
sqlplus -s "/as sysdba" << __EOF >> $MvLink 2>&1
@$OFA_SQL/ofa/$LOGIN_DIR/db_quiet/login.sql
select
distinct
-- host,
trim(TRAILING '"' from substr(a.master_link, instr(a.master_link,'"')+1))  as link_name
-- a.OWNER,
-- a.MVIEW_NAME
 from dba_mviews a, dba_db_links b where 
 b.host = '$DatabaseName'
 and b.db_link=trim(TRAILING '"' from substr(a.master_link, instr(a.master_link,'"')+1)) order by 1;
__EOF


cat $MvLink | while read line
do
LinkName=$(echo $line | awk '{print $1}')
	LogCons "Test DB Link: $LinkName"
	TestResult=$(DoSqlQ "select count(*) from user_tables@$LinkName;" | grep ORA-)
	if [ -z "$TestResult" ] ; then
        	LogCons "Link ok!"
	else
        	LogCons "Error: $TestResult"
        	exit 1
	fi
done



cat $MvList | while read line
do
	# echo $line
	SchemaName=$(echo $line | awk '{print $1}')
	MvName=$(echo $line | awk '{print $2}')
	LogCons "SchemaName: $SchemaName, MvName: $MvName"
	MainRefreshMv
done

}
#---------------------------------------------
RebuildSchemaName ()
#---------------------------------------------
{
LogCons "Rebuild MV's for schema: $SchemaName"
UserName=$(DoSqlQ "select username from dba_users where username = upper('$SchemaName');")

if [[ -z $UserName ]]
then
	LogError "Schema: $SchemaName don't exist" 
fi

MvNameList=$(DoSqlQ "select mview_name from dba_mviews where owner = '$SchemaName' and master_link is not null order by 1;")

LinkName=$(DoSqlQ "select distinct trim(TRAILING '\"' from substr(master_link, instr(master_link,'\"')+1)) as link_name from dba_mviews where owner = '$SchemaName';")


LogCons "Test DB Link: $LinkName"
TestResult=$(DoSqlQ "select count(*) from user_tables@$LinkName;" | grep ORA-)
if [ -z "$TestResult" ] ; then
	LogCons "Link ok!"
else
	LogCons "Error: $TestResult"
	exit 1
fi



# echo "MvNameList: $MvNameList"

if [[ -z $MvNameList ]]
then
	LogError "The schema don't have any remote MV(s)"
	exit 1
fi


for i in $MvNameList
do
	MvName=$i
	LogCons "SchemaName: $SchemaName, MvName: $MvName" 
	MainRefreshMv
done
}
#---------------------------------------------
MainRefreshMv ()
#---------------------------------------------
{
# SchemaName=ODSCRO
# MvName=BLOCBQCPN

# Get MV Info: Owner,table_name,link,tnsname
TmpLogFileMvLog=$OFA_LOG/tmp/RebuildMv.Log.tmp.$MvName.$$.$PPID.$TimeStamp.log
SqlLogFileMvLog=$OFA_LOG/tmp/RebuildMv.Log.sql.$MvName.$$.$PPID.$TimeStamp.log

LogCons "Getting MV log info."
LogCons "logfile: $TmpLogFileMvLog"

sqlplus -s "/as sysdba" << __EOF >> $TmpLogFileMvLog 2>&1
@$OFA_SQL/ofa/$LOGIN_DIR/db_quiet/login.sql

SET serveroutput on;
SET feedback off;
set long 500000;
set longchunksize 200000;
set trimout on;
set trim on;
set linesize 1000;

UNDEF ENTER_MVIEW_OWNER
UNDEF ENTER_MVIEW_NAME

DECLARE
   v_task_name     VARCHAR2 (100);
   v_mview_owner   VARCHAR2 (100)   := UPPER ('$SchemaName');
   v_mview_name    VARCHAR2 (100)   := UPPER ('$MvName');
   v_sql           VARCHAR2 (4000);
   v_sql_drop      VARCHAR2 (4000);
   v_sql_index     VARCHAR2 (4000);
   v_sql_add_ref   VARCHAR2 (4000);
   h1              NUMBER;
   th1             NUMBER;
   ddltext         CLOB;

BEGIN
-- Create MVIEW

   FOR kk IN (SELECT replace(DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW',u.mview_name,u.owner),'START WITH sysdate+0','START WITH to_date(''01014000_000000'',''DDMMYYYY_HH24MISS'')') as SQL_MVIEW
   FROM dba_mviews u
   where owner = v_mview_owner AND mview_name = v_mview_name)
   LOOP
     DBMS_OUTPUT.put_line ('--Create mview SQL: '||chr(10)||kk.SQL_MVIEW||';');
   END LOOP;
END;
/
__EOF


ErrorMsg=$(grep ORA- $TmpLogFileMvLog)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error MV info. Logfile:$TmpLogFileMvLog"
        cat $TmpLogFileMvLog >> $MainErorLog
        return 0
fi

LinkName=$(grep "\" FROM \"" $TmpLogFileMvLog | awk -F "FROM" '{print $2}'| sed 's/"//g' | awk -F "@" '{print $2}' | awk '{print $1}')
TableName=$(grep "\" FROM \"" $TmpLogFileMvLog | awk -F "FROM" '{print $2}' | awk -F "@" '{print $1}'| sed 's/"//g' | awk -F "." '{print $2}')
OwnerName=$(grep "\" FROM \"" $TmpLogFileMvLog | awk -F "FROM" '{print $2}' | awk -F "@" '{print $1}' | sed 's/"//g' | awk -F "." '{print $1}'| sed 's/ //g')
RemoteDbTns=$(DoSqlQ "select host from dba_db_links where db_link = upper('$LinkName');")


# Create MV log script

LogCons "Create MV log script for Owner: $OwnerName Table: $TableName Link: $LinkName Tnsname: $RemoteDbTns"

TmpLogFileMvLogScr=$OFA_LOG/tmp/RebuildMv.Scr.tmp.$MvName.$$.$PPID.$TimeStamp.log
SqlLogFileMvLogScr=$OFA_LOG/tmp/RebuildMv.Scr.sql.$MvName.$$.$PPID.$TimeStamp.sql

LogCons "Script: $SqlLogFileMvLogScr"

sqlplus -s system/$MmDp@$RemoteDbTns << __EOF >> $SqlLogFileMvLogScr 2>&1
@$OFA_SQL/ofa/$LOGIN_DIR/db_quiet/login.sql
SET serveroutput on;
SET feedback off;
set long 500000;
set longchunksize 200000;
set trimout on;
set trim on;
set linesize 1000;

DECLARE
   v_mview_owner   VARCHAR2 (100)   := UPPER ('$OwnerName');
   v_mview_name    VARCHAR2 (100)   := UPPER ('$TableName');
BEGIN
-- Create MVIEW LOG
   FOR tt IN (
   select dbms_metadata.get_ddl('MATERIALIZED_VIEW_LOG',LOG_TABLE,LOG_OWNER) as SQL_MVIEW_LOG,
   MASTER as MASTER_TABLE,
   LOG_OWNER as OWNER
   FROM DBA_MVIEW_LOGS 
   where log_owner= v_mview_owner and master = v_mview_name 
   order by LOG_OWNER, LOG_TABLE)
   LOOP
     DBMS_OUTPUT.put_line ('--Drop MVIEW LOG SQL:'||chr(10)||'DROP MATERIALIZED VIEW LOG ON '||tt.owner||'.'||tt.MASTER_TABLE||';'||chr(10));
     DBMS_OUTPUT.put_line ('--Create MVIEW LOG SQL:'||chr(10)||tt.SQL_MVIEW_LOG||';'||chr(10));
   END LOOP;
--     DBMS_OUTPUT.put_line ('--v_mview_owner:'||v_mview_owner);
--     DBMS_OUTPUT.put_line ('--v_mview_name:'||v_mview_name);
END;
/

DECLARE
   v_mview_owner   VARCHAR2 (100)   := UPPER ('$OwnerName');
   v_mview_name    VARCHAR2 (100)   := UPPER ('$TableName');
BEGIN
-- Create Grant (TAB)
    FOR bb IN (
    select 'grant '||privilege||
                ' on '||owner||
                '.'||table_name||
                ' to '||grantee||
                ' '||replace(replace(GRANTABLE,'YES','WITH GRANT OPTION'),'NO','') as SQL_GRANT_TAB
                from DBA_TAB_PRIVS a, DBA_MVIEW_LOGS b where log_owner= v_mview_owner and master = v_mview_name and a.table_name = b.log_table order by LOG_OWNER, LOG_TABLE)
    LOOP
      DBMS_OUTPUT.put_line ('--Create GRANT SQL (TAB): '||chr(10)||bb.SQL_GRANT_TAB||';'||chr(10));
    END LOOP;
END;
/
__EOF

# if [[ $MvName == SDSETT ]]
# then
# 	echo "ORA-" >>$SqlLogFileMvLogScr
# fi

ErrorMsg=$(grep ORA- $SqlLogFileMvLogScr)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error create MV log script. Logfile:$SqlLogFileMvLogScr"
	cat $SqlLogFileMvLogScr >> $MainErorLog
        return 0
fi


# Create rebuild script MV

LogCons "Create rebuild MV script. MV: $SchemaName.$MvName"
 
TmpLogFileMv=$OFA_LOG/tmp/RebuildMv.tmp.$MvName.$$.$PPID.$TimeStamp.log
SqlLogFileMv=$OFA_LOG/tmp/RebuildMv.sql.$MvName.$$.$PPID.$TimeStamp.sql

# LogCons "Refresh MV: $SchemaName.$MvName"
LogCons "Logfile: $SqlLogFileMv"
sqlplus -s "/as sysdba" << __EOF >> $SqlLogFileMv 2>&1
@$OFA_SQL/ofa/$LOGIN_DIR/db_quiet/login.sql

SET serveroutput on;
SET feedback off;
set long 500000;
set longchunksize 200000;
set trimout on;
set trim on;
set linesize 1000;

UNDEF ENTER_MVIEW_OWNER
UNDEF ENTER_MVIEW_NAME

DECLARE
   v_task_name     VARCHAR2 (100);
   v_mview_owner   VARCHAR2 (100)   := UPPER ('$SchemaName');
   v_mview_name    VARCHAR2 (100)   := UPPER ('$MvName');
   v_sql           VARCHAR2 (4000);
   v_sql_drop      VARCHAR2 (4000);
   v_sql_index     VARCHAR2 (4000);
   v_sql_add_ref   VARCHAR2 (4000);   
   h1              NUMBER;
   th1             NUMBER;
   ddltext         CLOB;



BEGIN
-- Drop MVIEW
   SELECT 'DROP MATERIALIZED VIEW '||owner||'.'||mview_name||';'
   INTO v_sql_drop
   FROM dba_mviews
   WHERE owner = v_mview_owner AND mview_name = v_mview_name;
      
   DBMS_OUTPUT.put_line ('--Drop MVIEW SQL: '||chr(10)|| v_sql_drop||chr(10));

-- Create MVIEW

   FOR kk IN (SELECT replace(DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW',u.mview_name,u.owner),'START WITH sysdate+0','START WITH to_date(''01014000_000000'',''DDMMYYYY_HH24MISS'')') as SQL_MVIEW
   FROM dba_mviews u
   where owner = v_mview_owner AND mview_name = v_mview_name)
   LOOP
     DBMS_OUTPUT.put_line ('--Create mview SQL: '||chr(10)||kk.SQL_MVIEW||';');
   END LOOP;

-- Create INDEX
   FOR tt IN (SELECT DBMS_METADATA.GET_DDL('INDEX',u.index_name,u.owner) as SQL_INDEX
   FROM dba_INDEXES u 
   where owner = v_mview_owner AND table_name = v_mview_name and index_type <> 'LOB')
   LOOP
     DBMS_OUTPUT.put_line ('--Create index SQL: '||chr(10)||tt.SQL_INDEX||';');
   END LOOP; 
   
-- Create SYNONYM
		FOR aa IN (
		select 'CREATE OR REPLACE SYNONYM '||owner||
		'.'||SYNONYM_NAME||' FOR '||TABLE_OWNER||
		'.'||TABLE_NAME as SQL_SYNONYMS
		from DBA_SYNONYMS where table_owner = v_mview_owner and table_name = v_mview_name)  
		LOOP
		  DBMS_OUTPUT.put_line ('--Create SYNOMYM SQL: '||chr(10)||aa.SQL_SYNONYMS||';'||chr(10));
    END LOOP; 
-- Create COMMENT
/*
   FOR jj IN (SELECT dbms_metadata.get_dependent_ddl('COMMENT',u.mview_name,u.owner) as SQL_COMMENT
   FROM dba_mviews u
   where owner = yy.v_mview_owner AND mview_name = yy.v_mview_name)
   LOOP
     DBMS_OUTPUT.put_line ('--Create COMMENT SQL: '||chr(10)||jj.SQL_COMMENT||';');
   END LOOP;
*/

   h1 := dbms_metadata.open('COMMENT');
   DBMS_METADATA.SET_FILTER(h1,'BASE_OBJECT_SCHEMA',v_mview_owner);
   DBMS_METADATA.SET_FILTER(h1,'BASE_OBJECT_NAME',v_mview_name);
   th1 := dbms_metadata.add_transform(h1, 'DDL');
   dbms_metadata.set_transform_param(th1,'PRETTY', false);
   dbms_metadata.set_transform_param(th1,'SQLTERMINATOR', true);

   LOOP
      ddltext := DBMS_METADATA.FETCH_CLOB(h1);
      EXIT WHEN ddltext IS NULL;
      DBMS_OUTPUT.PUT_LINE('-- Create COMMENT SQL: '||ddltext);
   END LOOP;
   dbms_metadata.close(h1);

    
-- Create Grant (TAB)    
    FOR bb IN (
    select 'grant '||privilege||
		' on '||owner||
		'.'||table_name||
		' to '||grantee||
		' '||replace(replace(GRANTABLE,'YES','WITH GRANT OPTION'),'NO','') as SQL_GRANT_TAB
		from DBA_TAB_PRIVS where owner = v_mview_owner and table_name = v_mview_name)
    LOOP
      DBMS_OUTPUT.put_line ('--Create GRANT SQL (TAB): '||chr(10)||bb.SQL_GRANT_TAB||';'||chr(10));
    END LOOP;  
           
-- Create Grant (COL)
    FOR cc IN (
    select 'grant '||privilege||
		' on '||owner||
		'.'||table_name||
		' to '||grantee||
		' '||replace(replace(GRANTABLE,'YES','WITH GRANT OPTION'),'NO','') as SQL_GRANT_COL
		from DBA_COL_PRIVS where owner = v_mview_owner and table_name = v_mview_name)
    LOOP
      DBMS_OUTPUT.put_line ('--Create GRANT SQL (TAB): '||chr(10)||cc.SQL_GRANT_COL||';'||chr(10));
    END LOOP;           

-- Add to Refresh Group
select 'exec DBMS_REFRESH.ADD (name => '''||ROWNER||
'.'||RNAME||''',list => '''||owner||'.'||NAME||''', lax => TRUE);'
INTO v_sql_add_ref
from all_refresh_children
where owner = v_mview_owner and name = v_mview_name;

DBMS_OUTPUT.put_line ('--Add to Refresh group SQL: '||chr(10)|| v_sql_add_ref||chr(10)||'commit;'||chr(10));

/*
-- Exception
    exception
      when no_data_found then
        null;
      when others then
        raise;

-- Exception
exception
  when others then
    raise_application_error(-20000, sqlerrm);
*/

END;
/


__EOF


# echo "ORA-" >> $SqlLogFileMv

ErrorMsg=$(grep ORA- $SqlLogFileMv)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error create MV script. Logfile:$SqlLogFileMv"
        cat $SqlLogFileMv >> $MainErorLog
        return 0
fi

if [[ $Create == Only ]]
then
	LogCons "Only creation of the script(s)"
else
	# Run rebuild MV log

	LogCons "Running recreate MV log, Script: $SqlLogFileMvLogScr"
	LogCons "Logfile:$TmpLogFileMvLogScr"
	sqlplus -s system/$MmDp@$RemoteDbTns << __EOF > $TmpLogFileMvLogScr 2>&1
	prompt Running: $SqlLogFileMvLogScr
 	@$SqlLogFileMvLogScr 
__EOF

	ErrorMsg=$(grep ORA- $TmpLogFileMvLogScr)
	if [[ ! -z "$ErrorMsg" ]]
	then
	       	 LogError "Error running MV script. Logfile:$TmpLogFileMvLogScr"
	        cat $SqlLogFileMv >> $MainErorLog
	        return 0
	fi

	# Run rebuild MV Script

	LogCons "Running MV rebuild script: $SqlLogFileMv"
	LogCons "Logfile: $TmpLogFileMv"
	sqlplus -s "/as sysdba" << __EOF >> $TmpLogFileMv 2>&1
	prompt Running: $SqlLogFileMv
 	@$SqlLogFileMv
__EOF

	ErrorMsg=$(grep ORA- $TmpLogFileMv | grep -v RA-01408 | grep -v RA-00955)
	if [[ ! -z "$ErrorMsg" ]]
	then
	        LogError "Error running MV script. Logfile:$TmpLogFileMv"
	        cat $SqlLogFileMv >> $MainErorLog
	        return 0
	fi
fi 
}
#---------------------------------------------
Mview ()
#---------------------------------------------
{
LogCons "Rebuild MV schema: $SchemaName MV: $MvNameList "
MvNameList=$(echo $MvNameList | sed 's/,/ /g')
LogCons "Check if MV(s) exist..."
LogCons "MV(s): $MvNameList"
for i in $MvNameList
do 
MvTestExist=$(DoSqlQ "select mview_name from dba_mviews where mview_name = '$i' and owner = '$SchemaName';")
if [[ -z $MvTestExist ]]
then
	LogError "Error MV: $SchemaName.$i don't exist"
	exit 1
fi
done

for i in $MvNameList
do
MvName=$i
echo "SchemaName: $SchemaName, MvName: $MvName"
MainRefreshMv
done


}
#---------------------------------------------
# MAIN
#---------------------------------------------

OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
RunMmDp

if [[ "$FuncToDo" == "Schema" ]]
then
	SchemaName=$3 Create=$4
    CheckVar                       \
	SchemaName		   \
     && LogIt "Variables complete" \
     || LogCons "Parameter missing"
	LogCons "Function: Rebuild MV's for schema: $SchemaName"
     RebuildSchemaName
elif [[ "$FuncToDo" == "Database" ]]
then
        DatabaseName=$3 Create=$4
    CheckVar                       \
        DatabaseName        \
     && LogIt "Variables complete" \
     || LogCons "Parameter missing"
        LogCons "Function: Rebuild MV's from database: $DatabaseName"
     RebuildDatabaseName     
elif [[ "$FuncToDo" == "Mview" ]]
then
        SchemaName=$3 MvNameList=$4 Create=$5
    CheckVar                       \
	SchemaName		   \
        MvNameList                 \
     && LogIt "Variables complete" \
     || LogCons "Parameter missing"
        # LogCons "Function: Rebuild MV's Owner.MviewName: $Mview"
	Mview
elif [[ "$FuncToDo" == "MviewUpdate" ]]
then
        MviewUpdate=$3
    CheckVar                       \
        MviewUpdate                \
     && LogIt "Variables complete" \
     || LogCons "Parameter missing"
        LogCons "Function: Rebuild MV's Owner.MviewName: $Mview"
else
        usage
fi
LogCons "Main logfile: $MainErorLog"
