#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

SourceHost=$1
SourceDB=$2
TargetDB=$3
SchemaName=$4
TableName=$5
LastParameter=$6

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
##
## Usage: ExpImpTab.sh [SOURCE_HOST] [SOURCE_SID] [TARGET_SID] [SCHEMA_NAME] [TABLE_NAME]
##
##
## Paremeter:
## 
## SOURCE_HOST:		Source Host
## SOURCE_SID: 		Source database
## TARGET_SID: 		target database
## SCHEMA_NAME:		Schema name
## TABLE_NAME:		Table name
##
## Target database must be a local DB
## ssh must run between the servers without password
##
## 
#
__EOF
exit 1
}
#---------------------------------------------
ExpTab ()
#---------------------------------------------
{
	LogCons "Exporting................"
        LogCons "Running: ExpTab"
        LogCons "Setting ENV for database: $SourceDB"	
        OraEnv $SourceDB
	ExitCode=$?
	if [[ "$ExitCode" -ne 0 ]]
	then
		LogError "Database: $SourceDB don't exist...."
		exit 1
	fi
	[[ ! -d  $OFA_DB_BKP/$ORACLE_SID/datapump ]] && mkdir -p $OFA_DB_BKP/$ORACLE_SID/datapump 
        [[ -r  $OFA_DB_BKP/$ORACLE_SID/datapump/expdp.${ExpImpFile}.dmp ]] && rm $OFA_DB_BKP/$ORACLE_SID/datapump/expdp.${ExpImpFile}.dmp 
	DoSql "create or replace directory EXP_TAB_DIR as '/backup/$ORACLE_SID/datapump';"
	expdp \'/ as sysdba\' TABLES =${SchemaName}.${TableName} directory=EXP_TAB_DIR dumpfile=expdp.${ExpImpFile}.dmp logfile=expdp.${ExpImpFile}.log

}
#---------------------------------------------
ImpTab ()
#---------------------------------------------
{

        OraEnv $TargetDB
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $TargetDB don't exist...."
                exit 1
        fi
        [[ ! -d  $OFA_DB_BKP/$ORACLE_SID/datapump ]] && mkdir -p $OFA_DB_BKP/$ORACLE_SID/datapump
        DoSql "create or replace directory EXP_TAB_DIR as '/backup/$ORACLE_SID/datapump';"
        impdp \'/ as sysdba\' TABLES=${SchemaName}.${TableName} directory=EXP_TAB_DIR dumpfile=expdp.${ExpImpFile}.dmp logfile=impdp.${ExpImpFile}.log TABLE_EXISTS_ACTION=TRUNCATE
}
#---------------------------------------------

# set -xv

    LogIt "Check variable completeness"
    CheckVar                       \
        SourceDB                   \
	SourceHost		   \
        TargetDB                   \
        SchemaName                 \
	TableName		   \
     && LogIt "Variables complete" \
     || usage 

# Check ssh connection
LogCons "Check ssh connection......."
SshStatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1 | grep "ok")

SshStatusText=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $SourceHost echo ok 2>&1)


if [[ -z "$LastParameter" ]]
then
	if [[ -z "$SshStatus" ]]
		then
		LogError "Can't connect to $SourceHost !" 
		LogCons "SSH connection status: $SshStatusText"
		ErrorPW=$(echo $SshStatusText| grep "Permission denied")
		if [[ ! -z "$ErrorPW" ]]
		then
			LogCons "Copy the pub key to $SourceHost:"
			LogCons "cat ~/.ssh/id_rsa.pub | ssh dba@$SourceHost \"umask 077;cat >> ~/.ssh/authorized_keys\""
		fi
		exit 1
	else
		LogCons "SSH connection status: $SshStatus"
	fi 
fi

ExpImpFile="$SourceDB.$SchemaName.$TableName"

if [[ $LastParameter == "EXP" ]] 
then
	ExpTab
        exit
elif [[ $LastParameter == "IMP" ]]
then
	ExpImp
        exit
fi
	ExpImpCom=$(ssh dba@${SourceHost} "find /ofa -name ExpImpTab.sh")
	echo "ExpImpCom: $ExpImpCom"
	# Command=$(echo ExpImpTab.sh $SourceHost $SourceDB $TargetDB $SchemaName $TableName EXP)
	Command=$(echo $ExpImpCom $SourceHost $SourceDB $TargetDB $SchemaName $TableName EXP)
	LogCons "Running: $Command On host ${SourceHost}"
	# ssh dba@${SourceHost} "source ~/.bashrc ; $OFA_BIN/$Command"
	# ssh dba@${SourceHost} "source ~/.bash_profile ; $OFA_BIN/$Command"
	ssh dba@${SourceHost} "source ~/.bash_profile ; $Command"
        LogCons "Copy dump file: expdp.${ExpImpFile}.dmp from server: $SourceHost"
	LogCons "Target dir.: $OFA_DB_BKP/$TargetDB/datapump"
	scp dba@$SourceHost:$OFA_DB_BKP/$SourceDB/datapump/expdp.${ExpImpFile}.dmp $OFA_DB_BKP/$TargetDB/datapump
	LogCons "Imp expdp.${ExpImpFile}.dmp to $TargetDB"
	ImpTab
