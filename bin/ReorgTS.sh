#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22


YesNo $(basename $0) || exit 1 && export RunOneTime=YES

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"
TimeStampLong=$(date +"%y%m%d_%H%M%S")

DbName=$2
FuncToDo=$1
AllParameter=$*


ParallelMove="parallel 8"

FuncToDo1=$(echo "$FuncToDo" | sed 's/\(.\).*/\1/' | tr "[a-z]" "[A-Z]")
FuncToDo2=$(echo "$FuncToDo" | sed 's/.\(.*\)/\1/' | tr "[A-Z]" "[a-z]")
FuncToDo=${FuncToDo1}${FuncToDo2}


# FuncToDo=$(echo "$(echo "$1" | tr "[A-Z]" "[a-z]" | sed 's/.*/\u&/')")

LogCons "Running function: $FuncToDo"


SqlScript=$OFA_LOG/tmp/Script.$DbName.$$.$PPID.$TimeStampLong.sql
SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.$$.$PPID.$TimeStampLong.log
TSInfo=$OFA_LOG/tmp/TSInfo.$DbName.$$.$PPID.$TimeStampLong.log
StatusFile=$OFA_LOG/tmp/StatusFile.$DbSid.$$.$PPID.log

#---------------------------------------------
SetReorgDir ()
#---------------------------------------------
{


	ReorgDir=$(echo $AllParameter | grep ReorgDir | awk -F "ReorgDir=" '{print $2}')
	if [[ -z $ReorgDir ]]
	then
		ReorgDir=$OFA_DB_DATA/$DbName
		LogCons "Default ReorgDir used, reorg directory: $ReorgDir"
	else
		LogCons "ReorgDir parmeter set, reorg directory: $ReorgDir"
	fi

	if [[ ! -d $ReorgDir ]]
	then
		LogError "Directory: $ReorgDir don't exist"
		exit 1
	fi
}
#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ReorgTS.sh  [FUNCTION] [SID] [see function] 
##
##
## Paremeter:
##
## SID: 
##      Name of the database
##
## Function:            Parameters:
## 
## Info    		[SID] Database name
##			List all TS's (None system TS's)
##
## Reorg		[SID] Database name
##			[TABLESPACE_NAME] Name of table space to reorg 
##                      <TARGET_TABLESPACE_NAME> Force target tablespace name
##				Reorg tablespace, copy all object to a new TS and delete old TS
##			If [TABLESPACE_NAME] is All, All TS's will be reorg.
##			If [TABLESPACE_NAME] is All_Force All TS's will be reorg and continue to next TS if one fail.
##			<ReorgDir=[DIR_NAME]> Set which directory used for the reorg (default: /DB/[SID]).
##
##			Reorg tablespace
##
## Remove		[SID] Database name
##			[TABLESPACE_NAME] Tablespace name to remove, ONLY removed if TS is empty.
##			Remove tablespace, only if empty.
##
## Shrink		[SID]
##			[TABLESPACE_NAME] If TABLESPACE_NAME All,  All TS will be Shrinked....  
##			Shrink the tablespace max possible.
##                      
## Last                 [SID]
##			[TABLESPACE_NAME]
##			Find the last object in the tablespace.
##
## Rename		[SID]
##			[OLD_TABLESPACE_NAME] [NEW_TABLESPACE_NAME]
##			Rename TS and datafiles to lower case [TABLESPACE_NAME].dbf
##			
## Move			[SID]
##			[SOURCE_TABLESPACE] [TARGET_TABLESPACE]
##			Move all objects from SOURCE_TABLESPACE -> TARGET_TABLESPACE 
#
__EOF
exit 1
}
#---------------------------------------------

    LogIt "Check variable completeness"
    CheckVar                       \
        DbName                      \
        FuncToDo                   \
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbName
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                # VolUp 1
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi
#---------------------------------------------
EmptyRecycBin ()
#---------------------------------------------
{
LogCons "Empty the RECYCLEBIN."
TsName=$1
	DoSqlQ "purge DBA_RECYCLEBIN;"
	BinTabName=$(DoSqlQ "select object_name from DBA_RECYCLEBIN where ts_name = '$TsName';")
        if [[ ! -z $BinTabName ]]
	then
		LogError "Still objects in RECYCLEBIN:"
		echo "$BinTabName"
	fi
}        
#---------------------------------------------
ListAll ()
#---------------------------------------------
{
# CreTsObj
LogCons "Logfile: $TSInfo"
sqlplus -s "/as sysdba" << __EOF >> $TSInfo 2>&1

set timing off
set feedback off

col "Tablespace" for a30
col "Used MB" for 99999999
col "Free MB" for 99999999
col "Total MB" for 99999999

/*
select 
df.tablespace_name "Tablespace",
totalusedspace "Used MB",
(df.totalspace - tu.totalusedspace) "Free MB",
df.totalspace "Total MB",
round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace))
"Pct. Free"
from
(select tablespace_name,
round(sum(bytes)/1024/1024) TotalSpace
from dba_data_files
group by tablespace_name) df,
(select round(sum(bytes)/(1024*1024)) totalusedspace, tablespace_name
from dba_segments
group by tablespace_name) tu
where 
df.tablespace_name = tu.tablespace_name 
and df.tablespace_name not in ('SYSTEM','SYSAUX')
and df.tablespace_name in (select tablespace_name from dba_tablespaces where contents = 'PERMANENT')
order by 2 
;
*/

select
df.tablespace_name "Tablespace",
totalusedspace "Used MB",
(df.totalspace - tu.totalusedspace) "Free MB",
df.totalspace "Total MB",
round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace)) "Pct. Free"
from
(select tablespace_name,
round(sum(bytes)/1024/1024) TotalSpace
from dba_data_files
group by tablespace_name) df,
(select round(sum(bytes)/(1024*1024)) totalusedspace, tablespace_name
from dba_segments
group by tablespace_name) tu
where
df.tablespace_name = tu.tablespace_name
and df.tablespace_name not in ('SYSTEM','SYSAUX')
and df.tablespace_name in (select tablespace_name from dba_tablespaces where contents = 'PERMANENT')
union all
/*
SELECT distinct 
TABLESPACE_NAME "Tablespace",
to_number('0') "Used MB",
to_number('0') "Free MB",
to_number('0') "Total MB",
to_number('0')  "Pct. Free"
FROM DBA_INDEXES, dual WHERE TABLESPACE_NAME not in (select distinct tablespace_name from dba_segments)
*/
SELECT distinct
a.TABLESPACE_NAME "Tablespace",
to_number('0') "Used MB",
to_number('0') "Free MB",
df.totalspace "Total MB",
to_number('100')  "Pct. Free"
FROM 
DBA_tablespace_objects a, 
dual,
(select tablespace_name,
round(sum(bytes)/1024/1024) TotalSpace
from dba_data_files
group by tablespace_name) df
WHERE 
a.TABLESPACE_NAME not in (select distinct tablespace_name from dba_segments)
and a.TABLESPACE_NAME not in (select distinct tablespace_name from dba_temp_files)
and a.tablespace_name=df.tablespace_name
order by 2
;

exit
__EOF

ErrorMsg=$(grep ORA- $TSInfo)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error getting TS info. Log: $TSInfo"
	exit 1
fi
echo ""
cat $TSInfo | LogStdInEcho
echo "---------------------------------------------------------------" >> $TSInfo
echo ""
}
#---------------------------------------------
CheckFreeSpace ()
#---------------------------------------------
{

FsDB=$(df -kP | grep $ReorgDir)
if [[ ! -z $FsDB ]]
then
	FSSize=$(df -kP | grep $ReorgDir | awk '{print $4}')
else
	FSSize=$(df -kP | grep $OFA_DB_DATA | awk '{print $4}')
fi

let "FSSizeMB = $FSSize/1024"
LogCons "Available space in $ReorgDir: $FSSizeMB MB"
echo ""
}

#---------------------------------------------
CreTsObj ()
#---------------------------------------------
{
# ---- Create DBA_TABLESPACE_OBJECT

        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.cre_dba_tablespace_objects.$$.$PPID.$TimeStampLong.sql
        LogCons "Create DBA_TABLESPACE_OBJECTS"
        LogCons "Log file: $SqlLog"
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1

        set feedback off
        set echo off
        set timing off
        set heading off

        CREATE OR REPLACE VIEW DBA_TABLESPACE_OBJECTS AS
        SELECT OWNER, TABLE_NAME "OBJECT_NAME", 'TABLE' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_TABLES
        UNION
        SELECT OWNER, INDEX_NAME "OBJECT_NAME", 'INDEX' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_INDEXES
        UNION
        -- SELECT OWNER, SEGMENT_NAME "OBJECT_NAME", 'LOB' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_LOBS
        SELECT OWNER, SEGMENT_NAME "OBJECT_NAME", 'LOB' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_LOBS where PARTITIONED = 'NO'
        UNION
        SELECT TABLE_OWNER, TABLE_NAME||'.'||PARTITION_NAME "OBJECT_NAME", 'TABLE PARTITION' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_TAB_PARTITIONS
        UNION
        SELECT INDEX_OWNER, INDEX_NAME||'.'||PARTITION_NAME "OBJECT_NAME", 'INDEX PARTITION' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_IND_PARTITIONS
        UNION
        SELECT TABLE_OWNER, TABLE_NAME||'.'||LOB_PARTITION_NAME "OBJECT_NAME", 'LOB PARTITION' "OBJECT_TYPE", SEGMENT_CREATED, TABLESPACE_NAME FROM DBA_LOB_PARTITIONS;

        CREATE OR REPLACE PUBLIC SYNONYM DBA_TABLESPACE_OBJECTS for DBA_TABLESPACE_OBJECTS;

__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating index move Log file: $SqlLog"
                exit 1
        fi
}


#---------------------------------------------
ForceContinue ()
#---------------------------------------------
{
ErrorCode=$1
if [[ $ErrorCode -ne 0 ]]
then
        if [[ ! -z $ForceGo ]]
        then
                LogCons "Go to next..."
                GoGo="continue"
        else
                GoGo="exit 1"
        fi
else
	GoGo="echo """
fi


# if [[ -z ForceGo ]]
# then
#	LogError "Error running step...."
#	exit 1
#else
#	LogWarning "Error in step, but continue. Force continue set"	
#fi
}
#---------------------------------------------
TSEmpty ()
#---------------------------------------------
{
CheckTs=$1
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.CheckTS.$$.$PPID.$TimeStampLong.log
        LogCons "Check if TS: $CheckTs is empty......"
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off

	select object_name from DBA_TABLESPACE_OBJECTS
        where
        tablespace_name ='$CheckTs';
__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting TS info: $SqlLog"
                return 1
        fi

        Empty=$(cat $SqlLog)

	if [[ -z $Empty ]]
	then
		LogError "Tablespace: $CheckTs is empty or don't exist"
		return 1
	fi
}
#---------------------------------------------
ReorgTS ()
#---------------------------------------------
{
  CheckVar TsName       \
  || Usage

ListAll

if [[ $TsName == 'All' ]]
then
	TsName=$(cat $TSInfo | grep -v -e "-----" -e "Tablespace"| awk '{print $1}')
	AllSet="All"
#        LogCons "Tablespaces to reorg: $TsName"
fi


# ---- remove default tablespace from list.

DefaultTS=$(DoSqlQ "SELECT PROPERTY_VALUE FROM DATABASE_PROPERTIES WHERE PROPERTY_NAME = 'DEFAULT_PERMANENT_TABLESPACE';")

DefaultTSInlist=$(echo $TsName | grep ${DefaultTS})

# echo "DefaultTS: ${DefaultTS}"
# echo "DefaultTSInlist: $DefaultTSInlist"

if [[ ! -z $DefaultTSInlist ]]
then
	LogCons "Removing "system" default TS: $DefaultTS from list (System default TS can't be renamed !)"

	# echo "TsName: $TsName"
	# echo "DefaultTS: $DefaultTS"

	TsName=$(echo $TsName | sed "s/$DefaultTS//g")

	# echo "TsNames: $TsNames"

	# LogCons "Tablespaces to reorg: $TsName"
fi

# ---- Remove TS from list contain LONG, LONG RAW

SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.RemoveList.$$.$PPID.$TimeStampLong.log

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off

        select distinct b.tablespace_name from 
        dba_tab_columns a,
        dba_tables b 
        where data_type like '%LONG%' and a.owner not in ('SYS','SYSTEM','WMSYS','OUTLN')
        and a.table_name = b.table_name; 
__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting list of TS with LONG, LONG RAW.  log file: $SqlLog"
                exit 1
        fi


###### NO CHECK
> $SqlLog

LongRawListTS=$(cat $SqlLog)
# LogCons "TS's with LONG, LONG RAW: ${LongRawListTS}"

# echo $TsName


for i in ${LongRawListTS}
do 
	LogCons "Remove TS's from List: $i (a table contain a LONG, LONG RAW, can't move tables contain LONG, LONG RAW)"
	# TsName=$(echo $TsName | sed "s/ $i / /g")
	TsName=$(echo $TsName | sed "s/\<$i\>/ /g")
done

# ---- Create DBA_TABLESPACE_OBJECT

# CreTsObj

if [[ -z $TsName ]]
then
	LogCons "No TS's to reorg."
	exit 1 
fi

LogCons "Tablespaces to reorg:"
echo $TsName | tr " " "\n"

	
for i in $TsName
do


echo " "
LogCons "------ Start Reorg of Tablespace: $i ------"


CheckFreeSpace

TSEmpty $i

ForceContinue $?
eval $GoGo

NeedSpace=$(grep -w $i $TSInfo | awk '{print $2}')

if [[ $NeedSpace -gt -1 ]] || [[ -z AllSet ]]
then

	if [[ ! -z $NeedSpace ]]
	then

		if [[ $NeedSpace -ge  $FSSizeMB ]]
		then
			# LogError "NOT space enough in FS: $OFA_DB_DATA/$DbName, $FSSizeMB MB to reorg: $i, Need space: $NeedSpace MB"
			LogWarning "NOT space enough in FS: $ReorgDir, $FSSizeMB MB to reorg: $i, Need space: $NeedSpace MB"
		else
			LogCons "Space enough in FS: $ReorgDir, $FSSizeMB MB to reorg: $i, Need space: $NeedSpace MB"
		fi
	else
		LogError "Tablepace: $i don't exist or empty"

		ForceContinue 1
		eval $GoGo

	fi

	EmptyRecycBin $i


	# ---- Create target TS
	
	if [[ -z $TsNameTarget   ]]
	then
		# Create new TS
        	TsBig=$(echo $i | grep -e "_BIGX" -e "_BIGY")
        	if [[ -z $TsBig ]]
		then
			TsNameNew="${i}_BIGY"
                	DataFileName=$(echo $TsNameNew.dbf | tr -s "[A-Z]" "[a-z]")
			LogCons "New Name TS: $TsNameNew, Datafile name: $DataFileName"
		elif [[ -z $(echo $i | grep "_BIGY")  ]]
		then
			TsNameNew=$(echo $i | sed 's/_BIGX/_BIGY/g')
                	DataFileName=$(echo $TsNameNew.dbf | tr -s "[A-Z]" "[a-z]")
			LogCons "New Name TS: $TsNameNew, Datafile name: $DataFileName"
                
		else 
			TsNameNew=$(echo $i | sed 's/_BIGY/_BIGX/g')
                	DataFileName=$(echo $TsNameNew.dbf | tr -s "[A-Z]" "[a-z]")
			LogCons "New Name TS: $TsNameNew, Datafile name: $DataFileName"
		fi 

		SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.creTS.$i.$$.$PPID.$TimeStampLong.log	
		LogCons "Creating new TS: $TsNameNew"
		LogCons "Logfile: $SqlLog"

		sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
		set echo on;
		set feedback on;
        	-- CREATE BIGFILE TABLESPACE $TsNameNew DATAFILE '$OFA_DB_DATA/$DbName/$DataFileName' SIZE 500M AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED;
        	CREATE BIGFILE TABLESPACE $TsNameNew DATAFILE '$ReorgDir/$DataFileName' SIZE 500M AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED;

        	exit
__EOF

	        ErrorMsg=$(grep ORA- $SqlLog)
        	if [[ ! -z "$ErrorMsg" ]]
        	then
                	LogError "Error create TS, Log file: $SqlLog"
			ForceContinue 1 
			eval $GoGo

        	fi

	else
		TsExist=$(DoSqlQ "select tablespace_name from dba_tablespaces where tablespace_name = '$TsNameTarget';")
		if [[ -z $TsExist ]]
		then
			LogError "Tablespace: $TsNameTarget DON'T exist"
                        ForceContinue 1
                        eval $GoGo
		fi
		TsNameNew=$TsNameTarget
	fi

	# ---- User rights
        LogCons "Set user rights on $TsNameNew"

        SqlScript=$OFA_LOG/tmp/Script.$DbName_$TsNameNew.rights.$i.$$.$PPID.$TimeStampLong.sql

        LogCons "Create User right script: $SqlScript"
	LogCons "Log File: $SqlScript"
        # sqlplus -s "/as sysdba" << __EOF >> $SqlScript 2>&1
        sqlplus -s "/as sysdba" << __EOF >> $SqlScript
        set feedback off
        set echo off
        set timing off
        set heading off

        select distinct 'ALTER USER '||owner||' default tablespace $TsNameNew;' from DBA_TABLESPACE_OBJECTS
        where tablespace_name = '$TsName'
        ;

        select distinct 'ALTER USER '||owner||' QUOTA UNLIMITED ON $TsNameNew;' from DBA_TABLESPACE_OBJECTS
        where tablespace_name = '$TsName'
        ;
__EOF

        ErrorMsg=$(grep ORA- $SqlScript)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating user rights script,  Log file: $SqlScript"
                        ForceContinue 1
                        eval $GoGo
        fi

        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.rights.$i.$$.$PPID.$TimeStampLong.log
        LogCons "Running User rights."
        LogCons "Script: $SqlScript"
        LogCons "Log file: $SqlLog"

	DoSql $SqlScript > $SqlLog 2>&1

        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error user Rights, Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi


	# ---- exp/imp LONG/LONGRAW
################
	SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.Long.$i.$$.$PPID.$TimeStampLong.sql
	ExpParFile=$OFA_LOG/tmp/ExpParFile.$DbName.Long.$i.$$.$PPID.$TimeStampLong.par
	ImpParFile=$OFA_LOG/tmp/ImpParFile.$DbName.Long.$i.$$.$PPID.$TimeStampLong.par
	LogCons "Move table(s) with LONG/LONGRAW"
	LogCons "Log file: $SqlScript"        
        sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1

        set feedback off
        set echo off
        set timing off
        set heading off

	select count(*) from 
        dba_tab_columns a,
        dba_tables b
        where data_type like '%LONG%' and a.owner not in ('SYS','SYSTEM','WMSYS','OUTLN')
        and a.table_name = b.table_name
        and tablespace_name = '$TsName';

	create or replace directory data_pump_reorg as '/backup/$DbName/datapump';
__EOF

RunMmDp
DbType=$(OraStartupFlagDBtype)

if [[ "$DbType" == "PDB" ]]
then	
	SqlScriptLog=$OFA_LOG/tmp/SqlLog.$DbName.Long.$i.$$.$PPID.$TimeStampLong.dir.log
        LogCons "Log file: $SqlScriptLog"
	sqlplus -s system/$MmDp@$DbName << __EOF > $SqlScriptLog 2>&1	
        create or replace directory data_pump_reorg as '/backup/$DbName/datapump';
__EOF

fi

	NumberTab=$(cat $SqlScript)

	if [[ $NumberTab -ne 0  ]]
	then
		LogCons "Get table list."
		LogCons "Log file: $SqlScript"
		sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1
	        set feedback off
	        set echo off
        	set timing off
        	set heading off
		
		select listagg(a.owner, ',') within group (order by a.owner) as name from
        	dba_tab_columns a,
        	dba_tables b
        	where data_type like '%LONG%' and a.owner not in ('SYS','SYSTEM','WMSYS','OUTLN')
        	and a.table_name = b.table_name
        	and tablespace_name = '$TsName';

		select listagg(''''||a.table_name||'''', ',') within group (order by a.table_name) as name from
        	dba_tab_columns a,
        	dba_tables b
        	where data_type like '%LONG%' and a.owner not in ('SYS','SYSTEM','WMSYS','OUTLN')
        	and a.table_name = b.table_name
        	and tablespace_name = '$TsName'; 
__EOF
	        ErrorMsg=$(grep ORA- $SqlScript)
        	if [[ ! -z "$ErrorMsg" ]]
        	then
                	LogError "Error getting schema/table name, Log file: $SqlScript"
                        	ForceContinue 1
                        	eval $GoGo
        	fi
		LogCons "Create exp parameter file"
		LogCons "Parameter file: $ExpParFile"
		
		SchemaNames=$(cat $SqlScript | sed '/^[[:space:]]*$/d' | head -1)
		TableNames=$(cat $SqlScript | sed '/^[[:space:]]*$/d' | tail -1)

		echo "directory=DATA_PUMP_REORG" > $ExpParFile
		echo "dumpfile=expdp.$TsName.$TimeStampLong.dmp" >> $ExpParFile
		echo "logfile=expdp.$TsName.$TimeStampLong.log" >> $ExpParFile
		echo "REUSE_DUMPFILES=YES" >> $ExpParFile
		echo "INCLUDE = TABLE:\"IN ($TableNames)\"" >> $ExpParFile
		echo "SCHEMAS = $SchemaNames" >> $ExpParFile		

		# expdp \'/ as sysdba\' parfile=$ExpParFile
		expdp system/$MmDp@$DbName parfile=$ExpParFile
		

                LogCons "Create imp parameter file"
                LogCons "Parameter file: $ImpParFile"

                echo "directory=DATA_PUMP_REORG" > $ImpParFile
                echo "dumpfile=expdp.$TsName.$TimeStampLong.dmp" >> $ImpParFile
                echo "logfile=impdp.$TsName.$TimeStampLong.log" >> $ImpParFile
		echo "TABLE_EXISTS_ACTION=REPLACE" >> $ImpParFile
		echo "REMAP_TABLESPACE=$TsName:$TsNameNew" >> $ImpParFile

		# impdp \'/ as sysdba\' parfile=$ImpParFile
		impdp system/$MmDp@$DbName parfile=$ImpParFile
	else
		LogCons "No tables with LONG/LONGRAW in TS: $TsName"
	fi


################
        # ---- Move AQ's 
################
        SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.move_AQ.$i.$$.$PPID.$TimeStampLong.sql
        LogCons "Move AQ's"
	LogCons "Create Move AQ's script: $SqlScript"
        LogCons "Log file: $SqlScript"
        sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1

        set feedback off
        set echo off
        set timing off
        set heading off

        select distinct 'ALTER USER '||owner||' default tablespace $TsNameNew;' from dba_segments
        where tablespace_name = '$TsName'
        ;

        select distinct 'ALTER USER '||owner||' QUOTA UNLIMITED ON $TsNameNew;' from dba_segments
        where tablespace_name = '$TsName'
        ;

	prompt @$OFA_SQL/move_qt_pkgs.sql;;
	prompt @$OFA_SQL/move_qt_pkgb.plb;;

	-- select a.owner, a.queue_table, b.tablespace_name from dba_queue_tables a, dba_segments b where a.queue_table = b.segment_name and a.owner = b.owner order by tablespace_name;

	-- exec move_qt_pkg.move_queue_table('ODSAQ','FT_Q_ODS_IN','ODSAQ_DATA','ODSAQ_DATA_BIGY');

        -- select  'prompt Move AQ: '||owner||'.'||a.queue_table || chr(10) ||'exec move_qt_pkg.move_queue_table(''||a.owner||'',''||a.queue_table||'',${TsName},${TsNameNew}');'
	-- from dba_queue_tables a, dba_segments b where a.queue_table = b.segment_name and a.owner = b.owner order by tablespace_name;

	select 'prompt Move AQ: '||a.owner||'.'||a.queue_table || chr(10) ||'exec move_qt_pkg.move_queue_table('''||a.owner||''','''||a.queue_table||''',''${TsName}'',''${TsNameNew}'');'
        from dba_queue_tables a, dba_segments b where a.queue_table = b.segment_name and a.owner = b.owner and tablespace_name = '${TsName}' order by tablespace_name;


__EOF
        ErrorMsg=$(grep ORA- $SqlScript)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating AQ move script,  Log file: $SqlScript"
                        ForceContinue 1
                        eval $GoGo
        fi

        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.move_AQ.$i.$$.$PPID.$TimeStampLong.log
        LogCons "Running Move AQ's."
        LogCons "Script: $SqlScript"
        LogCons "Log file: $SqlLog"

DoSql $SqlScript > $SqlLog 2>&1

        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Move AQ's, Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi

#        cat $SqlLog | LogStdIn


################



	# ---- Create reorg script

	LogCons "Move Objects from: $TsName to $TsNameNew"

	SqlScript=$OFA_LOG/tmp/Script.$DbName_$TsName.reorg.$i.$$.$PPID.$TimeStampLong.sql

        LogCons "Create Reorg script: $SqlScript"

        # sqlplus -s "/as sysdba" << __EOF >> $SqlScript 2>&1
        sqlplus -s "/as sysdba" << __EOF >> $SqlScript
	set feedback off
	set echo off
	set timing off
	set heading off

	select distinct 'ALTER USER '||owner||' default tablespace $TsNameNew;' from dba_segments 
	where tablespace_name = '$TsName'
	;

        select distinct 'ALTER USER '||owner||' QUOTA UNLIMITED ON $TsNameNew;' from dba_segments
        where tablespace_name = '$TsName'
        ;

        -- Move table where LOB's are ARRAY.
        -- select 'prompt reorg table (Move table where LOB(s) are ARRAY.): '||a.owner||'."'||a.table_name||'"'|| chr(10)
	-- || 'alter table '||a.owner||'."'||a.TABLE_NAME||'" MOVE tablespace ${TsNameNew} ${ParallelMove};' from dba_tab_columns a, dba_types b, dba_tables c
	-- where
	-- a.owner=b.owner and
	-- a.data_type=b.type_name and
	-- a.OWNER=c.OWNER and
	-- a.table_name=c.table_name and 
	-- c.tablespace_name = '$TsName' order by 1;

	select 'prompt reorg table (Move LOB partitions): '||a.table_owner||'."'||a.table_name||'"'|| chr(10)
        || 'alter table '||a.table_owner||'."'||a.table_name||'" MOVE PARTITION "'||a.partition_name||'" LOB ("'||a.column_name||'") STORE AS basicfile (TABLESPACE ${TsNameNew}) ${ParallelMove};'
        from dba_lob_partitions a where tablespace_name ='$TsName' and SECUREFILE='NO' order by 1;

	select 'prompt reorg table (Move LOB partitions): '||a.table_owner||'."'||a.table_name||'"'|| chr(10)
        || 'alter table '||a.table_owner||'."'||a.table_name||'" MOVE PARTITION "'||a.partition_name||'" LOB ("'||a.column_name||'") STORE AS SECUREFILE (TABLESPACE ${TsNameNew}) ${ParallelMove};'
        from dba_lob_partitions a where tablespace_name ='$TsName' and SECUREFILE='YES' order by 1;


        -- Move LOB column

	-- select 'prompt reorg table (Move LOB column): '||a.owner||'."'||a.table_name||'"'|| chr(10) || 'alter table '||a.owner||'."'||a.table_name||'" MOVE LOB("'||a.column_name||'") STORE AS (TABLESPACE ${TsNameNew}) ${ParallelMove};'
	select 'prompt reorg table (Move LOB column): '||a.owner||'."'||a.table_name||'"'|| chr(10) || 'alter table '||a.owner||'."'||a.table_name||'" MOVE LOB("'||a.column_name||'") STORE AS (TABLESPACE ${TsNameNew}) ${ParallelMove};'
	from dba_lobs a where tablespace_name ='$TsName' and PARTITIONED = 'NO'
	and a.table_name not in (select distinct a.table_name from dba_tab_columns a, dba_types b, dba_tables c
                                 where a.owner=b.owner and a.data_type=b.type_name and a.OWNER=c.OWNER and a.table_name=c.table_name and
                                 c.tablespace_name = '$TsName');

        -- where SEGMENT_NAME in (select segment_name from dba_segments where tablespace_name ='$TsName');


        -- Move LOB column not in dba_lobs

        select 'prompt reorg table (Move LOB column not in dba_lobs): '||a.owner||'."'||a.table_name||'"'|| chr(10) || 'alter table '||a.owner||'."'||a.table_name||'" MOVE LOB("'||a.column_name||'") STORE AS (TABLESPACE ${TsNameNew}) ${ParallelMove};'
        from dba_tab_columns a, dba_tablespace_objects b
	where
	a.table_name=b.object_name
	and a.owner=b.owner
	and a.data_type in ('CLOB','BLOB')
	and b.tablespace_name ='$TsName'
        and a.table_name not in (select table_name from dba_lobs a where SEGMENT_NAME in (select segment_name from dba_segments where tablespace_name = '$TsName'))
	and a.table_name not in (select distinct a.table_name from dba_tab_columns a, dba_types b, dba_tables c
				 where a.owner=b.owner and a.data_type=b.type_name and a.OWNER=c.OWNER and a.table_name=c.table_name and 
				 c.tablespace_name = '$TsName');

        -- Movin tables none IOT

        select 'prompt reorg table: (None IOT) '||a.owner||'."'||a.table_name||'"'|| chr(10) || 'alter table '||owner||'."'||table_name||'" move tablespace $TsNameNew ${ParallelMove};' 
	from dba_tables a 
	where 
	tablespace_name = '$TsName'
	-- and object_type = 'TABLE'
	and IOT_NAME is null;

        -- Movin tables IOT

        select 'prompt reorg table: (IOT) '||a.owner||'."'||a.table_name||'" IOT_NAME: "'||a.iot_name||'"'|| chr(10) || 'alter table '||owner||'."'||iot_name||'" move tablespace $TsNameNew ${ParallelMove};'
        from dba_tables a
        where
        tablespace_name = '$TsName'
        -- and object_type = 'TABLE'
	and IOT_NAME not like 'AQ\$_%'
        and IOT_NAME is not null;

        -- Movin tables IOT overflow.

        select 'prompt reorg table: (IOT overflow) '||a.owner||'."'||a.table_name||'" IOT_NAME: "'||a.iot_name||'"'|| chr(10) 
	|| 'alter table '||owner||'."'||iot_name||'" move tablespace $TsNameNew OVERFLOW TABLESPACE $TsNameNew ${ParallelMove};'
        from dba_tables a
        where
        tablespace_name = '$TsName'
        -- and object_type = 'TABLE'
        and IOT_NAME not like 'AQ\$_%'
        and IOT_NAME is not null
	and IOT_TYPE= 'IOT_OVERFLOW';



        -- Move paratitions

        select 'prompt reorg table partition: '||a.table_owner||'."'||a.table_name||'"'|| chr(10) || 'alter table '||table_owner||'."'||table_name||'" move partition '||partition_name||' tablespace $TsNameNew ${ParallelMove};'
        from dba_TAB_PARTITIONS a
        where
        tablespace_name = '$TsName'
        ;


__EOF



        ErrorMsg=$(grep ORA- $SqlScript | head -1)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error create reorg script Log: $SqlScript"
		LogError "Error: $ErrorMsg"
                        ForceContinue 1
                        eval $GoGo
        fi
	
	# ---- Run script
	
	SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.reorg.$i.$$.$PPID.$TimeStampLong.log
	LogCons "Running reorg script."
 	LogCons "Script: $SqlScript"
	LogCons "Log file: $SqlLog"

DoSql $SqlScript > $SqlLog 2>&1

	ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error running reorg of $TsName" 
		LogError "Error: $ErrorMsg"
		LogError "Log file: $SqlLog"
		
                        ForceContinue 1
                        eval $GoGo
        fi

#	cat $SqlLog | LogStdIn

	# ---- Move indexes and move constraint.
	
	SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.move_idx.$i.$$.$PPID.$TimeStampLong.sql
	LogCons "Move  indexes/constraint."
	LogCons "Source TS: $TsName, Target TS: $TsNameNew"
	LogCons "Create Move script: $SqlScript"
        sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1
        
	set feedback off
        set echo off
        set timing off
        set heading off

	prompt set echo on;;
	prompt set feedback on;;
	prompt set heading on;;

        select distinct 'ALTER USER '||owner||' default tablespace $TsNameNew;' from dba_indexes
        where tablespace_name = '$TsName'
        ;

        select distinct 'ALTER USER '||owner||' QUOTA UNLIMITED ON $TsNameNew;' from dba_indexes
        where tablespace_name = '$TsName'
        ;

        -- Move index/constraint

	select 'prompt Move index/constraint: '||a.owner||'.'||a.index_name|| chr(10) 
	|| 'alter index '||owner||'."'||index_name||'" rebuild tablespace ${TsNameNew} ${ParallelMove} nologging;'
        from dba_indexes a
        where
        tablespace_name = '$TsName' 
	and index_name not in (select index_name from all_lobs where tablespace_name not in ('SYSTEM','SYSAUX'))
	and index_type  not like '%IOT%'
	;

        -- Move Rebuild index partitions

        select distinct 'prompt rebuild index partition: '||a.index_owner||'."'||a.index_name||'"'|| chr(10) 
	|| 'alter index '||a.index_owner||'."'||a.index_name||'" rebuild partition '||a.partition_name||' tablespace ${TsNameNew} ${ParallelMove} nologging;'
        from dba_IND_PARTITIONS a, dba_indexes b
        where
        a.tablespace_name = '$TsName' 
        and a.index_name = b.index_name
        and a.index_owner=b.owner
        and index_type not like '%IOT%'
	and partition_name not in (select partition_name from dba_lob_partitions)

	--      a.tablespace_name = '$TsName'
	--	and a.index_name = b.index_name
	--	and a.index_name not in (select distinct a.index_name 
	--	from dba_IND_PARTITIONS a, dba_indexes b where a.index_name = b.index_name and  index_type like '%IOT%' and a.tablespace_name = '$TsName') 
       ;

	-- Move index partitions on IOT tables.
	
	select distinct 'prompt Move index partitions on IOT tables: '||a.index_owner||'.'||table_name||' partition name: '||a.partition_name|| chr(10) 
	||'alter table '||a.index_owner||'.'||b.table_name||' move partition '||a.partition_name||' tablespace ${TsNameNew};' 
	from dba_IND_PARTITIONS a, dba_indexes b where a.index_name = b.index_name and  index_type like '%IOT%' and a.tablespace_name = '$TsName';

	-- Move index/table IOT
	
	select 'prompt Move index/table IOT: '||a.owner||'.'||a.index_name|| chr(10) 
	||'alter table '||a.owner||'."'||a.table_name||'" move tablespace ${TsNameNew} ${ParallelMove};'
	from dba_indexes a where index_type like '%IOT%' and tablespace_name = '$TsName';


        select 'prompt Move index/table IOT (with partitions): '||a.index_owner||'.'||a.index_name|| chr(10)
        ||'alter table '||a.index_owner||'."'||b.table_name||'" move partition '||a.partition_name||' tablespace ${TsNameNew};'
	from dba_IND_PARTITIONS a, dba_indexes b 
	where 
	a.index_name=b.index_name 
	and a.index_owner=b.owner 
	and a.tablespace_name = '$TsName'
	and index_type like '%IOT%'
	;

	-- Move index partition (Not in dba_indexes)

        select distinct 'prompt rebuild index partition (Not in dba_indexes): '||a.index_owner||'."'||a.index_name||'"'|| chr(10) 
        || 'alter index '||a.index_owner||'."'||a.index_name||'" rebuild partition '||a.partition_name||' tablespace ${TsNameNew} ${ParallelMove} nologging;'
        from dba_IND_PARTITIONS a
        where
        a.tablespace_name = '$TsName'
	and a.index_name not in  (select index_name from dba_indexes where index_type like '%IOT%')
	order by 1
        ;



__EOF


        ErrorMsg=$(grep ORA- $SqlScript)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating index move Log file: $SqlScript"
                        ForceContinue 1
                        eval $GoGo
        fi


        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.move_idx.$i.$$.$PPID.$TimeStampLong.log
        LogCons "Running move indexes/constraint."
	LogCons "Script: $SqlScript"
        LogCons "Log file: $SqlLog"

DoSql $SqlScript > $SqlLog 2>&1


        ErrorMsg=$(grep ORA- $SqlLog | head -1)
        if [[ ! -z "$ErrorMsg" ]]
        then
		LogError "Error move index/constraint: $ErrorMsg" 
                LogError "Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi


#	cat $SqlLog | LogStdIn

        # ---- Rebuild invalid indexes

        SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.rebuild_idx.$i.$$.$PPID.$TimeStampLong.sql
        LogCons "Rebuild invalid indexes"
        LogCons "Log file: $SqlScript"
        sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1

        set feedback off
        set echo off
        set timing off
        set heading off

        -- Rebuild indexes

        select  'prompt Rebuild index: '||b.owner||'.'||b.index_name|| chr(10) || 'alter index '||b.owner||'."'||b.index_name||'" rebuild online ${ParallelMove} nologging;' 
	from dba_tables a, dba_indexes b 
	where 
	a.TABLESPACE_NAME = '${TsNameNew}' 
	and b.STATUS <> 'VALID' 
	and a.table_name = b.table_name
	and b.index_name not in (select distinct index_name from dba_ind_partitions);

	-- Rebuild partition indexes 

	select  'prompt Rebuild partition index: '||b.index_owner||'.'||b.index_name|| chr(10) 
	|| 'alter index '||b.index_owner||'."'||b.index_name||'" rebuild partition '||b.partition_name||' ${ParallelMove} nologging;'
	 from dba_IND_PARTITIONS b where b.TABLESPACE_NAME = '${TsNameNew}' and b.STATUS <> 'USABLE';


	
	--	select  'prompt Rebuild partition index: '||b.index_owner||'.'||b.index_name|| chr(10) 
	--	|| 'alter index '||b.index_owner||'."'||b.index_name||'" rebuild partition '||b.partition_name||' ${ParallelMove} nologging;'
	--      from dba_TAB_PARTITIONS a, dba_IND_PARTITIONS b where a.TABLESPACE_NAME = '${TsNameNew}' and a.PARTITION_NAME = b.PARTITION_NAME and b.STATUS <> 'USABLE';


__EOF
        ErrorMsg=$(grep ORA- $SqlScript)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating index rebuild script, Log file: $SqlScript"
                        ForceContinue 1
                        eval $GoGo
        fi

        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.rebuild.$i.$$.$PPID.$TimeStampLong.log
        LogCons "Running Rebuild invalid indexes."
        LogCons "Script: $SqlScript"
        LogCons "Log file: $SqlLog"

DoSql $SqlScript > $SqlLog 2>&1

        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error creating index rebuild, Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi

	SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.ShrinkTS.$i.$$.$PPID.$TimeStampLong.log
        LogCons "Shrink tablespace: ${TsNameNew}, ${TsName}"
	LogCons "Log file: $SqlLog"
        # DoSqlQ $OFA_SQL/ShrinkTS.sql ${TsNameNew} > $SqlLog  2>&1
        # DoSqlQ $OFA_SQL/ShrinkTS.sql ${TsName} >> $SqlLog  2>&1
# echo "STOP"
# read
	ShrinkTs ${TsNameNew} 2>&1 | tee $SqlLog
	ShrinkTs ${TsName}  2>&1 | tee -a $SqlLog


        ErrorMsg=$(grep ORA- $SqlLog)

        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Shrink tablespace: ${TsNameNew}, ${TsName} log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
	else
		cat $SqlLog | LogStdIn
        fi


	# ---- Remove old TS if empty

        

	LogCons "Check if TS: $TsName is empty"
	SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.empty.$i.$$.$PPID.$TimeStampLong.log
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        -- set heading off
	col object_name form a50;
	col owner form a20;
	col object_type form a50;

        select owner,object_name, object_type from DBA_TABLESPACE_OBJECTS
        where
        tablespace_name ='$TsName';

__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting TS info: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi

	TsEmpty=$(cat $SqlLog) 

        if [[ ! -z $TsEmpty ]] 
	then
		LogError "Tablespace:$TsName  are not empty! "
		LogCons "Check log file $SqlLog';"
                        ForceContinue 1
                        eval $GoGo
	fi	


	RmLog=$OFA_LOG/tmp/SqlLog.$DbName.RmDataFile.$$.$PPID.$TimeStampLong.log

	RemoveDataFiles=$(DoSqlQ "select file_name from dba_data_files where tablespace_name = '$TsName';" | sed 's/[[:space:]]//g')

	SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.removeTs.$i.$$.$PPID.$TimeStampLong.log
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
       	drop tablespace $TsName; 
__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error dropping TS: $TsName Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
	fi

	LogCons "Remove old data files"
        LogCons "Log File: $RmLog"
	for i in $RemoveDataFiles
	do
                FileName=$(echo $i | awk -F "/" '{print $NF}')
                # DirName=$(echo $i | awk 'BEGIN{FS=OFS="/"}NF--')
                DirName=$(echo $i | awk -F "/" 'OFS="/"{$NF="";print $0}')
		cd $DirName
		if [[ $OSNAME == AIX ]]
		then
			FileToRm=$(/opt/freeware/bin/printf "%q\n" *${FileName}*)
		else
                	FileToRm=$(printf "%q\n" *${FileName}*)
		fi
                LogCons "Remove file: $FileToRm"
                LogCons "Remove data file: $DirName/$FileToRm"
                eval "rm ${FileToRm} 2>&1" | tee $RmLog | LogStdInEcho

		if [[ $? -ne 0 ]] 
		then
			LogError "Error remove data file: $i"
		fi
	done
        
        if [[ $FuncToDo == "Move" ]]
	then
		LogCons "No rename of TS"
		return
	else
		RenameTS ${TsNameNew} ${TsName} 
	fi

        if [[ $? -ne 0 ]]
        then
                LogError "Error rename TS ${TsName} to ${TsNameNew} "
                ForceContinue 1
                eval $GoGo
        fi


else
	LogCons "No Reorg done, no data in TS: $i "
fi


done
}
#---------------------------------------------
ListEmptyTS ()
#---------------------------------------------
{
# CreTsObj
TSInfoEmpty=$OFA_LOG/tmp/TSInfoEmpty.$DbName.$$.$PPID.$TimeStampLong.log
LogCons "List empty TS's"
LogCons "Logfile: $TSInfo"
sqlplus -s "/as sysdba" << __EOF >> $TSInfoEmpty 2>&1

set timing off
set feedback off

col "Tablespace" for a30
col "Used MB" for 99999999
col "Free MB" for 99999999
col "Total MB" for 99999999

select
df.tablespace_name "Tablespace",
-- totalusedspace "Used MB",
-- (df.totalspace - tu.totalusedspace) "Free MB",
df.totalspace "Total MB"
-- round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace)) "Pct. Free"
from
(select tablespace_name,
round(sum(bytes)/1024/1024) TotalSpace
from dba_data_files
group by tablespace_name) df
-- (select round(sum(bytes)/(1024*1024)) totalusedspace, tablespace_name
-- from dba_segments
-- group by tablespace_name) tu
where
-- df.tablespace_name = tu.tablespace_name
df.tablespace_name not in ('SYSTEM','SYSAUX')
and df.tablespace_name in (select tablespace_name from dba_tablespaces where contents = 'PERMANENT')
and df.tablespace_name in
(
select to_char(tablespace_name) from dba_tablespaces
minus
select distinct to_char(tablespace_name) from DBA_TABLESPACE_OBJECTS
) order by 1;

exit
__EOF

ErrorMsg=$(grep ORA- $TSInfoEmpty)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error getting TS info. Log: $TSInfoEmpty"
        exit 1
fi

echo ""
cat $TSInfoEmpty | LogStdInEcho
echo "---------------------------------------------------------------" >> $TSInfoEmpty
echo ""


}
#---------------------------------------------
RemoveEmptyTS ()
#---------------------------------------------
{
        # ---- Remove old TS if empty
if [[ -z $TsName ]]
then
	LogError "Parameter tablespace name missing....."
	usage
	exit 1
fi 


        LogCons "Check if TS: $TsName is empty"
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.RemoveEmptyTS.$i.$$.$PPID.$TimeStampLong.log
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off

        select object_name from DBA_TABLESPACE_OBJECTS
        where
        tablespace_name ='$TsName';

__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting TS info: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi

        TsEmpty=$(cat $SqlLog)

        if [[ ! -z $TsEmpty ]]
        then
                LogError "Tablespace:$TsName  are not empty! "
                LogCons "Check log file $SqlLog';"
                        ForceContinue 1
                        eval $GoGo
        fi

	RmLog=$OFA_LOG/tmp/SqlLog.$DbName.RmDataFile.$$.$PPID.$TimeStampLong.log

	RemoveDataFiles=$(DoSqlQ "select file_name from dba_data_files where tablespace_name = '$TsName';" | sed 's/[[:space:]]//g')
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.RemoveEmptyTS.$i.$$.$PPID.$TimeStampLong.log
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        drop tablespace $TsName;
__EOF
        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error dropping TS: $TsName Log file: $SqlLog"
                        ForceContinue 1
                        eval $GoGo
        fi

        LogCons "Remove old data files"
        for i in $RemoveDataFiles
        do
                FileName=$(echo $i | awk -F "/" '{print $NF}')
                # DirName=$(echo $i | awk 'BEGIN{FS=OFS="/"}NF--')
		DirName=$(echo $i | awk -F "/" 'OFS="/"{$NF="";print $0}')
                cd $DirName
                if [[ $OSNAME == AIX ]]
                then
                        FileToRm=$(/opt/freeware/bin/printf "%q\n" *${FileName}*)
                else
                        FileToRm=$(printf "%q\n" *${FileName}*)
                fi
                LogCons "Remove file: $FileToRm"
                LogCons "Remove data file: $DirName/$FileToRm"

                # FileToRm=$(printf "%q\n" *${FileName}*)
                LogCons "Remove file: $FileToRm"
                LogCons "Remove data file: $DirName/$FileToRm"
                eval "rm ${FileToRm} 2>&1" | tee $RmLog | LogStdInEcho

                if [[ $? -ne 0 ]]
                then
                        LogError "Error remove data file: $i"
                fi
        done

}
#---------------------------------------------
Shrink ()
#---------------------------------------------
{
LogCons "Shrink tablespace(s)......"
if [[ "$TsName" == "All" ]]
then
	LogCons "Shrink ALL tablespaces"
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.Shrink.$i.$$.$PPID.$TimeStampLong.log
	SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.Shrink.$i.$$.$PPID.$TimeStampLong.sql
	LogCons "Script file: $SqlScript"
	LogCons "Logfile: $SqlLog"
        sqlplus -s "/as sysdba" << __EOF > $SqlScript 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off

	select '@$OFA_SQL/ShrinkTS.sql '||tablespace_name from dba_tablespaces 
	where contents ='PERMANENT' and tablespace_name not in ('SYSTEM','SYSAUX');
__EOF
	LogCons "Running Shrink of ALL tablespaces"
	DoSqlQ $SqlScript | tee -a $SqlLog
else
	LogCons "Shrink tablespace: $TsName" 
	DoSqlQ $OFA_SQL/ShrinkTS.sql $TsName
fi

        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Shrink tablespace(s), Log file: $SqlLog"
        fi
}
#---------------------------------------------
ShrinkTs ()
#---------------------------------------------
{
ShrinkTsName=$1

if [[ $ShrinkTsName == All ]]
then
	TsToReorg="%"
else
	TsToReorg="$ShrinkTsName"
        TsExsist=$(DoSqlQ "select tablespace_name from dba_tablespaces where tablespace_name ='$TsToReorg';")

	if [[ -z $TsExsist ]]
	then
		LogError "Tablespace: $TsToReorg don't exist...."
		return 1
	fi
fi

# echo $TsToReorg

# echo "STOP"
# read 

LogCons "Shrink Tablespaces (ShrinkTs): $ShrinkTsName"
SqlLogTs=$OFA_LOG/tmp/SqlLog.$DbName.ShrinkTs.$ShrinkTsName.$$.$PPID.$TimeStampLong.log
SqlScriptTs=$OFA_LOG/tmp/SqlLog.$DbName.ShrinkTs.$ShrinkTsName.$$.$PPID.$TimeStampLong.sql
BlockSizeDb=$(DoSqlQ "select value from v\$parameter where name = 'db_block_size';")

LogCons "Script file: $SqlScriptTs"
LogCons "Logfile: $SqlScriptTs"
sqlplus -s "/as sysdba" << __EOF > $SqlScriptTs 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off


	select 'alter database datafile '''||file_name||''' resize ' ||
	case
		when ceil( (nvl(hwm,1)*$BlockSizeDb)/1024/1024 ) > c.INITIAL_EXTENT*c.MIN_EXTENTS/1024/1024
		then GREATEST(ceil( (nvl(hwm,1)*$BlockSizeDb)/1024/1024 ),128)
		else GREATEST(c.INITIAL_EXTENT*c.MIN_EXTENTS/1024/1024,128)
	end
	|| 'm;' cmd
	from dba_data_files a, 
	( select file_id, max(block_id+blocks-1) hwm
	from dba_extents
	group by file_id ) b, dba_tablespaces c
	where a.file_id = b.file_id(+)
	and ceil( blocks*$BlockSizeDb/1024/1024) - ceil( (nvl(hwm,1)*$BlockSizeDb)/1024/1024 ) > c.INITIAL_EXTENT/1024/1024*c.MIN_EXTENTS/1024/1024*2
	-- and a.tablespace_name = '$ShrinkTsName'
	and a.tablespace_name = c.tablespace_name(+) and a.tablespace_name like '$TsToReorg'
	/
	prompt -- Running: $OFA_LOG/tmp/SqlLog.$DbName.ShrinkTs.$ShrinkTsName.$$.$PPID.$TimeStampLong.sql
        -- set feedback on
        -- set echo on
        -- set timing on
        -- set heading on

-- 	@$OFA_LOG/tmp/SqlLog.$DbName.ShrinkTs.$ShrinkTsName.$$.$PPID.$TimeStampLong.sql
__EOF

# echo "STOP"
# read 
        ErrorMsg=$(grep ORA- $SqlScriptTs)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error Shrink Tablespace: $ShrinkTsName, Log file: $SqlScriptTs"
        fi
}
#---------------------------------------------
RenameTS ()
#---------------------------------------------
{
LogCons "Rename tablespace(s)......"
OldTSName=$1
NewTSName=$2
        LogCons "Check tablespace $OldTSName"
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.Check.$$.$PPID.$TimeStampLong.log
        SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.Check.$$.$PPID.$TimeStampLong.sql
        LogCons "Logfile: $SqlLog"
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off
	set serveroutput on;
	set verify off;
	DECLARE

	V_COUNT_1 number;
	V_COUNT_2 number;
	V_DIR_NAME VARCHAR2 (128);
	V_DIR_NAME_NEW VARCHAR2 (128) :='$OFA_DB_DATA/$DbName/';
	V_OLD_FILE_NAME VARCHAR2 (128);
	V_NEW_FILE_NAME VARCHAR2 (128);
	V_OLD_TS_NAME   VARCHAR2 (128) := UPPER ('$OldTSName');
	V_NEW_TS_NAME   VARCHAR2 (128) := UPPER ('$NewTSName');
	V_NEW_TS_NAME_LOWER VARCHAR2 (128) := LOWER ('$NewTSName');
	V_SQL_STR varchar(256);

	BEGIN
	        select count(*) into V_COUNT_1 from dba_tablespaces where bigfile = 'YES' and tablespace_name = V_OLD_TS_NAME;
	        select count(*) into V_COUNT_2 from dba_tablespaces where bigfile = 'YES' and tablespace_name = V_NEW_TS_NAME;


	IF (V_COUNT_1 != 0 and V_COUNT_2 = 0) THEN
	        DBMS_OUTPUT.put_line ('Tablespace: '||V_OLD_TS_NAME||' exist.....');

	        select SUBSTR(file_name, INSTR(file_name,'/',-1) + 1) into V_OLD_FILE_NAME from dba_data_files where tablespace_name = V_OLD_TS_NAME;

	        select replace(file_name,SUBSTR(file_name, INSTR(file_name,'/',-1) + 1)) into V_DIR_NAME from dba_data_files where tablespace_name = V_OLD_TS_NAME;

	        select V_NEW_TS_NAME_LOWER||'.dbf' into V_NEW_FILE_NAME from dual;

        	DBMS_OUTPUT.put_line ('Old file name: '||V_OLD_FILE_NAME);
        	DBMS_OUTPUT.put_line ('New file name: '||V_NEW_FILE_NAME);
        	DBMS_OUTPUT.put_line ('Old TS name: ' ||V_OLD_TS_NAME||' New TS name: '||V_NEW_TS_NAME);
        	DBMS_OUTPUT.put_line ('Directory name: '||V_DIR_NAME);

        	V_SQL_STR := 'alter tablespace '||V_OLD_TS_NAME||' rename to '||V_NEW_TS_NAME||'';
        	DBMS_OUTPUT.put_line ('Rename TS: '||V_SQL_STR);
        	V_SQL_STR := 'alter database rename file '''||V_DIR_NAME||V_OLD_FILE_NAME||''' to '''||V_DIR_NAME_NEW||V_NEW_FILE_NAME||'''';
        	DBMS_OUTPUT.put_line ('Rename file: '||V_SQL_STR);
	ELSE
        	IF V_COUNT_1 = 0 THEN
                	DBMS_OUTPUT.put_line ('ERROR (ORA-): Tablespace: '||V_OLD_TS_NAME||' do not exist or NOT a BIGFILE tablespace...');
        	ELSIF V_COUNT_2 > 0 THEN
                	DBMS_OUTPUT.put_line ('ERROR (ORA-): New Tablespace: '||V_OLD_TS_NAME||' already exist.....');
        	END IF;
	END IF;
	END;
	/

__EOF

        ErrorMsg=$(grep ORA- $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error by remane tablespace, Log file: $SqlLog"
		LogError "$ErrorMsg"
		return 1
        fi

RenameTsComm=$(grep "Rename TS:" $SqlLog | awk -F ":" '{print $2}')
RenameFileComm=$(grep "Rename file:" $SqlLog | awk -F ":" '{print $2}')
RenameOldFile=$(grep "Old file name:" $SqlLog | awk -F ":" '{print $2}' | tr -d ' ')
RenameNewFile=$(grep "New file name:" $SqlLog | awk -F ":" '{print $2}' | tr -d ' ')
RenameDir=$(grep "Directory name:" $SqlLog | awk -F ":" '{print $2}' | tr -d ' ')

# echo $RenameTsComm
# echo $RenameFileComm
# echo $RenameOldFile
# echo $RenameNewFile
# echo $RenameDir
FullOldName="${RenameDir}${RenameOldFile}"
FullNewName="${OFA_DB_DATA}/${DbName}/${RenameNewFile}"
# echo $FullOldName
# echo $FullNewName

if [[ -e ${RenameDir}${RenameNewFile} ]]
then
	LogError "Can't rename TS data file: ${RenameDir}${RenameNewFile}  already exist... "
	return 1
fi

        LogCons "Rename tablespace $OldTSName to $NewTSName"
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.Rename.$$.$PPID.$TimeStampLong.log
        SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.Rename.$$.$PPID.$TimeStampLong.sql
        LogCons "Logfile: $SqlLog"

        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
	WHENEVER SQLERROR EXIT;
	-- WHENEVER OSERROR EXIT;
	prompt $RenameTsComm;
	$RenameTsComm;
	prompt ALTER TABLESPACE $NewTSName OFFLINE;
	ALTER TABLESPACE $NewTSName OFFLINE;
	-- !mv $RenameDir$RenameOldFile $RenameDir$RenameNewFile;
	prompt  OS command move $FullOldName $FullNewName
	!mv $FullOldName $FullNewName;
	prompt $RenameFileComm;
	$RenameFileComm;
	prompt ALTER TABLESPACE $NewTSName ONLINE;
	ALTER TABLESPACE $NewTSName ONLINE;
__EOF
	ErrorMsg1=$(grep "ORA-" $SqlLog)
	ErrorMsg2=$(grep -w "mv" $SqlLog)

        ErrorMsg="${ErrorMsg1}${ErrorMsg2}"
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error by remane tablespace, Log file: $SqlLog"
                LogError "$ErrorMsg"
                return 1
        fi


}
#---------------------------------------------
CheckDbDir ()
#---------------------------------------------
{
        LogCons "List datafile and check datafiles."
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.CheckDbDir.$$.$PPID.$TimeStampLong.log
        LogCons "Logfile: $SqlLog"

        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off
        set serveroutput on

	SELECT DECODE(r, 1, tablespace_name, null) tablespace_name, file_name
	FROM (select tablespace_name, file_name, rank() over (partition by tablespace_name
        order by tablespace_name, file_name) r
        from dba_data_files where file_name not like '${OFA_DB_DATA}/${DbName}%'
        order by tablespace_name, file_name
	);
__EOF

	if [[ -s $SqlLog ]]
	then
	# 	LogCons "ERROR: Data file(s) exist in wrong directory !!!!!!"	
	#	cat $SqlLog
		WrongDir=1
		ErrorLogDir=$OFA_LOG/tmp/SqlLog.$DbName.CheckDbDirError.$$.$PPID.$TimeStampLong.log
		cat $SqlLog > $ErrorLogDir
	fi

        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
	set feedback off
	set timing off
	
	SELECT DECODE(r, 1, tablespace_name, null) tablespace_name, file_name
	FROM (select tablespace_name, file_name, rank() over (partition by tablespace_name
        order by tablespace_name, file_name) r
        from dba_data_files
        order by tablespace_name, file_name
	);
__EOF

ErrorMsg=$(grep "ORA-" $SqlLog)
        if [[ ! -z "$ErrorMsg" ]]
        then
                LogError "Error getting , Log file: $SqlLog"
                LogError "$ErrorMsg"
	else 
		cat $SqlLog
        fi

	if [[ ! -z $WrongDir ]]
	then
		echo ""
		LogError "ERROR: Data file(s) exist in wrong directory !!!!!!"
                cat $ErrorLogDir
	fi


}
#---------------------------------------------
LastObj ()
#---------------------------------------------
{
LogCons "Find last object in $TsName"
        SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.LastObj.$i.$$.$PPID.$TimeStampLong.log
        SqlScript=$OFA_LOG/tmp/SqlLog.$DbName.LastObj.$i.$$.$PPID.$TimeStampLong.sql

LogCons "Log file: $SqlLog"
        sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
        set feedback off
        set echo off
        set timing off
        set heading off
        set serveroutput on
	DECLARE

	V_COUNT        number;
	V_TS_NAME      VARCHAR2 (100):= UPPER('$TsName');
	V_OWNER        VARCHAR2 (100);
        V_SEGMENT_NAME VARCHAR2 (100);
        V_SEGMENT_TYPE VARCHAR2 (100);
	V_TS_SIZE      number;
	BEGIN
	select count(*) into V_COUNT from dba_extents where tablespace_name = V_TS_NAME;
	IF V_COUNT != 0 THEN
		select owner, segment_name, segment_type
		into V_OWNER,V_SEGMENT_NAME,V_SEGMENT_TYPE
		from dba_extents a,
		(select value/1024 as value
		from v\$parameter
		where name = 'db_block_size') b
		where block_id
		=(select max(block_id)
		from dba_extents
		where tablespace_name = V_TS_NAME) and tablespace_name = V_TS_NAME;
		DBMS_OUTPUT.put_line ('Last Object in Tablespace:'||V_TS_NAME||', Owner:'||V_OWNER||', Object_name:'||V_SEGMENT_NAME||', Object_type:'||V_SEGMENT_TYPE);
	ELSE
	        select count(*) into V_COUNT from dba_tablespaces where tablespace_name = V_TS_NAME;
        IF V_COUNT != 0 THEN
                Select (sum(bytes)/1024) SIZE_KB into V_TS_SIZE from dba_data_files where tablespace_name = V_TS_NAME;
                DBMS_OUTPUT.put_line ('ERROR: Tablespace: '||V_TS_NAME||' is empty, size: '||round(V_TS_SIZE/1024)||' MB');
        ELSE
                DBMS_OUTPUT.put_line ('ERROR: Tablespace: '||V_TS_NAME||' do not exist.....');
        END IF;
END IF;
END;
/
__EOF


ErrorCheck=$(grep -e "ERROR:" -e "ORA-" $SqlLog | head -1)


if [[ ! -z $ErrorCheck ]]
then
	LogError "$ErrorCheck"
else
	echo ""	
	cat $SqlLog | LogStdInEcho 
	echo ""	
fi

}
#---------------------------------------------
# Main
#---------------------------------------------
CreTsObj
if [[ "$FuncToDo" == "Info" ]]
then
	SetReorgDir	
	ListAll 
 	ListEmptyTS
	CheckFreeSpace
	CheckDbDir
elif [[ "$FuncToDo" == "Shrink" ]]
then
        export TsName=$3
        ShrinkTs $TsName
elif [[ "$FuncToDo" == "Last" ]]
then
        export TsName=$3
        LastObj
elif [[ "$FuncToDo" == "Rename" ]]
then
        export TsName=$3
	export TsNameNew=$4
	
        RenameTS $TsName $TsNameNew
elif [[ "$FuncToDo" == "Remove" ]]
then
	export TsName=$3
	RemoveEmptyTS	
elif [[ "$FuncToDo" == "Reorg" ]]
then
	SetReorgDir
        export TsName=$3
	ForceGo=$(echo $3 | grep  Force)
	TsName=$(echo $3 | sed 's/_Force//g')
	if [[ -z $(echo $4 | grep ReorgDir) ]]
	then
		export TsNameTarget=$4
	fi
	# export TsNameTarget=$4
	LogCons "Function: $FuncToDo"
	LogCons "Database: $DbName" 
        if [[ ! -z $ForceGo ]]
	then
		LogCons "Force: ON"
	else 
		 LogCons "Force: OFF"
        fi
	LogCons "TsName: $TsName"
	# LogCons "Target TS's: $TsNameTarget"
        ReorgTS 
        ListAll
	CheckDbDir
        CheckFreeSpace
elif [[ "$FuncToDo" == "Move" ]]
then
        SetReorgDir
        export TsName=$3
        ForceGo=$(echo $3 | grep  Force)
        TsName=$(echo $3 | sed 's/_Force//g')
        if [[ -z $(echo $4 | grep ReorgDir) ]]
        then
                export TsNameTarget=$4
        fi
        # export TsNameTarget=$4
        LogCons "Function: $FuncToDo"
        LogCons "Database: $DbName"
        if [[ ! -z $ForceGo ]]
        then
                LogCons "Force: ON"
        else
                 LogCons "Force: OFF"
        fi
        LogCons "TsName: $TsName"
        # LogCons "Target TS's: $TsNameTarget"
        ReorgTS
        ListAll
        CheckDbDir
        CheckFreeSpace
else 
	usage
fi

