#!/bin/bash
  #
  # load lib
  #  dg_adm_cliNew.sh Buildstb <pirmarySID>  <force>
  #

OFA_TAG="dg_adm_cli.sh"
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi

#YesNo $(basename $0) || exit 1 && export RunOneTime=YES

time_stamp=$(date +"%H%M%S")
broker_cmd_out=$OFA_LOG/tmp/dg_adm_cli.broker_cmd_out.$$.$PPID.$time_stamp.log
sql_exec_log=$OFA_LOG/tmp/dg_adm_cli.sql_exec_log.$$.$PPID.$time_stamp.log
sql_cmd=$OFA_LOG/tmp/dg_adm_cli.sql_cmd.$$.$PPID.$time_dtamp.log
ssh_log=$OFA_LOG/tmp/dg_adm_cli.ssh_log.$$.$PPID.$time_stamp.log
rman_log=$OFA_LOG/tmp/dg_adm_cli.rman_log.$$.$PPID.$time_stamp.log
rman_cmd=$OFA_LOG/tmp/dg_adm_cli.rman_cmd.$$.$PPID.$time_stamp.rman
broker_cmd=$OFA_LOG/tmp/dg_adm_cli.broker_cmd.$$.$PPID.$time_stamp.dg
net_log=$OFA_LOG/tmp/dg_adm_cli.net_log.$$.$PPID.$time_stamp.dg

my_hostname=$(uname -n)
START_TIME=$(date +%s)

#---------------------------------------------
function usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: dg_adm_cli [-h help] [-a {action}] [-d primary_sid] [-c config_file ] [-f force]
##
## SYNOPSYS: Create a standby (Data Guard) database.
##
## OPTIONS:
## -h                     This help
## -a                     The action to be executed. This option is MANDATORY.
##                          build             : will build the standby
##                          check_dg_config   : will execute a check of an existent configuration
##                          check_can_create  : check if the standby database can be created. No changes are made.
## -d                     The primary database SID. This option is MANDATORY.
## -c                     The configuration file
## -f                     Force flag. If not set the primary database will be NOT restarted.
##                        If actions that need a primary database restart are needed and <force flag> is
##                        not used the script will fail
##
## NOTE:                  The script must be executed only on the server on which primary database is installed.
##                        Any execution on standby server will exit.
##                        For the config file check template: $OFA_SCR/db_config_template.yml
##
##
## EXAMPLE:               dg_adm_cli.sh -a build -d DBDEV1 -s DBDEV02-VIP
##
##
__EOF
exit 22
}

# -------------------------------------------------------------------
# Get the parameters from config file
# -------------------------------------------------------------------
function get_param () {
  local param=$1
  local _ret_val=""

  if [ -z "$param" ]; then
    LogError "Unable to get an empty parameter."
    exit 1
  fi
  if [ ! -z "$2" ]; then
    _ret_val=$2
  fi
  local data=$(read_config_file.py -a read -f $config_file -p $param)
  local err_cnt=$(echo $data | grep -c "Error")
  if [ "$err_cnt" != "0" ]; then
    LogError "Error getting $param from $config_file"
    exit 1
  fi

  if [ ! -z "$_ret_val" ]; then
    eval $_ret_val=$(echo "'${data}'")
  fi
}

# -------------------------------------------------------------------
# Execute a command on remote server
# -------------------------------------------------------------------
function exec_remote() {
  local remote_server=$1
  local cmd=$2
  CheckVar remote_server \
           cmd \
  || Usage
  ssh_out=''
  ssh_out=$(ssh -q -o "StrictHostKeyChecking no" $remote_server \
    ". .bash_profile ; . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2}')/etc/ofa/0fa_load.rc > /dev/null 2>&1 ; $cmd")
}

# -------------------------------------------------------------------
# Check is the database is working oin OMF
# -------------------------------------------------------------------
function check_is_omf () {
  local _ret_val=""
  local chk="false"

  if [ ! -z "$1" ]; then
    _ret_val=$1
  fi

  chk=$(GetDbParam db_create_online_log_dest_1)
  if [ ! -z "$chk" ]; then
    chk="true"
  fi

  if [ ! -z "$_ret_val" ]; then
    eval $_ret_val=$(echo "'${chk}'")
  fi
}

# -------------------------------------------------------------------
# Compute and set variables names for primary and standy
# -------------------------------------------------------------------
function set_names() {
  get_param "dataguard.primary_vip" prim_vip
  get_param "dataguard.primary_unique_name" prim_db_unique
  get_param "dataguard.standby_vip" stb_vip
  get_param "dataguard.standyb_unique_name" stb_db_unique
  get_param "database.multitenant" is_multitenant
  is_multitenant=$(echo $is_multitenant |  tr '[:upper:]' '[:lower:]'  )

  LogCons "================================================="
  LogCons "Primary UNIQUE name : $prim_db_unique"
  LogCons "Standby UNIQUE name : $stb_db_unique"
  LogCons "Primary vip         : $prim_vip"
  LogCons "Standby vip         : $stb_vip"
  LogCons "Multitenant         : $is_multitenant"
  LogCons "================================================="
}

# -------------------------------------------------------------------
# Clear the primary database configuration
# -------------------------------------------------------------------
function drop_prim_conf ()
{
  LogCons "Drop Primary DG configuration"
    CheckVar prim_sid       \
    || Usage

  LogCons "Log file: $sql_exec_log"
  DoSqlQStrict "select value from v\$parameter where name like 'dg_broker_config_file%';"  | tee -a $sql_exec_log
  for i in $(cat $sql_exec_log); do
    LogCons "Remove file: $i"
    rm -f $i >> $ssh_log 2>&1
    if [[ $? -ne 0 ]]; then
      LogError "Error Remove file: $i"
    fi
  done

  DoSqlQStrict "alter system set dg_broker_start=FALSE;" | tee -a $sql_exec_log
  LogCons "Reset dataguard parameters. "
  DoSqlQStrict "alter system reset log_archive_dest_2 scope=both sid='*';" | tee -a $sql_exec_log
  DoSqlQStrict "alter system reset log_archive_config scope=both sid='*';" | tee -a $sql_exec_log
  
}

# -------------------------------------------------------------------
#  Check if the network interfaces are present
#    dataguard base can be created. No changes are made.
# -------------------------------------------------------------------
function check_network() {
  LogCons "Check the vip's needed fot dataguard construction on ${prim_sid}."
  for id in 1 2; do
    ip=$(nslookup ${prim_sid}0${id}-vip | awk '/^Address: / { print $2 }')
    if [ -z "$ip" ];then
      LogError "The VIP ${prim_sid}01-vip is not defined"
      exit 1
    else 
      LogCons "The VIP ${prim_sid}01-vip is $ip. "
    fi
  done
}

# -------------------------------------------------------------------
#  Get the primary database port. The standby port will be the same
# -------------------------------------------------------------------
function get_prim_db_port() {
  db_port=$(lsnrctl status LISTENER_${prim_sid} |  grep -m 1 -oP 'HOST=.*?PORT=\K\d+')
  if [[ -n "$db_port" && "$db_port" =~ ^[0-9]+$ ]]; then
    LogCons "Primary database $prin_sid port is $db_port. The standy will use the same port."
  else
    LogError "Unable to find the primary database $prim_sid port."
    exit 1
  fi
}

# -------------------------------------------------------------------
#  Check that the fielsystem on the standby server are present
# -------------------------------------------------------------------
function check_fs_stby() {

  exec_remote $stb_vip "df | grep -c ${prim_sid}"
  if [ "$ssh_out" == "0" ]; then
    LogError "Cannot build the dataguard. Remote file systems are not presents for $prim_sid."
    LogError "Need at least <3> filesystem. Found <$ssh_out>"
    exit 1
  fi
  
  LogCons "Check FS on standy server. Found <$ssh_out>. "
}
# -------------------------------------------------------------------
# Check the Primary database configuration to validate if the 
#    dataguard base can be created. No changes are made.
# -------------------------------------------------------------------
function check_can_create_dg {

  LogCons "Check if the standy database can be created for $prim_sid"

  get_prim_db_port

  check_network

  check_fs_stby

  OraEnv $prim_sid
  buildDG="true"

  force_logging=$(DoSqlQStrict "select force_logging from v\$database;")
  LogCons "Force Logging state on database: $force_logging"

  LogMode=$(DoSqlQStrict "select log_mode from v\$database;")
  LogCons "Check log mode on database: $LogMode"
  if [ "$LogMode" != "ARCHIVELOG" ]; then 
    LogError "  Given database is in $LogMode. Dataguard need ARCHIVELOG mode."
    LogError "  To switch the mode database need to be restarted."
    buildDG="false"
  fi

  DBUni=$(GetDbParam db_unique_name)
  if [ "$DBUni" != "$prim_db_unique" ]; then
    LogCons "WARNING: Actual db unique name is $DBUni. For dataguard db unique name must be $prim_db_unique. Primary DB will be restarted."
    buildDG="false"
  fi

  LogCons "Broker state is: $(GetDbParam dg_broker_start)"

  if [ "$buildDG" == "false" ] && [ "$force_flag" != "force" ]; then
    LogError "Cannot build the dataguard. See previous traces. Force mode is ($force_flag)"
    exit 1;
  fi
}

# -------------------------------------------------------------------
# Create the borker configuration. And validate it
# -------------------------------------------------------------------
function config_broker () {

  LogCons "Create the broker configuration"
  LogCons "Primary UNIQUE name: $prim_db_unique"
  LogCons "Standby UNIQUE name: $stb_db_unique"
  LogCons "Primary vip: $prim_vip"
  LogCons "Standby vip: $stb_vip"

  LogCons "Create broker configuration. "
  LogCons "Command file: $broker_cmd"
  LogCons "Logfile:  $broker_cmd_out"

  echo "connect sys/${MmDp}@${prim_db_unique};" >  $broker_cmd
  echo "create configuration '${prim_sid}' as primary database is '${prim_db_unique}' connect identifier is '${prim_db_unique}';" >> $broker_cmd
  echo "add database '${stb_db_unique}' as connect identifier is '${stb_db_unique}';" >>  $broker_cmd
  echo "enable configuration;" >> $broker_cmd 
  dgmgrl -silent @$broker_cmd > $broker_cmd_out
  broker_err=$(grep ORA- $broker_cmd_out )
  if [[ ! -z $broker_err ]]; then
    LogError "Error Create DG configuration, Error: $broker_err"
    LogError "Log: $broker_cmd_out"
    exit 1
  fi
  sed -i "1s/.*/$connect sys\/******@${prim_db_unique};/" $broker_cmd 
  cat $broker_cmd

  LogCons "Update broker database parameters. "
  LogCons "Command file: $broker_cmd"
  LogCons "Logfile:  $broker_cmd_out"
  echo "connect sys/${MmDp}@${prim_db_unique};" >  $broker_cmd
  # Really need Maximum avalability ? Leave it to default  maximum performance: 
  # echo "edit database '${prim_db_unique}' set property 'LogXptMode'='SYNC';" >>  $broker_cmd
  # echo "edit database '${stb_db_unique}' set property 'LogXptMode'='SYNC';" >>  $broker_cmd
  # echo "EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;" >>  $broker_cmd
  # echo "sql \"ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY\";" >>  $broker_cmd
  echo "edit database '${prim_db_unique}' set property StandbyFileManagement = 'AUTO';" >>  $broker_cmd
  echo "edit database '${stb_db_unique}' set property StandbyFileManagement = 'AUTO';" >>  $broker_cmd
  echo "edit database '${prim_db_unique}' set property NetTimeout = 20;" >>  $broker_cmd
  echo "edit database '${stb_db_unique}' set property NetTimeout = 20;" >>  $broker_cmd
  echo "edit database '${prim_db_unique}' set property ArchiveLagTarget = 1200;" >>  $broker_cmd
  echo "edit database '${stb_db_unique}' set property ArchiveLagTarget = 1200;" >>  $broker_cmd
  echo "edit database '${prim_db_unique}' set property StandbyFileManagement = 'AUTO';" >>  $broker_cmd
  echo "edit database '${stb_db_unique}' set property StandbyFileManagement = 'AUTO';" >>  $broker_cmd
  echo "edit database '${prim_db_unique}' set property StaticConnectIdentifier='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${prim_vip})(PORT=${db_port}))(CONNECT_DATA=(SERVICE_NAME=${prim_db_unique}_DGMGRL)(INSTANCE_NAME=${prim_sid})(SERVER=DEDICATED)(STATIC_SERVICE=TRUE)))';" >>  $broker_cmd
  echo "edit database '${stb_db_unique}' set property StaticConnectIdentifier='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${stb_vip})(PORT=${db_port}))(CONNECT_DATA=(SERVICE_NAME=${stb_db_unique}_DGMGRL)(INSTANCE_NAME=${prim_sid})(SERVER=DEDICATED)(STATIC_SERVICE=TRUE)))';" >>  $broker_cmd
  echo "sql \"alter system switch logfile\";" >>  $broker_cmd
  dgmgrl -silent @$broker_cmd > $broker_cmd_out
  broker_err=$(grep ORA- $broker_cmd_out )
  if [[ ! -z $broker_err ]]; then
    LogError "Error Create DG configuration, Error: $broker_err"
    LogError "Log: $broker_cmd_out"
    exit 1
  fi
  sed -i "1s/.*/$connect sys\/******@${prim_db_unique};/" $broker_cmd 
  cat $broker_cmd 
  check_dg_config
}

# -------------------------------------------------------------------
# Create the standby redologs if needed on primary database
# -------------------------------------------------------------------
function config_stby_redo() {
  LogCons "Config standby redo"

  log_groups=$(DoSqlQStrict "select count(*)+1 from v\$log;" | tr -d '[:space:]')
  sby_groups=$(DoSqlQStrict "select count(*) from v\$standby_log;" | tr -d '[:space:]')
  if [ "$log_groups" == "$sby_groups" ]; then
    LogCons "  There are already $log_groups standby. No need to recreate."
  else

    StbRedoGroups=$(DoSqlQStrict "select group#||':'||member from  V\$logfile where type = 'STANDBY';")
    LogCons "  Drop Standby log file"
    for i in $StbRedoGroups
    do
        member_file=$(echo $i | awk -F ":" '{print $2}')
        group_name=$(echo $i | awk -F ":" '{print $1}')
        LogCons "  Drop standby log file group#: $i"
        DoSqlQStrict "alter database drop standby logfile group $group_name;"
        rm -f $member_file
    done

    LogCons "  Create new standby GROUP#"
    dir_name=$(DoSqlQStrict "select member from v\$logfile where type <> 'STANDBY';" | awk -F/ '{gsub($NF,"");sub(".$", "");print}' | tail -1)
    logfile_size=$(DoSqlQStrict "select to_char(bytes) from v\$log;" | tail -1)

    i=$log_groups
    while [[ $i -gt 0 ]];do
      group_no=$i
      let group_no=group_no*100
      LogCons "  Create standby log ${group_no}"
      if [ "${is_omf}" ]; then
        DoSqlQStrict "alter database add standby logfile thread 1 group $group_no size ${logfile_size};"
      else
        DoSqlQStrict "alter database add standby logfile thread 1 group $group_no ('${dir_name}/redo_stb_G${group_no}M1.rdo') size ${logfile_size} reuse;"
      fi
      let i-=1
    done
  fi
}

# -------------------------------------------------------------------
# Create the listener configuration on primary and standby
# -------------------------------------------------------------------
function config_listeners() {
  LogCons "Update local listener.ora and tnsnames.ora"
  LogCons "   logfile: $net_log"
  $OFA_BIN/listener_adm_cli.sh -a update -d $prim_sid -m $prim_vip -p $db_port -u $prim_db_unique > $net_log 2>&1
  $OFA_BIN/tnsnames_adm_cli.sh -a update -d $prim_sid -m $prim_vip -p $db_port -s $prim_sid > $net_log 2>&1
  $OFA_BIN/tnsnames_adm_cli.sh -a update -d $prim_db_unique -m $prim_vip -p $db_port -s $prim_sid > $net_log 2>&1
  $OFA_BIN/tnsnames_adm_cli.sh -a update -d $stb_db_unique -m $stb_vip -p $db_port -s $prim_sid > $net_log 2>&1

  LogCons "Update remote listener.ora and tnsnames.ora"
  LogCons "   logfile: $net_log"
  exec_remote $stb_vip "$OFA_BIN/listener_adm_cli.sh -a update -d $prim_sid -m $stb_vip -p $db_port -u $stb_db_unique > $net_log 2>&1"
  exec_remote $stb_vip "$OFA_BIN/tnsnames_adm_cli.sh -a update -d $prim_sid  -m $stb_vip -p $db_port -s $prim_sid > $net_log 2>&1"
  exec_remote $stb_vip "$OFA_BIN/tnsnames_adm_cli.sh -a update -d $prim_db_unique -m $prim_vip -p $db_port -s $prim_sid > $net_log 2>&1"
  exec_remote $stb_vip "$OFA_BIN/tnsnames_adm_cli.sh -a update -d $stb_db_unique -m $stb_vip -p $db_port -s $prim_sid > $net_log 2>&1"
  # TODO: Only if force is used.
  if [ "$force_flag" == "force" ]; then
    LogCons "Restart the local listener : LISTENER_${prim_sid}"
    $OFA_BIN/listener_adm_cli.sh -a restart -d ${prim_sid} > $net_log 2>&1
    DoSqlQStrict "alter system register;"
  else
    LogCons "Primary server listener LISTENER_${prim_sid}, was not restarted as force flag mode was not used. (-f parameter)."
  fi

  LogCons "Restart the remote listener : LISTENER_${prim_sid}"
  exec_remote $stb_vip "$OFA_BIN/listener_adm_cli.sh -a restart -d ${prim_sid} > $net_log 2>&1"
}

# -------------------------------------------------------------------
# Execute the duplicate database to build the standby
# -------------------------------------------------------------------
function create_sby() {
    CheckVar prim_db_unique \
             stb_db_unique \
             prim_vip \
             stb_vip \
             prim_sid \
  || Usage

  LogCons "RMAN duplicate command file: $rman_cmd"
  LogCons "Log file: $rman_log"
  LogCons "Recovery in progress....... This could take a while."
  echo "connect target sys/${MmDp}@$prim_db_unique
    configure device type disk parallelism 6 backup type to backupset;
    connect auxiliary sys/${MmDp}@$stb_db_unique;
    duplicate target database for standby from active database
     spfile
     parameter_value_convert '$prim_db_unique','$stb_db_unique'
     set db_unique_name='$stb_db_unique'
     set standby_file_management='AUTO'
     set log_archive_config='dg_config=($prim_db_unique,$stb_db_unique)'
     set log_archive_dest_2=''
     set fal_server='$prim_db_unique'
     set log_file_name_convert='/DB/${prim_sid}','/DB/${prim_sid}'
     DORECOVER
    nofilenamecheck;
    configure device type disk parallelism 1 backup type to backupset;
    exit" > $rman_cmd
  rman cmdfile=$rman_cmd 2>&1 | grep -v RMAN-05158 | grep -v ORA-01275 | tee $rman_log | LogStdIn
  rman_err=$(grep "RMAN-"  $rman_log | grep -v -i "WARNING")
  if [[ ! -z "$rman_err" ]]
  then
    rman_err_first_line=$(grep "RMAN-"  $rman_log | grep -v -i "WARNING" | head -1)
    LogError "Error: $rman_err_first_line"
    LogError "Log file: $rman_log"
    exit 1
  fi
  LogCons "Force open of standby $stb_db_unique in read only to create tempfiles."
  exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"alter database open read only;\""  > $ssh_log 2>&1
  #LogCons "Create the standby database $stb_db_unique init file."
  #exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"alter create spfile from memory;\""  >> $ssh_log 2>&1
  LogCons "Restart standby database $stb_db_unique on new init."
  #exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"shutdown immediate;\""  >> $ssh_log 2>&1
  exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"startup mount;\""   | tee -a $ssh_log
  cat $ssh_log
  LogCons "Wait 10 sec the broker to start...."
  sleep 10
}

# -------------------------------------------------------------------
# Configure the primary and standby environment for dataguard
# -------------------------------------------------------------------
function config_prim_for_dg() {
  LogCons "Force the SYS password on primary database $prim_db_unique"
  DoSqlQStrict "alter user sys identified by "$MmDp";"

  LogCons "Create password file."
  ${ORACLE_HOME}/bin/orapwd file=${ORACLE_HOME}/dbs/orapw$prim_sid force=y password=$MmDp

  # Set force logging if needed
  if [ "$force_logging" == "NO" ]; then
    LogCons "Set force logging on primary $prim_db_unique"
    DoSqlQStrict "alter database force logging;"
  fi

  LogCons "Create broker parameter files."
  BrokerDir="$OFA_BRO_ADMIN/${prim_sid}"
  LogCons "Create broker dir $BrokerDir"
  mkdir -p $BrokerDir >/dev/null 2>&1
  rm -f ${BrokerDir}/dr*.dat 2>&1
  exec_remote $stb_vip "mkdir -p $BrokerDir >/dev/null 2>&1"
  exec_remote $stb_vip "rm -f ${BrokerDir}/dr*.dat 2>&1"

  LogCons "Set broker file parameter."
  DoSqlQStrict "alter system set dg_broker_config_file1 = '${BrokerDir}/dr1${prim_sid}.dat' scope=both;"
  DoSqlQStrict "alter system set dg_broker_config_file2 = '${BrokerDir}/dr2${prim_sid}.dat' scope=both;"

  DoSqlQStrict "alter system set dg_broker_start=true scope=both;"
  DoSqlQStrict "alter system set log_archive_dest_2='' scope=both;"

  LogCons "Set/check remote_password_file."
  DoSqlQStrict "alter system set remote_login_passwordfile=exclusive scope=spfile;"

  LogCons "Set local listener to (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=$prim_vip)(PORT=${db_port})))"
  DoSqlQStrict "alter system set local_listener='(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=$prim_vip)(PORT=${db_port})))';"
  DoSqlQStrict "alter system register;"

  LogCons "Set fal_server parameter"
  DoSqlQStrict "alter system set fal_server='$stb_db_unique';"

  LogCons "Set archive_lag_target parameter"
  DoSqlQStrict "alter system set archive_lag_target=900;"

  # set db unique name and force the archivelog to avoid double restart
  DBUni=$(GetDbParam db_unique_name)
  if [ "$DBUni" != "$prim_db_unique" ] && [ "$force_flag" == "force" ]; then
    LogCons "Current db unique name is $DBUni. For dataguard db unique name must be $prim_db_unique. DB will be restarted."
    DoSqlQStrict "alter system set db_unique_name = $prim_db_unique scope=spfile;"
    DoSqlQStrict "shutdown immediate;"
    DoSqlQStrict "startup mount;"
    DoSqlQStrict "alter database archivelog;"
    DoSqlQStrict "alter open;"
  fi

  if [ $LogMode != "ARCHIVELOG" ] && [ "$force_flag" == "force" ]; then 
    LogCons "Switch archiving on. DB will be restarted."
    DoSqlQStrict $OFA_SQL/SwitchArcLogging.sql on
  fi

}

function config_sby_for_dg() {

  LogCons "Build on remote server ($stb_vip) directory $OFA_BRO_ADMIN/$prim_sid"
  exec_remote $stb_vip "mkdir -p $OFA_BRO_ADMIN/$prim_sid"

  exec_remote $stb_vip "mkdir -p /dbvar/${prim_sid}/log/adump"
  exec_remote $stb_vip "mkdir -p /dbvar/${prim_sid}/admin"

  LogCons "Copy password file to: $stb_vip"
  scp -q $ORACLE_HOME/dbs/orapw${ORACLE_SID} $stb_vip:$ORACLE_HOME/dbs/
  LogCons "Copy DB config file $config_file to: $stb_vip"
  scp -q $config_file $stb_vip:/dbvar/$prim_sid/admin/

  exec_remote $stb_vip "echo DB_NAME=$prim_sid > /tmp/temp_sby.ora"
  exec_remote $stb_vip "echo DB_UNIQUE_NAME=$stb_db_unique >> /tmp/temp_sby.ora"

  # update oratab if needed
  LogCons "Update Oratab on remote server with $prim_sid "
  out=$(exec_remote $stb_vip "grep -c "$prim_sid:" /etc/oratab")
  local_oratab_line=($(grep "$prim_sid:" /etc/oratab))

  LogCons "Line to add to remote oratab: $local_oratab_line"
  if [ "$out" == "0" ];then
    out=$(exec_remote $stb_vip "echo "$local_oratab_line" >> /etc/oratab")
  else
    exec_remote $stb_vip "grep -v $prim_sid /etc/oratab > /tmp/tmp_oratab"
    exec_remote $stb_vip "echo "$local_oratab_line" >> /tmp/tmp_oratab"
    exec_remote $stb_vip "cat /tmp/tmp_oratab > /etc/oratab"
  fi

  if [ "$is_multitenant" == "true" ]; then
    out=$(exec_remote $stb_vip "grep -c "${prim_sid}_PDB:" /etc/oratab")
    local_oratab_line=($(grep "${prim_sid}_PDB:" /etc/oratab))

    LogCons "Line to add to remote oratab: $local_oratab_line"
    if [ "$out" == "0" ];then
      out=$(exec_remote $stb_vip "echo "$local_oratab_line" >> /etc/oratab")
    else
      exec_remote $stb_vip "grep -v ${prim_sid}_PDB /etc/oratab > /tmp/tmp_oratab"
      exec_remote $stb_vip "echo "$local_oratab_line" >> /tmp/tmp_oratab"
      exec_remote $stb_vip "cat /tmp/tmp_oratab > /etc/oratab"
    fi
  fi

  # reatart the remote database in mount state
  LogCons "Restart the remote $stb_vip database in nomount state "
  exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"shutdown abort;\""  > $ssh_log 2>&1
  exec_remote $stb_vip  "OraEnv $prim_sid; DoSqlQStrict \"startup nomount pfile='/tmp/temp_sby.ora';\""  >> $ssh_log 2>&1
  cat $ssh_log
  
  LogCons "Clean remote files"
  exec_remote $stb_vip "rm -rf /arch/${stb_db_unique}/*"
  exec_remote $stb_vip "rm -rf /arch/${prim_sid}/*"
  exec_remote $stb_vip "rm -rf /DB/${prim_sid}/*"
  exec_remote $stb_vip "rm -rf /backup/${prim_sid}/*"


}

# -------------------------------------------------------------------
# Build the standy database entry point
# -------------------------------------------------------------------
function build_standby_database ()
{
  LogCons "Build standby database, Rebuild: $prim_sid"
  CheckVar prim_sid        \
  || Usage
  # clean the previous DG config if exist
  check_can_create_dg
  drop_prim_conf
  config_prim_for_dg
  config_stby_redo
  config_sby_for_dg
  config_listeners
  create_sby
  config_broker
  LogCons "Restart STANDBY database in MOUNT state."
  exec_remote $stb_vip "OraEnv $prim_sid; DoSqlQStrict \"startup force mount;\""  | tee -a $ssh_log
}

function check_dg_config ()
{
  LogCons "Validate the Dataguard configuration."
  LogCons "Command file: $broker_cmd"
  LogCons "Logfile:  $broker_cmd_out"
  echo "connect sys/${MmDp}@${prim_db_unique};" >  $broker_cmd
  echo "show configuration;"
  echo "validate network configuration for all;" >>  $broker_cmd
  echo "validate database verbose '${prim_db_unique}';" >>  $broker_cmd
  echo "validate database verbose '${stb_db_unique}';" >>  $broker_cmd
  dgmgrl -silent @$broker_cmd > $broker_cmd_out
  broker_err=$(grep ORA- $broker_cmd_out | grep -v ORA-16675)
  if [[ ! -z $broker_err ]]; then
    LogError "Error Config DG, Error: $broker_err"
    LogError "Log: $broker_cmd_out"
  fi
  sed -i "1s/.*/connect sys\/******@${prim_db_unique};/" $broker_cmd
  cat $broker_cmd
  cat $broker_cmd_out
}

function dg_switchover () 
{
  LogCons "Command file: $broker_cmd"
  LogCons "Logfile:  $broker_cmd_out"
  check_dg_config
  
  local cnt=$(grep -c "The static connect identifier allows for a connection to database"  $broker_cmd_out)
  if [ "$nb_err" != "2" ]; then 
    LogError "Cannot switchover. There are issues with the static connect identifier. Check logfile $broker_cmd_out"
    exit 1
  fi

  cnt=$(egrep -c "Ready for Switchover:[[:space:]]*Yes")
  if [ "$nb_err" != "1" ]; then 
    LogError "Cannot switchover. Database is not ready for switchover. Check logfile $broker_cmd_out"
    exit 1
  fi

  cnt=$(egrep -c "Gap Status:[[:space:]]*No Gap")
  if [ "$nb_err" != "1" ]; then 
    LogError "Cannot switchover. Gap is present. Check logfile $broker_cmd_out"
    exit 1
  fi

  LogCons "Redy for switchover"

}
#---------------------------------------------
# Main
#---------------------------------------------
# set -xv
LogCons " "
LogCons " "
LogCons "Running on host (uname -n): $my_hostname"

force_flag="noforce"

OPTSTRING="h:d:a:f:c:"

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    d)
      prim_sid=${OPTARG}
      ;;
    a)
      action=${OPTARG}
      ;;
    f)
      force_flag=$(echo ${OPTARG}  | tr '[:upper:]' '[:lower:]')
      ;;
    c)
      config_file=${OPTARG}
      ;;
    :)
      LogError "Option -${OPTARG} requires an argument."
      usage
      ;;
    h)
      usage
      ;;
    ?)
      LogError "Invalid option: -${OPTARG}."
      usage
      ;;
  esac
done
shift $((OPTIND -1))

# get some secrets
RunMmDp

# check that mandatory parameters are present
if [ -z "$prim_sid" ] || [ -z "$action" ]; then
  LogError "Parameters -d and -a are mandatory"
  usage
fi

if [ -z "$config_file" ]; then
  if [ -f "/dbvar/${prim_sid}/admin/config_db_$prim_sid.yml" ]; then
    config_file="/dbvar/${prim_sid}/admin/config_db_${prim_sid}.yml"
  else
    LogError "No config file provide. No default config file found."
    LogError "   searched for default in: /dbvar/${prim_sid}/admin/config_db_${prim_sid}.yml"
    exit 1
  fi
else
  if [ ! -f "$config_file" ]; then
    LogError "Given config file <$config_file> does not exist."
    exit 1
  fi
fi

LogCons "Use config file $config_file"

# set the environment for the database
OraEnv $prim_sid

# set the prim and standby unique name and vip's
set_names

# execute the script only on primary server
DBRole=$(DoSqlQStrict "select database_role from v\$database;")
LogCons "Database role is $DBRole"
if [ "$DBRole" != "PRIMARY" ]; then
  LogError "The script must be executed ONLY on primary server."
  exit 1
fi

check_is_omf is_omf
LogCons "Database is working in OMF (is_omf: $is_omf)"
# execute the actions
case ${action} in
  "build")
    build_standby_database
    ;;
  "check_dg_config")
    check_dg_config
    ;;
  "check_can_create")
    check_can_create_dg
    ;;
  "switchover")
    dg_switchover
    ;;
  *)
    LogError "Given action $action not known"
    usage
    ;;
esac

END_TIME=$(date +%s)
runtime=$((${END_TIME}-${START_TIME}))
runtime_human="$((runtime/60))m$((runtime%60))s"
LogCons "Script duration $runtime_human"
LogCons "End of action <$action>."