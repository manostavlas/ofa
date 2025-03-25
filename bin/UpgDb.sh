#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"

TimeStampLong=$(date +"%y%m%d_%H%M%S")
TimeStamp=$(date +"%H%M%S")
DbName=$1
ToHome=$2
HostToUpgrade=$3
UpgDir=$OFA_DB_VAR/$DbName/upg
UpgCfgFile=$UpgDir/Upg_${DbName}.cfg
UpgCfgFileAnalyze=$UpgDir/Upg_${DbName}_Analyze.cfg
UpgCfgFileInitAddAfter=$UpgDir/Upg_${DbName}_init.cfg
UpgCfgFileChecklist=$UpgDir/Upg_${DbName}_checklist.cfg
TmpLogFile=${UpgDir}/Upg_${TimeStamp}.log
TmpLogFileTab=${UpgDir}/Upg_${TimeStamp}_tab.log
SqlLog=$OFA_LOG/tmp/SqlLog.$DbName.$$.$PPID.log

# Check var

  CheckVar DbName      		\
           ToHome       	\
           HostToUpgrade 	\
	&& LogCons "Variables OK!"    \
  || Usage


#---------------------------------------------
Usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: UpgDb.sh  [SID] [TO_HOME] [HOST_NAME]
##
## Parameters:
##
## SID               Database Name to Upgrade. 
##
## TO_HOME           New home of the database.
##
## HOST_NAME	     Name of the host (Sometimes with domain name.)
#
__EOF
}
#---------------------------------------------
Analyze ()
#---------------------------------------------
{
LogCons "Runing Analyze on Database: $DbName"
LogCons "Log directory: ${UpgDir}"
LogCons "       Command:$ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFileAnalyze} -mode analyze -noconsole"
$ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFileAnalyze} -mode analyze -noconsole 2>&1 | tee $TmpLogFile | LogStdInEcho

JobNumber=$(grep -i -w job ${TmpLogFile} | head -1 | awk '{print $2}')

CheckError=$(grep ERROR ${TmpLogFile})

echo "TmpLogFile: $TmpLogFile"
echo "JobNumber:$JobNumber"

JobLogDir="${UpgDir}/${DbName}/${JobNumber}"
echo "JobLogDir: $JobLogDir"
echo ""
LogCons "Log directory for the Job: ${JobLogDir}"
echo ""
LogCons "Log files:"
ls -lpd ${JobLogDir}/* | grep -v drwx | awk '{print $9}' | LogStdInEcho 
echo ""
LogCons "Prechecks files:"
ls -lpd ${JobLogDir}/prechecks/* | awk '{print $9}' | LogStdInEcho
LogCons "Check list file config file:"
PreUpgCfgFile=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')*_checklist.cfg
cp $PreUpgCfgFile $UpgCfgFileChecklist
echo "$UpgCfgFileChecklist"
echo ""
if [[ ! -z $CheckError ]]
then
	print "$REVON ERROR: $REVOFF"
	LogError "Check logfile: ${TmpLogFile} for error(s) !!!!!!!!!!!"
fi


}
#---------------------------------------------
Fix ()
#---------------------------------------------
{
LogCons "Runing Fix on Database: $DbName"

# if [[ -z ${JobNumber} ]]
# then
#         echo "Job Number: "
#         read JobNumber
# fi
# 
# JobDir=${UpgDir}/${DbName}/${JobNumber}
# if [[ ! -d $JobDir ]]
# then
# 	LogError "Job dirctory: $JobDir don't exist" 
# 	return
# fi
# 
# PreUpgCfgFile=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')_checklist.cfg
LogCons "cfg log file: $UpgCfgFile"

if [[ ! -f $UpgCfgFile ]]
then
        LogError "cfg file: $UpgCfgFile don't exist"
        return
fi


echo "Run FIX?  (Y/N)"
read YesOrNo
if [[ $YesOrNo == Y ]] || [[ $YesOrNo == y ]]
then

	LogCons "Log directory: ${UpgDir}"
        LogCons "Config file: ${UpgCfgFile}" 
	LogCons "       Command:$ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFile} -mode fixups -noconsole"
	# $ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${PreUpgCfgFile} -mode fixups -noconsole 2>&1 | tee $TmpLogFile | LogStdInEcho
	$ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFile} -mode fixups -noconsole 2>&1 | tee $TmpLogFile | LogStdInEcho

	JobNumber=$(grep -i -w job ${TmpLogFile} | awk '{print $2}')
	JobLogDir=${UpgDir}/${DbName}/${JobNumber}

	echo ""
	LogCons "Log directory for the Job: ${JobLogDir}"
	echo ""
	LogCons "Log files:"
	ls -lpd ${JobLogDir}/* | grep -v drwx | awk '{print $9}' | LogStdInEcho
	echo ""
	LogCons "Prechecks files:"
	ls -lpd ${JobLogDir}/prechecks/* | awk '{print $9}' | LogStdInEcho
else 
	LogCons "Exit FIX."
fi
}
#---------------------------------------------
Deploy ()
#---------------------------------------------
{
LogCons "Runing Deploy on Database: $DbName"

# if [[ -z ${JobNumber} ]]
# then
#         echo "Job Number: "
#         read JobNumber
# fi
# 
# JobDir=${UpgDir}/${DbName}/${JobNumber}
# if [[ ! -d $JobDir ]]
# then
#         LogError "Job dirctory: $JobDir don't exist"
#         return
# fi

# PreUpgCfgFile=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')_checklist.cfg
# LogCons "cfg log file: $PreUpgCfgFile"

# if [[ ! -f $PreUpgCfgFile ]]
# then
#         LogError "cfg file: $PreUpgCfgFile don't exist"
#         return
# fi


echo "Run Deploy?  (Y/N)"
read YesOrNo
if [[ $YesOrNo == Y ]] || [[ $YesOrNo == y ]]
then
	TimeStampLongTab=$(date +"%y%m%d_%H%M%S")
        LogCons "Log directory: ${UpgDir}"
        LogCons "Config file: ${UpgCfgFile}"
	echo ""
        LogCons "Create tables dba_obj_bef_${TimeStampLongTab}, dba_reg_bef_${TimeStampLongTab}" 
        echo ""
	DoSqlQ "create table dba_obj_bef_${TimeStampLongTab} as select owner,object_name,object_type,status from dba_objects where status <> 'VALID';"
	DoSqlQ "create table dba_reg_bef_${TimeStampLongTab} as select comp_id,comp_name,status from dba_registry where status <> 'VALID';"
	sleep 5
	LogCons "      Command: $ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFile} -mode deploy -noconsole"

        $ToHome/jdk/bin/java -jar $ToHome/rdbms/admin/autoupgrade.jar -config ${UpgCfgFile} -mode deploy -noconsole 2>&1 | tee $TmpLogFile | LogStdInEcho

	OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""	

	# LogCons "Update profiles, Running: $OFA_SQL/SetProfiles_19c.sql"
	# $OFA_SQL/SetProfiles_19c.sql

        LogCons "Create tables dba_obj_aft_${TimeStampLongTab}, dba_reg_aft_${TimeStampLongTab}" 
        echo ""
	DoSqlQ "create table dba_obj_aft_${TimeStampLongTab} as select owner,object_name,object_type,status from dba_objects where status <> 'VALID';"
	DoSqlQ "create table dba_reg_aft_${TimeStampLongTab} as select comp_id,comp_name,status from dba_registry where status <> 'VALID';"
	sleep 5

	LogCons "Diff tables dba_obj_bef_${TimeStampLongTab} and dba_obj_aft_${TimeStampLongTab}"
        echo ""
	DoSqlV "select * from dba_obj_aft_${TimeStampLongTab} minus select * from dba_obj_bef_${TimeStampLongTab};" 2>&1 > ${TmpLogFileTab}
	sleep 5
 	RowsSel=$(grep "rows selected" ${TmpLogFileTab} | grep "no rows selected")	
	if [[ -z $RowsSel ]]
	then
		LogError "Invalid objects after upgrade.... Check tables tables dba_obj_bef_${TimeStampLongTab} and dba_obj_aft_${TimeStampLongTab}"
	fi

	LogCons "Diff tables dba_reg_aft_${TimeStampLongTab} and dba_reg_bef_${TimeStampLongTab}"
        echo ""
        DoSqlV "select * from dba_reg_aft_${TimeStampLongTab} minus select * from dba_reg_bef_${TimeStampLongTab};" 2>&1 > ${TmpLogFileTab}
	sleep 5
 	RowsSel=$(grep "rows selected" ${TmpLogFileTab} | grep "no rows selected")	
	if [[ -z $RowsSel ]]
	then
		LogError "Invalid objects after upgrade.... Check tables: tables dba_reg_aft_${TimeStampLongTab} and dba_reg_bef_${TimeStampLongTab}"
	fi



        JobNumber=$(grep -i -w job ${TmpLogFile} | awk '{print $2}')
        JobLogDir=${UpgDir}/${DbName}/${JobNumber}
        # JobLogDir=${UpgDir}/${JobNumber}

        echo ""
        LogCons "Log directory for the Job: ${JobLogDir}"
        echo ""
        LogCons "Log files:"
        ls -lpd ${JobLogDir}/* | grep -v drwx | awk '{print $9}' | LogStdInEcho
        echo ""
        LogCons "Prechecks files:"
        ls -lpd ${JobLogDir}/prechecks/* | awk '{print $9}' | LogStdInEcho
else
        LogCons "Exit Upgrade...."
fi
}
#---------------------------------------------
CreateCfg ()
#---------------------------------------------
{
LogCons "Generate upgrade cfg file: $UpgCfgFileAnalyze "
cat << __EOF > $UpgCfgFileAnalyze
global.autoupg_log_dir=${UpgDir}
upg1.dbname=${DbName}
upg1.start_time=NOW
upg1.source_home=$(OraHomeDb)
upg1.target_home=${ToHome}
upg1.sid=${DbName}
upg1.log_dir=${UpgDir}
upg1.upgrade_node=$HostToUpgrade
upg1.restoration=no
upg1.target_version=19
upg1.drop_grp_after_upgrade=YES
# asg upgl.add_after_upgrade_pfile=$UpgCfgFileInitAddAfter
#upg1.run_utlrp=yes
#upg1.timezone_upg=yes
# New patameters
upg1.timezone_upg=no
# upg1.checklist=$UpgCfgFileChecklist
upg1.remove_underscore_parameters=yes
upg1.raise_compatible=yes
__EOF

LogCons "Generate upgrade cfg file: $UpgCfgFile "
cat << __EOF > $UpgCfgFile
global.autoupg_log_dir=${UpgDir}
upg1.dbname=${DbName}
upg1.start_time=NOW
upg1.source_home=$(OraHomeDb)
upg1.target_home=${ToHome}
upg1.sid=${DbName}
upg1.log_dir=${UpgDir}
upg1.upgrade_node=$HostToUpgrade
upg1.restoration=no
upg1.target_version=19
upg1.drop_grp_after_upgrade=YES
# asg upgl.add_after_upgrade_pfile=$UpgCfgFileInitAddAfter
#upg1.run_utlrp=yes
#upg1.timezone_upg=yes
# New patameters
upg1.timezone_upg=no
upg1.checklist=$UpgCfgFileChecklist
upg1.remove_underscore_parameters=yes
upg1.raise_compatible=yes
__EOF

LogCons "Generate upgrade init file: $UpgCfgFileInitAddAfter "
cat << __EOF > $UpgCfgFileInitAddAfter
*.compatible='19.0.0.0'
__EOF
}
#---------------------------------------------
PreUpgradeLog ()
#---------------------------------------------
{
if [[ -z ${JobNumber} ]]
then
	echo "Job Number: "
	read JobNumber
fi

JobDir=${UpgDir}/${DbName}/${JobNumber}
if [[ ! -d $JobDir ]]
then
        LogError "Job dirctory: $JobDir don't exist"
        return
fi


PreUpgLogFile=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')*_preupgrade.log
PreUpgChecklist=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')*_checklist.cfg
LogCons "Preupgrade log file: $PreUpgLogFile"
more ${PreUpgLogFile}
LogCons "Preupgrade log file: $PreUpgLogFile"
}
#---------------------------------------------
EnableFlash ()
#---------------------------------------------
{
LogCons "Enable flaschback"
DoSql $OFA_SQL/FlashBackEnable.sql 20
}
#---------------------------------------------
DisableFlash ()
#---------------------------------------------
{
LogCons "Enable flaschback"
DoSql $OFA_SQL/FlashBackDisable.sql
}

#---------------------------------------------
RemoveAllLogs ()
#---------------------------------------------
{
LogCons "Remove all logs Directory: ${UpgDir}/* "
if [[ ! -d $UpgDir ]]
then
        LogError "Log dirctory: $UpgDir don't exist"
        return
fi

rm -r ${UpgDir}/*

CreateCfg

}
#---------------------------------------------
PreUpgradeCfg ()
#---------------------------------------------
{
if [[ -z ${JobNumber} ]]
then
        echo "Job Number: "
        read JobNumber
fi
JobDir=${UpgDir}/${DbName}/${JobNumber}
if [[ ! -d $JobDir ]]
then
        LogError "Job dirctory: $JobDir don't exist"
        return
fi


# PreUpgCfgFile=${UpgDir}/${DbName}/${JobNumber}/prechecks/$(echo $DbName | awk '{print tolower($0)}')*_checklist.cfg
# LogCons "Preupgrade cfg file: $PreUpgCfgFile"
# vi ${PreUpgCfgFile}
LogCons "Preupgrade cfg file: $UpgCfgFileChecklist"
vi $UpgCfgFileChecklist
LogCons "Preupgrade cfg file: $UpgCfgFileChecklist"

}
#---------------------------------------------
UpdateAutoUpgrade ()
#---------------------------------------------
{
LogCons "Check ${ToHome}/rdbms/admin/autoupgrade.jar with ${OFA_BIN}/autoupgrade_newest.jar"
CkSumNew=$(cksum ${ToHome}/rdbms/admin/autoupgrade.jar | awk '{print $1}')
CkSumOrig=$(cksum ${OFA_BIN}/autoupgrade_newest.jar | awk '{print $1}')

LogCons "Check sum ${ToHome}/rdbms/admin/autoupgrade.jar: $CkSumNew"
LogCons "Check sum ${OFA_BIN}/autoupgrade_newest.jar: $CkSumOrig"


if [[ $CkSumNew != $CkSumOrig ]] 
then
	LogCons "Update ${ToHome}/rdbms/admin/autoupgrade.jar with ${OFA_BIN}/autoupgrade_newest.jar"
	cp ${ToHome}/rdbms/admin/autoupgrade.jar ${ToHome}/rdbms/admin/autoupgrade.jar_${TimeStampLong}
	Error01=$?
	# echo "Error01=$Error01"
	cp $OFA_BIN/autoupgrade_newest.jar ${ToHome}/rdbms/admin/autoupgrade.jar
	Error02=$?
	# echo "Error02=$Error02"
	if [[ $Error01 -ne 0 ]] || [[ $Error02 -ne 0 ]]
	then
		LogError "Error copy autoupgrade.jar file" 
		return
	fi
	LogCons "${ToHome}/rdbms/admin/autoupgrade.jar updated !"
else
	LogCons "${ToHome}/rdbms/admin/autoupgrade.jar OK!"
fi
}
#---------------------------------------------
PreSetup ()
#---------------------------------------------
{
LogCons "Create network links"

FilesToLink="listener.ora tnsnames.ora sqlnet.ora"

LogCons "Files to link: $FilesToLink"

for i in $FilesToLink 
do 
	if [[ ! -L $ToHome/network/admin/$i ]]
	then
		LogCons "Create link $ToHome/network/admin/$i"
		cd $ToHome/network/admin
		ln -sf $OFA_TNS_ADMIN/$i
	else
		LogCons "Link exist: $ToHome/network/admin/$i"
	fi
done

if [[ ! -L $ToHome/network/admin/ldap.ora ]] && [[ $(HostType) == PRD ]]
then
	LogCons "Create link $ToHome/network/admin/ldap.ora"
	cd $ToHome/network/admin
	ln -sf $OFA_TNS_ADMIN/ldap.ora
fi

LogCons "Create file mgwu121.sql if don't exist"
if [[ ! -r $ToHome/mgw/admin/mgwu121.sql ]]
then
	echo "prompt Work around for MGW bug (28785273) during upgrade……" > $ToHome/mgw/admin/mgwu121.sql
else 
	LogCons "File exist $ToHome/mgw/admin/mgwu121.sql"
fi


LogCons "Check if $ORACLE_HOME/dbs/orapw${ORACLE_SID}"
if [[ ! -r $ORACLE_HOME/dbs/orapw${ORACLE_SID} ]]
then
        LogError "File: $ORACLE_HOME/dbs/orapw${ORACLE_SID} don't exist"
else
        LogCons "OK, File: $ORACLE_HOME/dbs/orapw${ORACLE_SID} exist"
fi

EmptyRecycBin

LogCons "Stop listener....."
ListStartStop.sh stop ${ORACLE_SID} > /dev/null 2>&1

}
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
PostSetup ()
#---------------------------------------------
{
LogCons "Running: CreLinkHome.sh $DbName "
$OFA_BIN/CreLinkHome.sh $DbName

LogCons "Recreate PWD Functions"
DoSql "drop function SYS.F_VERIFY_USRPWD;"
DoSql "drop function SYS.F_VERIFY_PWD;"
DoSqlQ "$OFA_SQL/SetProfiles_19c.sql"

LogCons "Recompile all objects"
DoSql "$OFA_SQL/recompile.sql"
LogCons "List Invalid objects"
DoSql "select owner, object_name from dba_objects where status <> 'VALID';"



CompPara=$(DoSqlQ "select substr(value,1,6) from v\$parameter where name = 'compatible';")
DbVersion=$(DoSqlQ "select substr(version,1,6) from v\$instance;")

if [[ "$CompPara" != "$DbVersion" ]]
then
	LogCons "Database version: *$DbVersion*"
	LogError "Wrong value of the init parameter: compatible value: *$CompPara*"
else
	LogCons "init parameter: compatible OK!"
	LogCons "compatible: $CompPara"
	LogCons "Database version: $DbVersion"
fi

LogCons "Start listner....."
ListStartStop.sh start ${ORACLE_SID} > /dev/null 2>&1
tnsping ${ORACLE_SID}
echo " "
print "$REVON**************************************** Manual task to do: **************************************** $REVOFF"
print ""
print "1) If a CDB/PDB database need to update the /etc/oratab for the PDB, change to the new ORACLE_HOME !!"
print ""
print "2) It redhat cluster update the /etc/oratab on the other server !!!!!!"
# print "2) Restart listener(s) for the database (Standard listener, MGW listener, etc..)"
# print ""
# print "3) Check init parameter compatible (DoSql )  init parameter:" 
# print "		sq"
# print "		create pfile from spfile"
# print "		vi $ORACLE_HOME/dbs/init${ORACLE_SID}.ora"
# print "		set compatible=[MAIN_DATABASE_VERSION] set only to main version !!! (e.g. *.compatible='19.0.0.0')"
# print "		sq"
# print "		shutdown immediate" 
# print "		create spfile from pfile" 
# print "		startup" 
# print ""
# print "         Start/Restart Listener"
# print ""
# print "Press [Yes/No]"

while true;
do
    echo "All done [Yes]: "
    read response
    if [[ $response = Yes ]]
    # if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "You chose: $response"
        return 0
    else
        echo "You chose: $response"
    fi
done


}
#---------------------------------------------
InstallJava ()
#---------------------------------------------
{
# LogCons "Install JAVA"
LogCons "Log file: $SqlLog"
LogCons "Please wait ......"
sqlplus -s "/as sysdba" << __EOF > $SqlLog
ALTER PROFILE "DEFAULT" LIMIT PASSWORD_VERIFY_FUNCTION NULL;
set echo on
alter system set "_system_trig_enabled" = false scope=memory;
select obj#, name from obj$
where type#=28 or type#=29 or type#=30 or namespace=32;
@?/javavm/install/initjvm.sql
select count(*), object_type from all_objects
where object_type like '%JAVA%' group by object_type;
@?/xdk/admin/initxml.sql
select count(*), object_type from all_objects
where object_type like '%JAVA%' group by object_type;
@?/xdk/admin/xmlja.sql
select count(*), object_type from all_objects
where object_type like '%JAVA%' group by object_type;
@?/rdbms/admin/catjava.sql
select count(*), object_type from all_objects
where object_type like '%JAVA%' group by object_type;
shutdown immediate
startup
set echo off
exit
__EOF

SqlError=$(grep "ORA-" $SqlLog | head -1)

if [[ ! -z $SqlError ]]
then
        LogError "Error Install JAVA: $SqlError Log file: $SqlLog"
fi

LogCons "Recompile ......"
DoSql "$OFA_SQL/recompile.sql" >> $SqlLog 2>&1

JavaStatus=$(DoSqlQ "select '*'||comp_name, status from dba_registry where upper(comp_name) like upper('%java%');")
echo $JavaStatus | sed 's/*/\n/g'

}
#---------------------------------------------
RemoveJava ()
#---------------------------------------------
{
# LogCons "Remove JAVA"
LogCons "Log file: $SqlLog"
LogCons "Please wait ...."
SetPwFunc=$(DoSqlQ "select LIMIT from dba_profiles where profile='DEFAULT' and resource_name = 'PASSWORD_VERIFY_FUNCTION';")
sqlplus -s "/as sysdba" << __EOF > $SqlLog
spool full_rmjvm.log
set echo on
alter system set "_system_trig_enabled" = false scope=memory;
alter system enable restricted session;
@?/rdbms/admin/catnojav.sql
@?/xdk/admin/rmxml.sql
@?/javavm/install/rmjvm.sql
truncate table java$jvm$status;
select * from obj$ where obj#=0 and type#=0;
delete from obj$ where obj#=0 and type#=0;
commit;
select owner, count(*) from all_objects
where object_type like '%JAVA%' group by owner;
select obj#, name from obj$
where type#=28 or type#=29 or type#=30 or namespace=32;
select o1.name from obj$ o1,obj$ o2
where o1.type#=5 and o1.owner#=1 and o1.name=o2.name and o2.type#=29;
ALTER PROFILE "DEFAULT" LIMIT PASSWORD_VERIFY_FUNCTION $SetPwFunc;

shutdown immediate
startup
set echo off
exit
__EOF

SqlError=$(grep "ORA-" $SqlLog | head -1)

if [[ ! -z $SqlError ]]
then
        LogError "Error remove JAVA: $SqlError Log file: $SqlLog"
fi



DoSql "drop package SYS.JVMRJBCINV;" >> $SqlLog 2>&1
DoSql "drop package SYS.JAVAVM_SYS;" >> $SqlLog 2>&1


LogCons "Recompile ....."
DoSql "$OFA_SQL/recompile.sql" >> $SqlLog 2>&1


JavaStatus=$(DoSqlQ "select '*'||comp_name, status from dba_registry where upper(comp_name) like upper('%java%');")
echo $JavaStatus | sed 's/*/\n/g'

}
#---------------------------------------------
CheckRegistry ()
#---------------------------------------------
{
ErrorPreCheck=0
# ------------  Check Reg  ------------

LogCons "Check the registry" 

sqlplus -s "/as sysdba" << __EOF > $SqlLog
set echo off;
set feedback off;
set timing off;
col COMP_NAME for a40;
col VERSION for a30;
col STATUS for a30;
prompt
prompt List all comp in the registry
prompt ************************************
select COMP_NAME, VERSION, STATUS from dba_registry;


exit
__EOF

SqlError=$(grep "ORA-" $SqlLog | head -1)

if [[ ! -z $SqlError ]]
then
        LogError "Error Check Registry. Error: $SqlError"
        ErrorPreCheck=1 
fi

Invalid=$(grep "INVALID" $SqlLog | head -1)
if [[ ! -z $Invalid ]]
then
        LogError "Error Invalid Comp... Logfile: $SqlLog"
        ErrorPreCheck=1
fi

cat $SqlLog
# ------------ Check JAVA is installed ------------
echo ""
LogCons "Check if JAVA is installed"

JavaInst_1=$(grep "Java Packages" $SqlLog | grep -v REMOVED)
JavaInst_2=$(grep "JAVA Virtual Machine" $SqlLog | grep -v REMOVED)

if [[ -z $JavaInst_1 ]] || [[ -z $JavaInst_2 ]]
then
	LogError "Java Packages or JAVA Virtual Machine are not installed."
	ErrorPreCheck=1
fi




echo ""
# ------------  Check invalid objects  ------------

LogCons "Checking for invalid objects"

sqlplus -s "/as sysdba" << __EOF > $SqlLog
set echo off;
set feedback off;
set timing off;

prompt
select count(*) as "Number of Invalid objects" from dba_objects where status <> 'VALID';

__EOF

NumberOfInvalid=$(cat $SqlLog | tail -1 | awk '{$1=$1};1')

# echo "NumberOfInvalid: $NumberOfInvalid"

if [[ $NumberOfInvalid != 0 ]]
then 
	LogError "Error Invalid objects (select owner,object_name,status from dba_objects where status <> 'VALID';)"
	ErrorPreCheck=1
fi

cat $SqlLog

echo ""
# ------------  Check data patch  ------------

LogCons "Check data patch"

OpatchCheck.sh $DbName Info

Error=$?
if [[ $Error != 0 ]]
then
	LogError "Error on datapatch..."
	ErrorPreCheck=1
fi

echo ""
if [[ $ErrorPreCheck != 0 ]]
then
	LogError "Error during pre check....."
	return
fi

}
#---------------------------------------------
# MAIN
#---------------------------------------------
OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""

# Check new home 
if [[ ! -d $ToHome ]]
then
	LogError "New home: $ToHome DON'T exist" 
	exit 1
fi

[[ ! -d  $UpgDir ]] && mkdir -p $UpgDir

echo ""
echo ""

CreateCfg

UpdateAutoUpgrade

typeset -r SLEEPTIME=2

REVON=$(tput smso)  # Reverse on.
REVOFF=$(tput rmso) # Reverse off.

while :
do
    # clear
    print
    print
    print "$REVON Upgrade database: $DbName to New Home: $ToHome  $REVOFF"
    print
    print
    print "\tOptions:"
    print "\t-----------------------------------------------------------------"
    print "\t1) Pre setup/clean up          Tools: 90) Enable flaschback" 
    print "\t2) Check dba_registry                 91) Disable flaschback" 
    print "\t3) Run Analyze                        92) Remove all logs" 
    print "\t4) Check Preupgrade file              93) Switch archiving OFF"
    print "\t5) Edit/Check FIX cfg file            94) Switch archiving ON"
    print "\t6) Backup Database                    95) Install JAVA"
    print "\t7) Run FIX                            96) Remove JAVA"
    print "\t8) Run Deploy"
    print "\t9) Post setup"
    print "\t10) Time zone update"
    print
#    print "\t Tools"
#    print "\t	90) Enable flaschback"
#    print "\t	91) Disable flaschback"
#    print "\t	92) Remove all logs"
#    print "\t	93) Switch archiving OFF"
#    print "\t	94) Switch archiving ON"
#    print "\t	95) Install JAVA"
#    print "\t	96) Remove JAVA"
#    print
    print "\n\tOther Options:"
    print "\t----------------"
    print "\tr) Refresh screen"
    print "\tq) Quit"
    print
    print "\tEnter your selection: r\b\c"
    read selection
    if [[ -z "$selection" ]]
        then selection=r
    fi

    case $selection in
        1)  print "\nYou selected option 1"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Runing Pre setup/clean up"
            PreSetup
            ;;
        2)  print "\nYou selected option 2"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Runing Pre Check"
            CheckRegistry
            ;;
        3)  print "\nYou selected option 3"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing Analyze"
            Analyze 
            ;;
        4)  print "You selected option 4"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Check Preupgrade file."
            PreUpgradeLog
            ;;
        5)  print "You selected option 5"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Check FIX cfg file"
            PreUpgradeCfg 
            ;;
        6)  print "You selected option 6"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Backup database: ${DbName}"
            $OFA_BIN/rman_hot_bkp.sh $DbName | LogStdInEcho
	    mv $OFA_DB_BKP/$DbName/rman $OFA_DB_BKP/$DbName/BeforeUpg_${TimeStampLong}
	    LogCons "Backup stored in $OFA_DB_BKP/$DbName/BeforeUpg_${TimeStampLong}"
            ;;
        7)  print "You selected option 7"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing FIX"
            Fix
            ;; 
        8)  print "You selected option 8"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing Deploy"
            Deploy
            ;; 
        9)  print "You selected option 9"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Post setup"
            PostSetup
            ;;
        10)  print "You selected option 10"
            # OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Update time zone"
	    $OFA_BIN/UpdTimezone.sh $DbName
            ;;

	90) print "You selected option 90"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing Enable flashback"
	    EnableFlash
	    ;; 
	91) print "You selected option 91"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing Disable flashback"
	    DisableFlash
	    ;; 
	92) print "You selected option 92"
	    OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
	    LogCons "Runing remove all logs"
	    RemoveAllLogs
            ;;
        93) print "You selected option 93"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Runing Switch Arcihive Logging OFF"
            DoSqlQ $OFA_SQL/SwitchArcLogging.sql off
            ;;
        94) print "You selected option 94"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Runing Switch Arcihive Logging ON"
            DoSqlQ $OFA_SQL/SwitchArcLogging.sql on
            ;;
        95) print "You selected option 95"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Install JAVA"
            InstallJava 
            ;;
        96) print "You selected option 96"
            OraEnv $DbName || BailOut "Failed OraEnv \"$DbName\""
            LogCons "Remove JAVA"
            RemoveJava 
            ;;


      r|R)  continue
            ;;
      q|Q)  print
            exit
            ;;
        *)  print "\n$REVON Invalid selection $REVOFF"
            read
            ;;
    esac
done
