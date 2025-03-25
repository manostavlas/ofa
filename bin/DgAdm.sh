#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

FuncToDo=$(echo "$(echo "$1" | tr "[A-Z]" "[a-z]" | sed 's/.*/\u&/')")
LogCons "Running function: $FuncToDo"

TimeStamp=$(date +"%H%M%S")
DgmgrlLog=$OFA_LOG/tmp/DgAdm.DgmgrlLog.$FuncToDo.$$.$PPID.$TimeStamp.log
SqlLog=$OFA_LOG/tmp/DgAdm.SqlLog.$FuncToDo.$$.$PPID.$TimeStamp.log
ShhLog=$OFA_LOG/tmp/DgAdm.ShhLog.$FuncToDo.$$.$PPID.$TimeStamp.log
RmanLog=$OFA_LOG/tmp/DgAdm.RmanLog.$FuncToDo.$$.$PPID.$TimeStamp.log
RmanExecRmanCopyPrimToStb=$OFA_LOG/tmp/DgAdm.RmanExecRmanCopyPrimToStb.$$.$PPID.$TimeStamp.rman
RemoteSqlScript=$OFA_LOG/tmp/DgAdm.RemoteSqlScript.$$.$PPID.$TimeStamp.sql
OnHost=$(uname -n)

LogCons "Running on host (uname -n): $OnHost"
RunMmDp

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DgAdm.sh [FUNCTION] [FUNCTION_PARAMETERS]
##
## Function:            Parameters:
##
## Login                [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Login in to data guard.
##
## Status               [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Get Status
##
## StatusL              [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Get long Status.
##
## GetConfDg            [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Show data gurad configuration.
##
## ShowFastSw           [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Show Fast-Start Failover status/configuration.
##
## SwOver               [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Switch over the primary database to the other server.
##
## DropPrimConf         [DbSid] (Database name)
##                      Remove DG configuration from database.
##
## DropStbForceOnly     [DbSid] (Database name)
##                      Shutdown DB,  remove Database.
##
## DropStbForce         [DbSid] (Database name)
##                      Shutdown DB, Removing broker, Database, DB config files.
##
## ConfPrimDb           [ORACLE_SID] (Database name.)
##                      Config data guard and create standby database.
##
## Validate             [UniSid] (DB_UNIQUE_NAME, Unique database name)
##                      Performs an exhaustive set of validations for a database.
##
## RebuildStbOnly       [DbSid] (Database name)
##                      [Hostname] (VIP host name where the standby DB are running)
##                      <Number> Number of channels to use of RMAN copy to standby server.
##                      Run Only from Primary server !!!!
##                      Only rebuild the standby....
##
## RebuildStb           [DbSid] (Database name)
##                      [Hostname] (VIP host name where the standby DB are running)
##                      <Number> Number of channels to use of RMAN copy to standby server.
##                      Config PRIMANY and STANDBY DB's
##                      Primary will be restarted !!!!!
##                      Run Only from Primary server !!!!
##                      Running function: DropStbForce, DropPrimConf, ConfPrimDb
##
## Failover             [DbSidUni] Unique DB name of the standby.
##                      Changes a standby database to be the primary database
##
## Reinstate            [UniSid] Unique DB name of the Primary.
##                      [ReiSid] Unique DB name of the database to Reinstate.
##                      Changes a database marked for reinstatement into a viable standby.
#
__EOF
#  Functions only used "internal" in the script.
#
# DropStbConf           [UniSid] (DB_UNIQUE_NAME, Unique database name)
#                       Remove dataguard config from primary and remove the standby database.
#
# DropStbRemote [UniSid] (DB_UNIQUE_NAME, Unique database name)
#                       [Hostname] (VIP host name where the standby DB are running)
#
# ConfStandbyDb [DbSid] (General DB name.)
#                       [DbSidUni] Unique DB name of the standby.
#
}

#---------------------------------------------
LogIn ()
#---------------------------------------------
{
  CheckVar UniSid         \
  || Usage

CheckLogIn=$1

if [[ -z $CheckLogIn ]]
then
#       LogCons "Login to :$UniSid"
        dgmgrl sys/${MmDp}@${UniSid}
        exit
else
        dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
        exit;
__EOF
        DgmgrlErr=$(grep ORA- $DgmgrlLog)

        if [[ ! -z $DgmgrlErr ]]
        then
                echo "ERROR"
        else
                echo "SUCCESS"
        fi
fi

}
#---------------------------------------------
Validate ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage

dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
VALIDATE DATABASE VERBOSE '${UniSid}';
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
Failover ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage

LogCons "Activate standby database $UniSid as Primary"


DatabaseType=$(GetStatus | grep standby | awk '{print $1}')
LogCons "Standby database name: $DatabaseType"

if [[ "$UniSid" != "$DatabaseType" ]]
then
        LogError "Database: $UniSid are not a standby database"
        exit 1
fi

dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
FAILOVER TO "${UniSid}" IMMEDIATE;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
Reinstate ()
#---------------------------------------------
{
  CheckVar UniSid \
           ReiSid \
  || Usage

LogCons "Reinstate the database: $ReiSid"

dgmgrl -silent sys/${MmDp}@$UniSid "show configuration" | tee -a $DgmgrlLog
PrimaryDB=$(grep -i primary $DgmgrlLog | grep -v ORA-)
StandbyDB=$(grep -i standby $DgmgrlLog | grep -v ORA-)

LogCons "Primary database: $PrimaryDB"
LogCons "Standby database: $StandbyDB"


if [[ $(echo $PrimaryDB | awk '{print $1}') != $UniSid ]]
then
        LogError "Database $UniSid are not an Primary database !!!"
        LogCons "Log File: $DgmgrlLog"
        exit 1
fi

dgmgrl -silent sys/${MmDp}@$UniSid "REINSTATE DATABASE '$ReiSid'" | tee -a $DgmgrlLog

Error=$(grep "ORA-" $DgmgrlLog)

if [[ ! -z $Error ]]
then
        LogError "Error Reinstate the database: $ReiSid"
        LogCons "Log File: $DgmgrlLog"
fi

}
#---------------------------------------------
ShowFastSw ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage

dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
show fast_start failover;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
GetStatus ()
#---------------------------------------------
{
  CheckVar UniSid  \
  || Usage



LoopCount=0
LoopNumber=11

while (( $LoopCount < $LoopNumber ))
do
        dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
        show configuration;
        exit;
__EOF

        LoopError=$(grep ORA- $DgmgrlLog)
# LoopError=$(grep Disabled $DgmgrlLog)

        if [[ ! -z $LoopError ]]
        then
                LogCons "Sync DB's Please wait....($LoopCount)"
                # echo "Please wait....($LoopCount)"
                sleep 30
                let LoopCount=$LoopCount+1
        else
                LoopCount=$LoopNumber
        fi
done

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
        exit 1
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
GetStatusL ()
#---------------------------------------------
{
  LogCons "Checking variables."
  CheckVar                   \
        UniSid         \
  && LogCons "Variables OK!" \
  || Usage

# LogCons "Login to :$UniSid"
dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
show configuration verbose;
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
GetConfDg ()
#---------------------------------------------
{
  CheckVar UniSid \
  || Usage

# LogCons "Login to :$UniSid"
dgmgrl -silent sys/${MmDp}@${UniSid} << __EOF > $DgmgrlLog
show database verbose '${UniSid}';
exit;
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error running function: $FuncToDo, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        cat $DgmgrlLog
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
CheckSwOverReady ()
#---------------------------------------------
{
UniSidOld=$UniSid
UniSid=$PrimDb
ReadyToSwitchPrim=$(Validate | grep "Ready for Switchover" | awk -F ":" '{print $2}' | tr -d ' ')
LogCons "Primary, Ready for Switchover: $ReadyToSwitchPrim"

UniSid=$StanDb
ReadyToSwitchStan=$(Validate | grep "Ready for Switchover" | awk -F ":" '{print $2}' | tr -d ' ')
LogCons "Standby, Ready for Switchover: $ReadyToSwitchStan"

UniSid=$UniSidOld


}
#---------------------------------------------
SwOver ()
#---------------------------------------------
{

  CheckVar UniSid         \
  || Usage

# LogCons "Login to :$UniSid"
PrimDb=$(GetStatus | grep "Primary database" | awk '{print $1}')
LogCons "Primary database: $PrimDb"
StanDb=$(GetStatus | grep "standby database" | awk '{print $1}')
LogCons "Standby database: $StanDb"
Status=$(GetStatus | grep  -A 1 "Configuration Status" | tail -1 | awk '{print $1}')
LogCons "Configuration Status: $Status"

if [[ "$Status" != "SUCCESS" ]]
then
        LogError "Configuration Status: $Status"
        exit 1
fi

OldUniSid=$UniSid

Loop="${PrimDb} ${StanDb}"
for i in ${PrimDb} ${StanDb}
do
        UniSid=$i
        CheckSb=$(LogIn check)
        if [[ "$CheckSb" != "SUCCESS" ]]
        then
                LogError "Can't connect to $i, Status: $CheckSb, Log:$DgmgrlLog"
        else
                LogCons "Connect to $i, Status: $CheckSb"
        fi
done

# Switching

LogCons "Switching from $PrimDb to $StanDb"
LogCons "Login to: $StanDb"
LogCons "Log: $DgmgrlLog"


i=5

while [[ $i -gt 0 ]];do
CheckSwOverReady
if [[ "$ReadyToSwitchPrim" != "Yes" ]] || [[ "$ReadyToSwitchStan" != "Yes" ]]
then
        # LogError "Primary, Ready for Switchover: $ReadyToSwitchPrim"
        # LogError "Standby, Ready for Switchover:: $ReadyToSwitchStan"
        LogError "Primary/Standby are not read for switch....."
        LogCons "Wait 30 ($i)"
        sleep 30
        let i-=1
        if [[ $i == 0 ]]
        then
                LogError "Primary/Standby are not read for switch....."
                exit 1
        fi
else
        i=0
fi
done

echo ""
echo "Switchover running......."
echo ""

dgmgrl -silent sys/${MmDp}@$StanDb "switchover to '$StanDb'" | tee -a $DgmgrlLog

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error switching from $PrimDb to $StanDb Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
#       cat $DgmgrlLog
fi

echo ""
echo "Get status......."
echo ""
echo "Please wait......" ; sleep 10
echo ""

UniSid=$StanDb
GetStatus
}
#---------------------------------------------
DropPrimConf ()
#---------------------------------------------
{
LogCons "Drop Primary DG configuration"
  CheckVar DbSid       \
  || Usage

OraEnv $DbSid

>$SqlLog

DoSqlQ "select value from v\$parameter where name like 'dg_broker_config_file%';"  > $SqlLog

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error getting dg file info: $PrimDb Error: $SqlErr"
        LogError "Log: $SqlLog"
        exit 1
fi

for i in $(cat $SqlLog)
do
        LogCons "Remove file: $i"
        rm -f $i >> $ShhLog 2>&1
        if [[ $? -ne 0 ]]
        then
                LogError "Error Remove file: $i"
        fi
done

# LogCons "remove files in $OFA_BRO_ADMIN/$DbSid"
# rm -f $OFA_BRO_ADMIN/$DbSid/dr*.dat

DoSqlQ "alter system set dg_broker_start=FALSE;" > $SqlLog

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error Stopping Broker on: $PrimDb Error: $SqlErr"
        LogError "Log: $SqlLog"
fi

LogCons "Set log_archive_dest_2 to '' "
LogCons "Log file: $SqlLog"

DoSql "select * from v\$parameter where NAME = 'log_archive_dest_2';" > $SqlLog
DoSql "alter system set log_archive_dest_2='' scope=both;" >> $SqlLog
DoSql "select * from v\$parameter where NAME = 'log_archive_dest_2';" >> $SqlLog

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error set log_archive_dest_2 on: $PrimDb Error: $SqlErr"
        LogError "Log: $SqlLog"
fi

DoSql "shutdown immediate;"
DoSql "startup"

}
#---------------------------------------------
DropStbConf ()
#---------------------------------------------
{
LogCons "Drop Standby"
  CheckVar UniSid       \
  || Usage

PrimDb=$(GetStatus | grep "Primary database" | awk '{print $1}')
CheckVar PrimDb || BailOut "Error in GetStatus"
LogCons "Primary database: $PrimDb"
StanDb=$(GetStatus | grep "standby database" | awk '{print $1}')
LogCons "Standby database: $StanDb"
Status=$(GetStatus | grep  -A 1 "Configuration Status" | tail -1 | awk '{print $1}')
LogCons "Configuration Status: $Status"

UniSidOrig=$UniSid

# Get VIP primary
UniSid=$PrimDb
VipPrimDb=$(GetConfDg | grep StaticConnectIdentifier | awk -F "HOST" '{print $2}' | awk -F ")" '{print $1}' | sed 's/=//g')
LogCons "Primary DB VIP: $VipPrimDb"

# Get VIP Standby
UniSid=$StanDb
VipStanDb=$(GetConfDg | grep StaticConnectIdentifier | awk -F "HOST" '{print $2}' | awk -F ")" '{print $1}' | sed 's/=//g')
LogCons "Standby DB VIP: $VipStanDb"

LogCons "Remove Broker configuration"

# Drop config (Primary).
>$DgmgrlLog
dgmgrl -silent sys/${MmDp}@$PrimDb "remove configuration;" | tee -a $DgmgrlLog

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error switching from $PrimDb to $StanDb Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
else
        cat $DgmgrlLog
fi

# Remove dg config files

LogCons "Delete Broker files. (Primary)"
sqlplus -s system/$MmDp@$PrimDb << __EOF > $SqlLog
set heading off;
set feedback off;
set timing off;
select value from v\$parameter where name like 'dg_broker_config_file%';
exit;
__EOF

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error getting dg file info: $PrimDb Error: $SqlErr"
        LogError "Log: $SqlLog"
fi

> $ShhLog
LogCons "Log file: $ShhLog"
for i in $(cat $SqlLog)
do
        LogCons "Remove file: $i On Server: $VipPrimDb"
        ssh -q -o "StrictHostKeyChecking no" $VipPrimDb rm $i >> $ShhLog 2>&1
        if [[ $? -ne 0 ]]
        then
                LogError "Error Remove file: $i On Server: $VipPrimDb"
        fi
done

# Stop broker

LogCons "Stop Broker on primary."

sqlplus -s system/$MmDp@$PrimDb << __EOF > $SqlLog
set heading off;
set feedback off;
set timing off;
alter system set dg_broker_start=FALSE;
exit;
__EOF

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error Stopping Broker on: $PrimDb Error: $SqlErr"
        LogError "Log: $SqlLog"
fi


DropStbRemote $StanDb $VipStanDb


}
#---------------------------------------------
DropStbForceOnly ()
#---------------------------------------------
{
LogCons "Drop Standby (Force)"
  CheckVar DbSid       \
           OFA_BRO_ADMIN \
  || Usage

OraEnv $DbSid

DoSqlQ "shutdown abort;"

# LogCons "Delete Broker files."
# rm -f ${OFA_BRO_ADMIN}/${DbSid}/*
LogCons "Remove database file."
rm -f /DB/${DbSid}/*.*
rm -f /DB/${DbSid}/*/*.*
rm -f /DB/${DbSid}_PDB/*.*
rm -rf /arch/${DbSid}_??/*
rm -f /arch/${DbSid}/*.*
# rm -f $ORACLE_HOME/dbs/*${DbSid}*
}
#---------------------------------------------
DropStbForce ()
#---------------------------------------------
{
LogCons "Drop Standby (Force)"
  CheckVar DbSid       \
           OFA_BRO_ADMIN \
  || Usage

OraEnv $DbSid

DoSqlQ "shutdown abort;"

LogCons "Delete Broker files."
rm -f ${OFA_BRO_ADMIN}/${DbSid}/*
LogCons "Remove database file."
rm -f /DB/${DbSid}/*.*
rm -f /DB/${DbSid}/*/*.*
rm -f /DB/${DbSid}_PDB/*.*
rm -rf /arch/${DbSid}_??/*
rm -f /arch/${DbSid}/*.*
rm -f $ORACLE_HOME/dbs/*${DbSid}*
}
#---------------------------------------------
RebuildStbOnly ()
#---------------------------------------------
{

DbName=$1
StandbyServer=$2

LogCons "Rebuild ONLY standby database, Rebuild: $DbName, Server: $StandbyServer"
  CheckVar StandbyServer       \
        DbName        \
  || Usage

LogCons "Drop standby database."
LogCons "Log file: $ShhLog"

ssh -q -o "StrictHostKeyChecking no" $StandbyServer "date" > $ShhLog
Error=$?
if [[ "$Error" -ne "0" ]]
then
        LogError "Can't connect to standby server: $StandbyServer"
        exit 1
fi

ssh -q -o "StrictHostKeyChecking no" $StandbyServer ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; DgAdm.sh DropStbForceOnly $DbName " > $ShhLog 2>&1

LogCons "Log file DropStbForceOnly: $ShhLog"


# Set up standby database.
OraEnv $DbSid


IpAdd01=$(nslookup ${DbSid}01-vip | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
IpAdd02=$(nslookup ${DbSid}02-vip | grep -A 1 "Name:" | tail -1 | awk '{print $2}')

HostName01=$(ssh -q -o "StrictHostKeyChecking no" $IpAdd01 "hostname")
HostName02=$(ssh -q -o "StrictHostKeyChecking no" $IpAdd02 "hostname")

HostInfo="${DbSid}01-vip:$IpAdd01:$HostName01 ${DbSid}02-vip:$IpAdd02:$HostName02"
ServerInfo01="VIP:${DbSid}01-vip,IP:$IpAdd01,HOST:$HostName01,SERVER_NO:01"
ServerInfo02="VIP:${DbSid}02-vip,IP:$IpAdd02,HOST:$HostName02,SERVER_NO:02"


# LogCons "Server Info: $HostInfo"
LogCons "Server 01: $ServerInfo01"
LogCons "Server 02: $ServerInfo02"


# Check Server info
LogCons "Check Server name"
LogCons "Host name: $OnHost"

for i in "$ServerInfo01" "$ServerInfo02"
do
        TmpInfo=$(echo $i | grep $OnHost)
        if [[ ! -z $TmpInfo ]]
        then
                LocalServerInfo=$TmpInfo
                LogCons "Server Local Info: $LocalServerInfo"
        fi

        TmpInfo=$(echo $i | grep -v $OnHost)
        if [[ ! -z $TmpInfo ]]
        then
                RemoteServerInfo=$TmpInfo
                LogCons "Server Remote Info: $RemoteServerInfo"
        fi

done

if [[ -z $LocalServerInfo ]]
then
        LogError "Wrong server, VIP ${DbSid}01-vip or ${DbSid}02-vip don't exist on the server."
        exit 1
fi

LogCons "Local Server: $LocalServerInfo"
LogCons "Remote Server: $RemoteServerInfo"

LocalServerNo=$(echo $LocalServerInfo | awk -F ":" '{print $5}')
RemoteHostVip=$(echo $RemoteServerInfo | awk -F ":" '{print $2}' | awk -F "," '{print $1}')
RemoteServerNo=$(echo $RemoteServerInfo | awk -F ":" '{print $5}')


PrimDbUni=${DbSid}_${LocalServerNo}
StbDbUni=${DbSid}_${RemoteServerNo}

PrimVip=$(echo "${DbSid}${LocalServerNo}-vip" | awk '{print tolower($0)}')
StbVip=$(echo "${DbSid}${RemoteServerNo}-vip" | awk '{print tolower($0)}')

LogCons "Primary UNIQUE name: $PrimDbUni"
LogCons "Standby UNIQUE name: $StbDbUni"
LogCons "Primary vip: $PrimVip"
LogCons "Standby vip: $StbVip"


# Check DB role.

LogCons "Check DB role."
DbRole=$(OraDBRole | awk -F ":" '{print $1}')
if [[ "$DbRole" != "PRIMARY" ]]
then
        LogError "Wrong Role database should be "PRIMARY" be are :$DbRole"
        exit 1
else
        LogCons "DB Role: $DbRole"
fi





LogCons "Copy DB config files to: $RemoteHostVip"

scp $ORACLE_HOME/dbs/spfile${ORACLE_SID}.ora $RemoteHostVip:$ORACLE_HOME/dbs/
scp $ORACLE_HOME/dbs/orapw${ORACLE_SID} $RemoteHostVip:$ORACLE_HOME/dbs/

LogCons "Call DgAdm.sh Confstandbydb ${DbSid} ${StbDbUni} on remote server $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; DgAdm.sh ConfStandbyDb ${DbSid} ${StbDbUni}"

# Copy primary to Standby
CopyPrimToStb

# Config standby
LogCons "Create script: $RemoteSqlScript on server: $RemoteHostVip"
echo "alter system set dg_broker_start = TRUE scope=both;" > $RemoteSqlScript
echo "alter database flashback on;" >> $RemoteSqlScript
echo "ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;" >> $RemoteSqlScript
echo "select flashback_on from v\$database;" >> $RemoteSqlScript
echo "show parameter dg_broker_start;" >> $RemoteSqlScript
cat $RemoteSqlScript | ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip "cat >> $RemoteSqlScript"
LogCons "Running "$RemoteSqlScript" on $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DbSid ; DoSqlQ "$RemoteSqlScript"" > $ShhLog 2>&1

ErrorSsh=$(grep ORA- $ShhLog)

if [[ ! -z $ErrorSsh ]]
then
        LogError "Error running: $RemoteSqlScript, Error: $ShhLog"
        LogError "Log: $ShhLog"
        cat $ShhLog
        exit 1
else
        cat $ShhLog
fi

echo "Please wait......" ; sleep 30
echo ""

LogCons "Reset APPLY-ON...."
dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
edit database '${StbDbUni}' set state='APPLY-OFF';
edit database '${StbDbUni}' set state='APPLY-ON';
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog )

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error APPLY-ON, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
fi

CopyTempFiles

LoopCount=0
LoopNumber=11
while (( $LoopCount < $LoopNumber ))
do

        echo "Please wait......" ; sleep 30
        echo ""

        # echo "****************** READ ******************"
        # read

        LogCons "List status/configuration. ($LoopCount)"
        dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
        show configuration verbose;
        show database verbose '${PrimDbUni}';
        show database verbose '${StbDbUni}';
__EOF

        DgmgrlErr=$(grep ORA- $DgmgrlLog )
        if [[ ! -z $DgmgrlErr ]]
        then
                let LoopCount=$LoopCount+1
        else
               LoopCount=$LoopNumber
        fi
done



if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error status/configuration, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
else
        cat $DgmgrlLog
fi
}
#---------------------------------------------
CopyTempFiles ()
#---------------------------------------------
{
        LogCons "Copy tempfiles to standby..."
        sqlplus -s sys/$MmDp@$DbName as sysdba << __EOF > $SqlLog
        set heading off;
        set feedback off;
        set timing off;
        select 'TEMP_FILE_NAME: '||file_name from dba_temp_files;
        select 'PDB_NAMES: '||pdb_name from DBA_PDBS;
exit;
__EOF

sed -i '/^$/d' $SqlLog
cat  $SqlLog



for i in $(cat $SqlLog | grep PDB_NAMES | awk '{print $2}')
do
        echo "Database name $i"
        sqlplus -s sys/$MmDp@$DbName as sysdba << __EOF >> $SqlLog
        set heading off;
        set feedback off;
        set timing off;
        alter session set container=$i;
        select 'TEMP_FILE_NAME: '||file_name from dba_temp_files;
exit
__EOF
done

SqlError=$(grep "ORA-" $SqlLog | head -1)

if [[ ! -z $SqlError ]]
then
        LogError "Error getting TEMPTABLE SPACE info: $SqlError Log file: $SqlLog"
fi


CopyFiles=$(grep TEMP_FILE_NAME $SqlLog | awk '{print $2}')
for i in $CopyFiles
do
        LogCons "Copy file: $i to $StandbyServer"
        scp -q -o "StrictHostKeyChecking=no" $i $StandbyServer:$i

        if [[ $? -ne 0 ]]
        then
                LogError "Error copy file..... "
        fi
done
}
#---------------------------------------------
RebuildStb ()
#---------------------------------------------
{
DbName=$1
StandbyServer=$2

LogCons "Rebuild standby database, Rebuild: $DbName, Server: $StandbyServer"
  CheckVar StandbyServer       \
        DbName        \
  || Usage

LogCons "Drop standby database."
LogCons "Log file: $ShhLog"

ssh -q -o "StrictHostKeyChecking no" $StandbyServer "date" > $ShhLog
Error=$?
if [[ "$Error" -ne "0" ]]
then
        LogError "Can't connect to standby server: $StandbyServer"
        exit 1
fi

ssh -q -o "StrictHostKeyChecking no" $StandbyServer ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; DgAdm.sh DropStbForce $DbName " > $ShhLog 2>&1

# LogCons "Drop prinary DG configuration."
DropPrimConf

LogCons "Config data guard and create standby database."
ConfPrimDb
}
#---------------------------------------------
DropStbRemote ()
#---------------------------------------------
{
DbName=$1
StandbyServer=$2

LogCons "Drop Standby database."
  CheckVar StandbyServer       \
        DbName        \
  || Usage

# Check if Standby database.

sqlplus -s sys/$MmDp@$DbName as sysdba << __EOF > $SqlLog
set heading off;
set feedback off;
set timing off;
select 'DB_ROLE: '||DATABASE_ROLE from v\$database;
exit;
__EOF

SqlErr=$(grep -e "ORA-" -e "SP2" $SqlLog | grep -v ORA-12514)

if [[ ! -z $SqlErr ]]
then
        LogError "Error checking DB Role: $DbName Error: $SqlErr"
        LogError "Log: $SqlLog"
fi

DbRoleCheck=$(grep STANDBY $SqlLog)
DbRole=$(grep DB_ROLE $SqlLog)

if [[ -z $DbRoleCheck ]]
then
        LogError "Error DB Role are NOT STANDBY, Role: $DbRole"
        LogError "Log: $SqlLog"
        exit 1
else
        LogCons "DB Role: $DbRole"
fi

# Shutdown database

LogCons "Shutdown Standby database"
LogCons "Logfile: $SqlLog"
sqlplus -s sys/$MmDp@$DbName as sysdba << __EOF > $SqlLog
set heading off;
set feedback off;
set timing off;
select * from v\$database;
shutdown abort;
exit;
__EOF

SqlErr=$(grep -e "ORA-" $SqlLog | grep -v ORA-12514)

if [[ ! -z $SqlErr ]]
then
        LogError "Error Shutdown abort: $DbName Error: $SqlErr"
        LogError "Log: $SqlLog"
fi

LogCons "Remove standby database files."
LogCons "Logfile: $ShhLog"
DbNameShort=$(echo ${DbName} | awk -F "_" '{print $1}')
LogCons "DB name: $DbNameShort"

ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f /DB/${DbNameShort}/*.*" > $ShhLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f /DB/${DbNameShort}/*/*.*" >> $ShhLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f /DB/${DbNameShort}_PDB/*.*" >> $ShhLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f /arch/${DbNameShort}/*.*" >> $ShhLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f /oracle/${DbNameShort}/dbs/*${DbNameShort}*" >> $ShhLog 2>&1
ssh -q -o "StrictHostKeyChecking no" $StandbyServer "rm -f ${OFA_BRO_ADMIN}/${DbNameShort}/*.dat" >> $ShhLog 2>&1

}
#---------------------------------------------
ConfPrimDb ()
#---------------------------------------------
{
LogCons "Config primary database: $DbSid"
OraEnv $DbSid


IpAdd01=$(nslookup ${DbSid}01-vip | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
IpAdd02=$(nslookup ${DbSid}02-vip | grep -A 1 "Name:" | tail -1 | awk '{print $2}')

HostName01=$(ssh -q -o "StrictHostKeyChecking no" $IpAdd01 "hostname")
HostName02=$(ssh -q -o "StrictHostKeyChecking no" $IpAdd02 "hostname")

HostInfo="${DbSid}01-vip:$IpAdd01:$HostName01 ${DbSid}02-vip:$IpAdd02:$HostName02"
ServerInfo01="VIP:${DbSid}01-vip,IP:$IpAdd01,HOST:$HostName01,SERVER_NO:01"
ServerInfo02="VIP:${DbSid}02-vip,IP:$IpAdd02,HOST:$HostName02,SERVER_NO:02"


# LogCons "Server Info: $HostInfo"
LogCons "Server 01: $ServerInfo01"
LogCons "Server 02: $ServerInfo02"


# Check Server info
LogCons "Check Server name"
LogCons "Host name: $OnHost"

for i in "$ServerInfo01" "$ServerInfo02"
do
        TmpInfo=$(echo $i | grep $OnHost)
        if [[ ! -z $TmpInfo ]]
        then
                LocalServerInfo=$TmpInfo
                LogCons "Server Local Info: $LocalServerInfo"
        fi

        TmpInfo=$(echo $i | grep -v $OnHost)
        if [[ ! -z $TmpInfo ]]
        then
                RemoteServerInfo=$TmpInfo
                LogCons "Server Remote Info: $RemoteServerInfo"
        fi

done

if [[ -z $LocalServerInfo ]]
then
        LogError "Wrong server, VIP ${DbSid}01-vip or ${DbSid}02-vip don't exist on the server."
        exit 1
fi


LogCons "Local Server: $LocalServerInfo"
LogCons "Remote Server: $RemoteServerInfo"

LocalServerNo=$(echo $LocalServerInfo | awk -F ":" '{print $5}')
RemoteServerNo=$(echo $RemoteServerInfo | awk -F ":" '{print $5}')


PrimDbUni=${DbSid}_${LocalServerNo}
StbDbUni=${DbSid}_${RemoteServerNo}

PrimVip=$(echo "${DbSid}${LocalServerNo}-vip" | awk '{print tolower($0)}')
StbVip=$(echo "${DbSid}${RemoteServerNo}-vip" | awk '{print tolower($0)}')

LogCons "Primary UNIQUE name: $PrimDbUni"
LogCons "Standby UNIQUE name: $StbDbUni"
LogCons "Primary vip: $PrimVip"
LogCons "Standby vip: $StbVip"


# Check DB role.

LogCons "Check DB role."
DbRole=$(OraDBRole)
if [[ "$DbRole" != "STANDALONE" ]]
then
        LogError "Wrong Role database should be "STANDALONE" be are :$DbRole"
        exit 1
else
        LogCons "DB Role: $DbRole"
fi

# Set PW
DoSqlQ "alter user sys identified by "$MmDp";"

# LogCons "Switch archiving on"
# DoSqlQ $OFA_SQL/SwitchArcLogging.sql on

LogCons "Create password file."
${ORACLE_HOME}/bin/orapwd file=${ORACLE_HOME}/dbs/orapw${ORACLE_SID} force=y password=$MmDp

# Activate force logging on.

LogCons "Activate force logging on."
LoggingStat=$(DoSqlQ "select force_logging from v\$database;")

if [[ "$LoggingStat" != "YES" ]]
then
        DoSqlQ "alter database force logging;"
fi

LoggingStat=$(DoSqlQ "select force_logging from v\$database;")
LogCons "Logging status: $LoggingStat"


ServerNo=$(echo $LocalServerInfo | awk -F "SERVER_NO:" '{print $2}')
DbUniNo="${DbSid}_${ServerNo}"
LogCons "Set db_unique_name to: $DbUniNo"
DoSqlQ "alter system set db_unique_name = $DbUniNo scope=spfile;"

DoSqlQ "shutdown immediate;"
DoSqlQ "startup"

BrokerDir="$OFA_BRO_ADMIN/${DbSid}"
LogCons "Create broker dir.:$BrokerDir"
[[ ! -d  $OFA_BRO_ADMIN/$DbSidStb ]] && mkdir -p $BrokerDir >/dev/null 2>&1

# Create service


LogCons "Delete old service: $ORACLE_SID"

ServiceName=$(DoSqlQ "select name from dba_services where name = '${ORACLE_SID}';")
if [[ ! -z $ServiceName ]]
then
        DoSqlQ "exec dbms_service.stop_service('${ORACLE_SID}');" >/dev/null
        DoSqlQ "exec dbms_service.delete_service('${ORACLE_SID}');" >/dev/null
fi


LogCons "Create SERVICE and SERVICE startup trigger"

sqlplus -s "/as sysdba" << __EOF > $SqlLog
DECLARE
  DB_NAME        VARCHAR(10);
BEGIN
select VALUE into DB_NAME from V\$PARAMETER where name = 'db_name';
FOR yy IN (select name
                as service_name
                from dba_services
                where name not in (select name from dba_services where name like DB_NAME||'%' or name like 'SYS$%'))
LOOP
        DBMS_OUTPUT.put_line ('--Drop SERVICE_NAME: '||chr(10)||yy.service_name||chr(10));
        DBMS_SERVICE.DELETE_SERVICE(yy.service_name);
END LOOP;
END;
/

DECLARE
  DB_NAME        VARCHAR(10);
  SERVICE_NAME   VARCHAR(96);
BEGIN
   select VALUE into DB_NAME   from V\$PARAMETER where name = 'db_name';
   DBMS_SERVICE.CREATE_SERVICE
      (
      service_name     => DB_NAME,
      network_name     => DB_NAME,
      failover_method  => 'BASIC',
      failover_type    => 'SELECT',
      failover_retries => 1800,
      failover_delay   => 1
   );
END;
/

CREATE OR REPLACE TRIGGER startup_trigger_service
AFTER STARTUP ON DATABASE
DECLARE
  DB_NAME        VARCHAR(10);
  DATABASE_ROLE  VARCHAR(25);
BEGIN
  select VALUE into DB_NAME   from V\$PARAMETER where name = 'db_name';
  select DATABASE_ROLE into DATABASE_ROLE from V\$DATABASE;
  IF DATABASE_ROLE = 'PRIMARY'
  THEN
    DBMS_SERVICE.START_SERVICE(DB_NAME);
  END IF;
END;
/
exit;
__EOF

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error create service or trigger Error: $SqlErr"
        LogError "Log: $SqlLog"
        exit 1
fi

# Broker configuration files

LogCons "Set broker file parameter."
DoSqlQ "alter system set dg_broker_config_file1 = '${BrokerDir}/dr1${DbSid}.dat' scope=both;"
DoSqlQ "alter system set dg_broker_config_file2 = '${BrokerDir}/dr2${DbSid}.dat' scope=both;"
DoSqlQ "show parameter broker_config;"

# Set/check remote_password_file.

LogCons "Set/check remote_password_file."
DoSqlQ "alter system set remote_login_passwordfile = EXCLUSIVE scope=spfile;"


LogCons "Switch archiving on"
DoSqlQ $OFA_SQL/SwitchArcLogging.sql on


LogCons "Set db_recovery_file_dest_size (100 GB) and db_recovery_file_dest"
[[ ! -d  /arch/${DbSid}/flashback ]] && mkdir -p /arch/${DbSid}/flashback

DoSqlQ "alter system set db_recovery_file_dest_size=100G scope=both;"
DoSqlQ "alter system set db_recovery_file_dest='/arch/${DbSid}/flashback' scope=both;"

LogCons "Flashback activation."

# Flashback activation.

FlashbachStat=$(DoSqlQ "select flashback_on from v\$database;")

if [[ "$LoggingStat" != "YES" ]]
then
        rm -rf /arch/${DbSid}/flashback/*
        DoSqlQ "alter database flashback on;"
else
        DoSqlQ "alter database flashback off;"
        rm -rf /arch/${DbSid}/flashback/*
        DoSqlQ "alter database flashback on;"
fi



FlashbachStat=$(DoSqlQ "select flashback_on from v\$database;")
LogCons "Flashback status: $FlashbachStat"

# Config standby redo

LogCons "Config standby redo"

StbRedoGroups=$(DoSqlQ "select GROUP#||':'||member from  V\$logfile where type = 'STANDBY';")
LogCons "Drop Standby log file"
for i in $StbRedoGroups
do
        MemberFile=$(echo $i | awk -F ":" '{print $2}')
        GroupName=$(echo $i | awk -F ":" '{print $1}')
        LogCons "Drop standby log file GROUP#: $i"
        DoSqlQ "alter database drop standby logfile group $GroupName;"
        rm -f $MemberFile
done

LogCons "Create new standby GROUP#"
DirName=$(DoSqlQ "select member from v\$logfile where type <> 'STANDBY';" | awk -F/ '{gsub($NF,"");sub(".$", "");print}' | tail -1)
LogSize=$(DoSqlQ "select to_char(bytes) from v\$log;" | tail -1)
NumberOfFilesPlus1=$(DoSqlQ "select count(*)+1 from v\$log;")

i=$NumberOfFilesPlus1

while [[ $i -gt 0 ]];do
GroupNo=$i

let GroupNo=GroupNo*100
        LogCons "Create standby log: 'ALTER DATABASE ADD STANDBY LOGFILE group $GroupNo ('${DirName}/redo_stb_G${GroupNo}M1.rdo') SIZE ${LogSize} reuse;' "
#       DoSqlQ "ALTER DATABASE ADD STANDBY LOGFILE group $GroupNo ('${DirName}/redo_stb_G${GroupNo}M1.rdo') SIZE ${LogSize} reuse;"
        DoSqlQ "ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 group $GroupNo ('${DirName}/redo_stb_G${GroupNo}M1.rdo') SIZE ${LogSize} reuse;"
let i-=1
done

# Set convert parameter.
DoSqlQ "alter system set log_file_name_convert='${OFA_DB_DATA}/${ORACLE_SID}/','${OFA_DB_DATA}/${ORACLE_SID}/' scope=spfile;"
DoSqlQ "alter system set db_file_name_convert='${OFA_DB_DATA}/${ORACLE_SID}/','${OFA_DB_DATA}/${ORACLE_SID}/' scope=spfile;"
# DoSqlQ "shutdown immediate;"
# DoSqlQ "startup;"
# DoSqlQ "show parameter file_name_convert"

# Set archive on
LogCons "Switch archiving on"
DoSqlQ $OFA_SQL/SwitchArcLogging.sql on

# Set up standby database.


RemoteHostVip=$(echo $RemoteServerInfo | awk -F ":" '{print $2}' | awk -F "," '{print $1}')
RemoteServerNo=$(echo $RemoteServerInfo | awk -F ":" '{print $5}')

LogCons "Copy DB config files to: $RemoteHostVip"

scp $ORACLE_HOME/dbs/spfile${ORACLE_SID}.ora $RemoteHostVip:$ORACLE_HOME/dbs/
scp $ORACLE_HOME/dbs/orapw${ORACLE_SID} $RemoteHostVip:$ORACLE_HOME/dbs/

LogCons "Call DgAdm.sh Confstandbydb ${DbSid} ${StbDbUni} on remote server $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; DgAdm.sh ConfStandbyDb ${DbSid} ${StbDbUni}"

ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DbSid ; DoSqlQ "$RemoteSqlScript"" > $ShhLog 2>&1


# Copy primary to Standby
CopyPrimToStb

ssh -q -o "StrictHostKeyChecking no" $StandbyServer ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; DgAdm.sh RenameLogfile ${DbSid}" > $ShhLog 2>&1

# Config standby
LogCons "Create script: $RemoteSqlScript on server: $RemoteHostVip"
echo "alter system set dg_broker_start = TRUE scope=both;" > $RemoteSqlScript
echo "alter database flashback on;" >> $RemoteSqlScript
echo "ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;" >> $RemoteSqlScript
# echo "alter system set service_names = '${DbSid},${DbSid}_${RemoteServerNo}' scope = both;" >> $RemoteSqlScript
echo "select flashback_on from v\$database;" >> $RemoteSqlScript
echo "show parameter dg_broker_start;" >> $RemoteSqlScript
cat $RemoteSqlScript | ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip "cat >> $RemoteSqlScript"
LogCons "Running "$RemoteSqlScript" on $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DbSid ; DoSqlQ "$RemoteSqlScript"" > $ShhLog 2>&1

ErrorSsh=$(grep ORA- $ShhLog)

if [[ ! -z $ErrorSsh ]]
then
        LogError "Error running: $RemoteSqlScript, Error: $ShhLog"
        LogError "Log: $ShhLog"
        cat $ShhLog
        exit 1
else
        cat $ShhLog
fi



LogCons "Startup broker on primary."
DoSqlQ "alter system set dg_broker_start = TRUE scope=both;"
DoSqlQ "show parameter dg_broker_start;"

ConfigBroker

# Wait for services to be ready
echo "Please wait......" ; sleep 120
echo "**** READ ****"
dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
show configuration verbose;/
show database verbose '${PrimDbUni}';
show database verbose '${StbDbUni}';
__EOF

# Test switchover
#LogCons "Test Switch over no 1."
UniSid=${StbDbUni}
# echo "************* No switch over No. 1 *************"
#SwOver
#dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
#show configuration verbose;
#show database verbose '${PrimDbUni}';
#show database verbose '${StbDbUni}';
#__EOF



#LogCons "Test Switch over no 2. (switching back...)"
echo "Please wait......" ; sleep 60
# echo "************* No switch over No 2. *************"
#SwOver
LogCons "End of Standby configuration."
LogCons "Pleae test the  Switch over on both node."
}
#---------------------------------------------
ConfigBroker ()
#---------------------------------------------
{


# typeset -i PrimVip
# typeset -i StbVip

# PrimVip="${DbSid}${LocalServerNo}-vip"
# StbVip="${DbSid}${RemoteServerNo}-vip"


LogCons "Config broker."
LogCons "Config name: ${DbSid}"
LogCons "Primary: ${PrimDbUni} $PrimVip"
LogCons "Standby: ${StbDbUni} $StbVip"
LogCons "Primary vip: $PrimVip"
LogCons "Standby vip: $StbVip"


LogCons "Set log_archive_dest log parameter."
LogCons "Log file: $SqlLog"

DoSql "select * from v\$parameter where NAME = 'log_archive_dest_2';" > $SqlLog
DoSql "alter system set log_archive_dest_2='' scope=both;" >> $SqlLog
DoSql "select * from v\$parameter where NAME = 'log_archive_dest_2';" >> $SqlLog

DoSql "shutdown immediate;" >> $SqlLog
DoSql "startup" >> $SqlLog


Err=$(grep ORA- $SqlLog )

if [[ ! -z $Err ]]
then
        LogError "Error Set log_archive_dest, Error: $Err"
        LogError "Log: $SqlLog"
        exit 1
else
        cat $SqlLog
fi

# Create DG configuration

LogCons "Create DG configuration."
LogCons "Log file: $DgmgrlLog"

echo "Please wait......" ; sleep 30
echo ""

dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog

create configuration '${DbSid}' as primary database is '${PrimDbUni}' connect identifier is '${PrimDbUni}';

add database '${StbDbUni}' as connect identifier is '${StbDbUni}';

enable configuration ;

__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog )

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error Create DG configuration, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
        exit 1
else
        cat $DgmgrlLog
fi



# Config DG

DgmgrlLog=$OFA_LOG/tmp/DgAdm.DgmgrlLog.$FuncToDo.Config_DG.$$.$PPID.$TimeStamp.lo
LogCons "Config DG"
LogCons "Logfile: $DgmgrlLog"
echo "Please wait......" ; sleep 180
echo ""


dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog

EDIT DATABASE '${PrimDbUni}' SET PROPERTY 'LogXptMode'='SYNC';
EDIT DATABASE '${StbDbUni}' SET PROPERTY 'LogXptMode'='SYNC';

EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;

sql "ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY";

edit database '${PrimDbUni}' set property StandbyFileManagement = 'AUTO';
edit database '${StbDbUni}' set property StandbyFileManagement = 'AUTO';

edit database '${PrimDbUni}' set property NetTimeout = 20;
edit database '${StbDbUni}' set property NetTimeout = 20;

edit database '${PrimDbUni}' set property ArchiveLagTarget = 1200;
edit database '${StbDbUni}' set property ArchiveLagTarget = 1200;

rem edit database '${PrimDbUni}' set property LogFileNameConvert ='${DbSid},${DbSid}';
rem edit database '${StbDbUni}' set property LogFileNameConvert ='${DbSid},${DbSid}';

rem edit database '${PrimDbUni}' set property DbFileNameConvert ='${DbSid},${DbSid}';
rem edit database '${StbDbUni}' set property DbFileNameConvert ='${DbSid},${DbSid}';

rem  show configuration verbose;
rem  show database verbose '${PrimDbUni}';
rem  show database verbose '${StbDbUni}';
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog | grep -v ORA-16675)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error Config DG, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
else
        cat $DgmgrlLog | grep -v ORA-16675
fi

DgmgrlLog=$OFA_LOG/tmp/DgAdm.DgmgrlLog.$FuncToDo.$$.$PPID.$TimeStamp.log


LogCons "Set Connect string in DG"

ConnHostPrim=$(dgmgrl -silent sys/${MmDp}@${PrimDbUni} "show database verbose '${PrimDbUni}'" | grep StaticConnectIdentifier | awk -F "HOST=" '{print $2}' | awk -F ")" '{print $1}')
ConnHostStb=$(dgmgrl -silent sys/${MmDp}@${PrimDbUni} "show database verbose '${StbDbUni}'" | grep StaticConnectIdentifier | awk -F "HOST=" '{print $2}' | awk -F ")" '{print $1}')

LogCons "Primary Vip: ${PrimVip}"
echo "Standby Vip: ${StbVip}"

NewConnHostPrim=$(dgmgrl -silent sys/${MmDp}@${PrimDbUni} "show database verbose '${PrimDbUni}'" | grep StaticConnectIdentifier | awk -F "StaticConnectIdentifier" '{print $2}' | sed "s/(HOST=${ConnHostPrim})/(HOST=${PrimVip})/g")
NewConnHostStb=$(dgmgrl -silent sys/${MmDp}@${PrimDbUni} "show database verbose '${StbDbUni}'" | grep StaticConnectIdentifier | awk -F "StaticConnectIdentifier" '{print $2}' | sed "s/(HOST=${ConnHostStb})/(HOST=${StbVip})/g")

LogCons "Connect Info primary:${NewConnHostPrim}"
LogCons "Connect Info Standby:${NewConnHostStb}"

dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
edit database '${PrimDbUni}' set property StaticConnectIdentifier ${NewConnHostPrim};
edit database '${StbDbUni}' set property StaticConnectIdentifier ${NewConnHostStb};
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog | grep -v ORA-16675)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error Config DG, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
else
        cat $DgmgrlLog
fi


LogCons "Check/Show configuration."

echo "Please wait......" ; sleep 60
echo ""

dgmgrl -silent sys/${MmDp}@${PrimDbUni} << __EOF > $DgmgrlLog
show configuration verbose;
show database verbose '${PrimDbUni}';
show database verbose '${StbDbUni}';
__EOF

DgmgrlErr=$(grep ORA- $DgmgrlLog)

if [[ ! -z $DgmgrlErr ]]
then
        LogError "Error Config DG, Error: $DgmgrlErr"
        LogError "Log: $DgmgrlLog"
else
        cat $DgmgrlLog
fi


}
#---------------------------------------------
ConfStbDb ()
#---------------------------------------------
{
LogCons "Config Standby database: ${DbSid}"
LogCons "Remote Server Info: ${RemoteServerInfo}"

RemoteHostVip=$(echo $RemoteServerInfo | awk -F ":" '{print $2}' | awk -F "," '{print $1}')
RemoteServerNo=$(echo $RemoteServerInfo | awk -F ":" '{print $5}')



LogCons "Create standby dir. on server: $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc ; OraEnv $DbSid ; $OFA_BIN/cre.dir.sh cdb" 2>&1 | LogStdIn

LogCons "Create broker dir. on server: $RemoteHostVip"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip "mkdir -p /oracle/rdbms/admin/broker/$ORACLE_SID"

LogCons "Copy spfile and password file. to server $RemoteHostVip"
scp -q $ORACLE_HOME/dbs/spfile${DbSid}.ora $RemoteHostVip:$ORACLE_HOME/dbs/spfile${DbSid}.ora
scp -q $ORACLE_HOME/dbs/orapw${DbSid} $RemoteHostVip:$ORACLE_HOME/dbs/spfile${DbSid}

LogCons "Adapt the standby db_unique_name. on server: $RemoteHostVip"
LogCons "Startup $RemoteHostVip, $DbSid"
ssh -q -o "StrictHostKeyChecking no" $RemoteHostVip ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; OraEnv $DbSid ; DoSqlQ "startup nomount force; > /dev/null""


LogCons "Config standby parameter......"
LogCons "Log file: $SqlLog"




sqlplus -s sys/$MmDp@${DbSid}_${RemoteServerNo} << __EOF > $SqlLog
set heading off;
set feedback off;
set timing off;
startup nomount force;
alter system set db_unique_name='${DbSid}_${RemoteServerNo}' scope=spfile;
alter system set log_file_name_convert='${OFA_DB_DATA}/${DbSid}','${OFA_DB_DATA}/${DbSid}' scope=spfile;
alter system set db_file_name_convert='${OFA_DB_DATA}/${DbSid}','${OFA_DB_DATA}/${DbSid}' scope=spfile;
-- alter system set service_names = '${DbSid},${DbSid}_${RemoteServerNo}' scope = both;
startup nomount force;
show parameter unique_name;
show parameter file_name_convert;
select value from v\$parameter where name like 'dg_broker_config_file%';
exit;
__EOF

SqlErr=$(grep "ORA-" $SqlLog)

if [[ ! -z $SqlErr ]]
then
        LogError "Error Config standby parameter, Error: $SqlErr"
        LogError "Log: $SqlLog"
fi
}
#---------------------------------------------
ConfStandbyDb ()
#---------------------------------------------
{
LogCons "Config Standby Database."
DbSidStb=$1
DdSidStbUni=$2
  CheckVar DbSidStb         \
           DdSidStbUni      \
  || Usage
OraEnv $DbSidStb

[[ ! -d  $OFA_BRO_ADMIN/$DbSidStb ]] && mkdir -p $OFA_BRO_ADMIN/$DbSidStb
[[ ! -d  /arch/${DbSidStb}/flashback ]] && mkdir -p /arch/${DbSidStb}/flashback
rm -rf /arch/${DbSidStb}/flashback/*

LogCons "changing convert parameter "
DoSqlQ "shutdown abort;"
DoSqlQ "startup nomount;"
LogCons "Set db_unique_name=$DdSidStbUni"
DoSqlQ "alter system set db_unique_name='${DdSidStbUni}' scope=spfile;"
LogCons "Set log_file_name_convert: ${OFA_DB_DATA}/$DbSid"
DoSqlQ "alter system set log_file_name_convert='${OFA_DB_DATA}/${DbSid}','${OFA_DB_DATA}/${DbSid}' scope=spfile;"
LogCons "Set db_file_name_convert: /DB/$DbSid"
DoSqlQ "alter system set db_file_name_convert='${OFA_DB_DATA}/${DbSid}','${OFA_DB_DATA}/${DbSid}' scope=spfile;"

DoSqlQ "shutdown abort;"
DoSqlQ "create pfile='$ORACLE_HOME/dbs/init${DbSidStb}.ora'  from spfile='$ORACLE_HOME/dbs/spfile${DbSidStb}.ora';"
LogCons "Startup $DbSid"
DoSqlQ "startup nomount pfile='$ORACLE_HOME/dbs/init${DbSidStb}.ora';"
LogCons "Check parameter on: $DbSid"
DoSqlQ "show parameter unique_name;"
DoSqlQ "show parameter file_name_convert;"


LogCons "Restart listener..."
# lsnrctl reload LISTENER_${DbSid}
lsnrctl stop LISTENER_${DbSid} 2>&1 >/dev/null
lsnrctl start LISTENER_${DbSid}
# Wait for listener..... Zzzzzz
echo "Please wait......" ; sleep 10
echo ""
}
#---------------------------------------------
CopyPrimToStb ()
#---------------------------------------------
{
LogCons "Copy Primary -> Standby"
LogCons "Create RMAN command file."
if [[ -z $NumberOfChannel ]]
then
        NumberOfChannel=6
fi

LogCons "Number of Channels: $NumberOfChannel"
LocalServerNo=$(echo $LocalServerInfo | awk -F "SERVER_NO:" '{print $2}')
LocalDbUniName="${DbSid}_${LocalServerNo}"

RemoteServerNo=$(echo $RemoteServerInfo | awk -F "SERVER_NO:" '{print $2}')
RemoteDbUniName="${DbSid}_${RemoteServerNo}"

echo "connect target sys/${MmDp}@$LocalDbUniName" > $RmanExecRmanCopyPrimToStb
echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $NumberOfChannel BACKUP TYPE TO BACKUPSET;" >> $RmanExecRmanCopyPrimToStb
echo "connect auxiliary sys/${MmDp}@$RemoteDbUniName " >> $RmanExecRmanCopyPrimToStb
echo "duplicate target database for standby from active database " >> $RmanExecRmanCopyPrimToStb
echo "spfile" >> $RmanExecRmanCopyPrimToStb
echo " parameter_value_convert '$DbSid','$DbSid' " >> $RmanExecRmanCopyPrimToStb
echo " set db_unique_name='$RemoteDbUniName' " >> $RmanExecRmanCopyPrimToStb
echo " set db_file_name_convert='$DbSid','$DbSid' " >> $RmanExecRmanCopyPrimToStb
echo " set log_file_name_convert='$DbSid','$DbSid' " >> $RmanExecRmanCopyPrimToStb
echo "dorecover nofilenamecheck;" >> $RmanExecRmanCopyPrimToStb
echo "CONFIGURE DEVICE TYPE DISK PARALLELISM 1 BACKUP TYPE TO BACKUPSET;" >> $RmanExecRmanCopyPrimToStb
echo "exit" >> $RmanExecRmanCopyPrimToStb

LogCons "Run command file: $RmanExecRmanCopyPrimToStb"
LogCons "Log file: $RmanLog"

echo "Please wait......" ; sleep 60

rman $ConnectString cmdfile=$RmanExecRmanCopyPrimToStb 2>&1 | grep -v RMAN-05158 | grep -v ORA-01275 | tee $RmanLog | LogStdIn
# rman $ConnectString cmdfile=$RmanExecRmanCopyPrimToStb debug=ALL log=$OFA_LOG/tmp/rman.debug_$TimeStamp.txt 2>&1 | grep -v RMAN-05158 | grep -v ORA-01275 | tee $RmanLog | LogStdIn
CheckErrorRman

}
#---------------------------------------------------------
CheckErrorRman ()
#---------------------------------------------------------
{
ExecError=$(grep "RMAN-"  $RmanLog | grep -v -i "WARNING")

if [[ ! -z "$ExecError" ]]
then
        FirstLineError=$(grep "RMAN-"  $RmanLog | grep -v -i "WARNING" | head -1)
        LogError "Error: $FirstLineError"
        LogError "Log file: $RmanLog"
        exit 1
fi
}
#---------------------------------------------
RenameLogfile ()
#---------------------------------------------
{
LogCons "Rename Logfile on the Standby Database."
DbSidStb=$1
if [[ -z $DbSidStb ]]
then
exit 1
fi 
OraEnv $DbSidStb

DoSqlQ "alter system set standby_file_management=MANUAL;"
DoSqlQ "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;"
DoSqlQ " SELECT group#, type, member FROM v\$logfile order by group#;"
DirName=$(DoSqlQ "select member from v\$logfile where type <> 'STANDBY';" | awk -F/ '{gsub($NF,"");sub(".$", "");print}' | tail -1)
LogSize=$(DoSqlQ "select to_char(bytes) from v\$log;" | tail -1)
NumberOfFilesstb=$(DoSqlQ "select count(*) from v\$logfile where type='STANDBY';")
NumberOfFilesRedo=$(DoSqlQ "select count(*) from v\$log;")

i=$NumberOfFilesRedo

while [[ $i -gt 0 ]];do
GroupNo=$i

let GroupNo=GroupNo*1
        DoSqlQ "ALTER DATABASE DROP LOGFILE group $GroupNo ;"
        DoSqlQ "ALTER DATABASE ADD LOGFILE THREAD 1 group $GroupNo ('${DirName}/redo_G${GroupNo}M2l.rdo') SIZE ${LogSize} reuse;"
let i-=1
done

b=$NumberOfFilesstb
while [[ $b -gt 0 ]];do
GroupNo=$b
let GroupNo=GroupNo*100
        DoSqlQ "alter database clear logfile group $GroupNo;"
        DoSqlQ "ALTER DATABASE DROP STANDBY LOGFILE group $GroupNo ;"
        DoSqlQ "ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 group $GroupNo ('${DirName}/redo_G${GroupNo}MS2.rdo') SIZE ${LogSize} reuse;"
let b-=1
done


DoSqlQ " SELECT group#, type, member FROM v\$logfile order by group#;"
DoSqlQ "alter system set standby_file_management=AUTO;"
}
#---------------------------------------------
# Main
#---------------------------------------------
# set -xv
if [[ "$FuncToDo" == "Login" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        LogIn
elif [[ "$FuncToDo" == "Status" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        GetStatus
elif [[ "$FuncToDo" == "Statusl" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        GetStatusL
elif [[ "$FuncToDo" == "Getconfdg" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        GetConfDg
elif [[ "$FuncToDo" == "Swover" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        SwOver
elif [[ "$FuncToDo" == "Rebuildstbonly" ]]
then
        DbSid=$2
        StandbyServer=$3
        NumberOfChannel=$4
        RebuildStbOnly $DbSid $StandbyServer
elif [[ "$FuncToDo" == "Rebuildstb" ]]
then
        DbSid=$2
        StandbyServer=$3
        NumberOfChannel=$4
        RebuildStb $DbSid $StandbyServer
elif [[ "$FuncToDo" == "Dropstblocal" ]]
then
        UniSid=$2
        StandbyServer=$3
        DropStbRemote $UniSid $StandbyServer
elif [[ "$FuncToDo" == "Dropprimconf" ]]
then
        DbSid=$2
        LogCons "Login to: $DbSid"
        DropPrimConf
elif [[ "$FuncToDo" == "Dropstbconf" ]]
then
        UniSid=$2
        LogCons "Login to: $UniSid"
        DropStbConf
elif [[ "$FuncToDo" == "Reinstate" ]]
then
        UniSid=$2
        ReiSid=$3
        LogCons "Login to: $UniSid"
        Reinstate
elif [[ "$FuncToDo" == "Dropstbforceonly" ]]
then
        DbSid=$2
        LogCons "Login to: $DbSid"
        DropStbForceOnly
elif [[ "$FuncToDo" == "Dropstbforce" ]]
then
        DbSid=$2
        LogCons "Login to: $DbSid"
        DropStbForce
elif [[ "$FuncToDo" == "Validate" ]]
then
        UniSid=$2
        Validate
elif [[ "$FuncToDo" == "Failover" ]]
then
        UniSid=$2
        Failover
elif [[ "$FuncToDo" == "Confprimdb" ]]
then
        DbSid=$2
        ConfPrimDb
elif [[ "$FuncToDo" == "Renamelogfile" ]]
then
        DbSidStb=$2
        LogCons "Configure Redo log at the standby"
        RenameLogfile $DbSidStb
elif [[ "$FuncToDo" == "Showfastsw" ]]
then
        UniSid=$2
        ShowFastSw
elif [[ "$FuncToDo" == "Confstandbydb" ]]
then
        DbSid=$2
        DbSidUni=$3
        ConfStandbyDb $DbSid $DbSidUni
else
        usage
fi

VolMin
