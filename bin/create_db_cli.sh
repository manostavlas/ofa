#!/bin/bash

OFA_TAG="create_db_cli.sh"
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi
YesNo $(basename $0) || exit 1 && export RunOneTime=YES

unset ORACLE_PATH
unset SQLPATH
my_hostname=$(uname -n)
START_TIME=$(date +%s)
ORATAB="/etc/oratab"
force_flag="none"


#---------------------------------------------
function usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: create_db_cli.sh [-h help] [-a build | build_ubp_env] [-c config_file ] [-f force ]
##
## SYNOPSYS: Create a database
##
## OPTIONS:
## -h                     This help
## -a                     The action to be executed. This option is MANDATORY.
##                          build             : will build the database
##                          build_ubp_env     : rebuild the ubp environment in the database
##                                              the database will not be STOPPED
##                          clean             : remove all references for the database from the server
##                                            : use with caution. -f force flag must be used.
## -c                     The YAML config file keeping the options
## -f                     force: drop existent if exist. Otherwise it will stop.
##
## NOTE:                  The database creation will fail if
##                          * the FS are not present
##                          * the VIP are not create
##                          * the OMS is not reachable (firewall ports are not open)
##
##                        The config file is an YAML that can contain:
##                           * The database.init.spec section is the init parameters to be added to init*.ora file
##                             These parameters must be valid oracle parameters. The script do not validate them,
##                                but the database will fail to start if there are invalid parameters.
##                           * The init spec shoud contains only non default parameters (parameters that are in any case defined for all databases)
##                           * The init.common section contains parameter that are common for all databases. Normally this section should not be changed.
##
##                        The default vaules (word 'default' in config file) are for:
##                          database.port: 1555
##                          database.db_unique_name: {db_name}_01
##                          database.hostname: {dbname}01-vip
##                          database.characterSet: AL32UTF8
##                          database.nationalCharacterSet: AL16UTF16
##
##                        For the config file check template: $OFA_SCR/db_config_template.yml
##
##
## EXAMPLE:
##                         create_db_cli.sh -a build -d DBDEV1 -c DBDEV1_config.yml
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
# Set come global variables for the script
# -------------------------------------------------------------------
function set_glob_vars () {

  # fix these variable for the rest of the script
  get_param "database.port" db_port
  if [ "$db_port" == "default" ]; then
    db_port="1555"
  fi

  get_param "database.db_name" sid

  get_param "database.db_unique_name" db_unique_name
  if [ "$db_unique_name" == "default" ]; then
    db_unique_name=$(echo ${sid}_01  | tr '[:lower:]' '[:upper:]')
  fi

  get_param "database.hostname_vip" hostname_vip
  if [ "$hostname_vip" == "default" ]; then
    hostname_vip=$(echo ${sid}01-vip.corp.ubp.ch  | tr '[:upper:]' '[:lower:]')
  fi

  get_param "database.engine_path" engine_path

  # for an dict return cannot use get_param as it expands '  character
  dir_layout=$(read_config_file.py -a read -f $config_file -p database.dir_layout)

  get_param "database.multitenant" is_multitenant
  is_multitenant=$(echo $is_multitenant |  tr '[:upper:]' '[:lower:]'  )

  LogCons "Database installation resume parameters:"
  LogCons "================================"
  LogCons "Database name        : ${sid}"
  LogCons "Database unique name : ${db_unique_name}"
  LogCons "Port nb              : ${db_port}"
  LogCons "MultiTenant Database : ${is_multitenant}"
  LogCons "Hostname             : ${hostname_vip}"
  LogCons "Oracle engine        : ${engine_path}"
  LogCons "Disk Layout          : ${dir_layout}"
  LogCons "================================"
}

# -------------------------------------------------------------------
# Check the prereq are satisfied
# -------------------------------------------------------------------
function check_prereq () {

  # check some programs
  for cmd in nslookup python3 dig; do
    if ! command -v $cmd 2>&1 >/dev/null
    then
      LogError "Command $cmd cannot be found. STOP"
      exit 1
    fi
  done

  #check the Oracle installation
  LogCons "Check Oracle Engine Path $engine_path"
  if [ ! -d $engine_path ]; then
    LogError "Oracle installation path <$engine_path> found in $config_file does not exist.STOP"
    exit 1
  fi

  if [ ! -f $ORATAB ]; then
    LogCons "Oratab file $ORATAB does not exist. A new one will be created"
  else
    local  sid_exist=$(cat $ORATAB | grep -c ${sid})
    if [ "${sid_exist}" != "0" ]; then
      LogCons "WARNING: Database ${sid} exist in $ORATAB file."
      if [ "$force_flag" == "force" ]; then
        LogCons "   Force flag <force_flag: $force_flag> is used. CONTINUE."
      else
        LogError "   Force flag is not used <force_flag: $force_flag>. STOP."
        exit 1
      fi
    fi
  fi

  # get the disk layout
  local dir_list=$(python3 -c "for key,value in $dir_layout.items(): print(value);")
  for dir in $dir_list; do
    if [ ! -d "$dir/${sid}" ]; then
      LogError "Directory $dir/${sid} defined in fonfig file does not exist.STOP"
      exit 1
    fi
  done

  # check the ip config
  vip=$(dig +short $hostname_vip)
  if [ -z "$vip" ]; then
    LogError "The vip $hostname_vip canot be resolved. STOP"
    exit 1
  fi
  local is_local_ip=$(hostname --all-ip-addresses | grep -c $vip )
  if [ "$is_local_ip" != "1" ]; then
    LogError "The VIP $hostname_vip is not defined on local hostname. STOP"
    exit 1
  fi

  LogCons "Database server VIP: ${vip}"

}

# -------------------------------------------------------------------
# Remove an object file | directory | link
# -------------------------------------------------------------------
function remove_obj () {
  # be sure to remove only what exist

  local object=$1
  if [ -z "$object" ]; then
    LogError "Unable to remove an empty name file. Received parameter: <$object>"
    exit 1
  fi

  if [ -d "$object" ]; then
    LogCons "Remove directory: $object"
    rm -rf $object
    if [ "$?" != "0" ]; then
      LogError "Unable to remove directory $object ($?)"
      exit 1
    fi
  elif  [ -f "$object" ]; then
    LogCons "Remove file: $object"
    rm -f $object
    if [ "$?" != "0" ]; then
      LogError "Unable to remove file $object ($?)"
      exit 1
    fi
  elif [ -L "$object" ]; then
    LogCons "Remove simlynk: $object"
    rm -f $object
    if [ "$?" != "0" ]; then
      LogError "Unable to remove symlink $object ($?)"
      exit 1
    fi
  elif [ $(echo "$object" | grep -c "*") != "0" ]; then
      LogCons "Remove star (*) directory or file $object"
      rm -rf $object
  else
    LogCons "Unable to identify the object $object. Maybe not exist. SKIP"
  fi

}

# -------------------------------------------------------------------
# Remove all objects related to a database name
# -------------------------------------------------------------------
function clean_env() {
  # do not continue here if the force flag is not set
  if [ "$force_flag" == "force" ]; then
    LogCons " Force flag <force_flag: $force_flag> is used. CONTINUE."
  else
    LogError " Force flag is not used <force_flag: $force_flag>. STOP."
    exit 1
  fi

  local  sid_exist=$(cat $ORATAB | grep -c ${sid})

  if [ "${sid_exist}" != "0" ]; then
    LogCons "The database ${sid} exist in $ORATAB. Remove it from the file."
    LogCons "Force shutdown of ${sid} database"
    local tmp_oratab="/tmp/tmp_oratab"
    # force a shutdown abort of the database
    OraEnv ${sid}
    DoSqlQStrict "shutdown abort;"
    # remove the line from oratab if exist
    cp $ORATAB ${tmp_oratab}
    if [ "$?" != "0" ]; then
      LogError "Unable to update oratab (copy to ${tmp_oratab})"
      exit 1
    fi
    sed -i "/${sid}/d" ${tmp_oratab}
    cp ${tmp_oratab} $ORATAB
    if [ "$?" != "0" ]; then
      LogError "Unable to update oratab (copy to /etc/oratab)"
      exit 1
    fi
  fi

  # get the disk layout and remove data files. This is dangerous
  local dir_list=$(python3 -c "for key,value in $dir_layout.items(): print(value);")
  for dir in $dir_list; do
    remove_obj "$dir/${sid}/*"
  done

  # remove files in $ORACLE_HOME/dbs
  for fl in $engine_path/dbs/*${sid}*; do
    remove_obj $fl
  done

  # remove  directory in diag of $ORACLE_HOME
  local sid_lower=$(echo "${sid}" |  tr '[:upper:]' '[:lower:]' )
  remove_obj $engine_path/log/diag/rdbms/${sid_lower}

  # remove other files
  remove_obj /oracle/${sid}
  remove_obj /oracle/admin/${sid}
  remove_obj /oracle/audit/${sid}
  remove_obj /oracle/diag/rdbms/${sid_lower}
  remove_obj "$engine_path/log/diag/rdbms/${sid_lower}_*"

  # remove all other files that can be found
  files=$(find $engine_path -name *${sid}* -print)
  for fl in $files; do
    remove_obj $fl
  done

  LogCons "Remove listener configuration "
  $OFA_BIN/listener_adm_cli.sh -a remove -d $sid
  $OFA_BIN/listener_adm_cli.sh -a stop -d $sid
  LogCons "Remove tnsnames configuration "
  $OFA_BIN/tnsnames_adm_cli.sh -a remove -d $sid
}

# -------------------------------------------------------------------
# Build all needed directories for the database
# -------------------------------------------------------------------
function build_dirs ()
{
  # get the disk layout and remove data files. This is dangerous
  local dir_list=$(python3 -c "for key,value in $dir_layout.items(): print(value);")
  for dir in $dir_list; do
    # be sure to remove only what exist
    if [ ! -d "$dir/${sid}" ]; then
      LogCons "Create directory  $dir/${sid} "
      mkdir -p $dir/${sid}
    fi
  done

  for dir in "/oracle/admin/${sid}/adump" \
            "/oracle/admin/${sid}/dpdump" \
            "/oracle/admin/${sid}/pfile" \
            "/oracle/admin/${sid}/xdb_wallet" \
            "/oracle/audit/${sid}" \
            "/dbvar/$sid/log/cdump" \
            "/dbvar/$sid/admin"; do
    if [ ! -d "$dir" ]; then
      LogCons "Create directory:     $dir "
      mkdir -p $dir
    fi
  done
}

# -------------------------------------------------------------------
# Create the database
# -------------------------------------------------------------------
function create_database() {

  # unset these as make databaptch never ends because is waiting for a fixed string and SQLPATH
  # leads to unnexpected output when database is not started
  unset ORACLE_PATH
  unset SQLPATH

  local time_stamp=$(date +"%H%M%S")
  local dbca_out=$OFA_LOG/tmp/${OFA_TAG}.dbca_cmd_out.$$.$PPID.$time_stamp.log

  get_param "database.characterSet" characterSet
  if [ "$characterSet" == "default" ]; then
    characterSet="AL32UTF8"
  fi

  get_param "database.nationalCharacterSet" nationalCharacterSet
  if [ "$nationalCharacterSet" == "default" ]; then
    nationalCharacterSet="AL16UTF16"
  fi

  local par_lst=$(read_config_file.py -a read -f $config_file -p database.init.spec)
  local init_par_lst=$(python3 -c "print(','.join(f'{key}={value}' for key,value in $par_lst.items()))")
  par_lst=$(read_config_file.py -a read -f $config_file -p database.init.common)
  local init_common_lst=$(python3 -c "print(','.join(f'{key}={value}' for key,value in $par_lst.items()))")

  get_param "database.dir_layout.arch" arch_path
  get_param "database.dir_layout.data" data_path
  get_param "database.recoveryAreaSize" recovery_area_sz

  # prevent lower upper before test
  multitenant_options=""
  if [ "$is_multitenant" == "true" ]; then
    multitenant_options="\
    -pdbName ${sid}_PDB \
    -pdbAdminPassword "${MmDp}" \
    -useLocalUndoForPDBs true \
    -numberOfPDBs 1 \
    -createAsContainerDatabase true"
  fi

  # ATTENTION: having spaces in initParams option list, can lead to unpredictible behaviour of dbca.
  #   e.g. construct datafiles in wrong paths, ignoring some parameters, etc.
  local cmd="$engine_path/bin/dbca -silent \
  -ignorePreReqs \
  -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbName ${sid} \
  -sid  ${sid} \
  -systemPassword "${MmDp}" \
  -sysPassword "${MmDp}" \
  -emConfiguration NONE \
  -datafileDestination $data_path/${sid} \
  -storageType FS \
  -useOMF true \
  -characterSet $characterSet \
  -redoLogFileSize 500 \
  -listeners LISTENER_${sid} \
  -recoveryAreaDestination $arch_path/${sid} \
  -recoveryAreaSize $recovery_area_sz \
  -enableArchive true \
  -databaseType MULTIPURPOSE \
  -nationalCharacterSet $nationalCharacterSet \
  -initParams audit_file_dest=/dbvar/${sid}/log/adump,db_create_online_log_dest_1=${arch_path}/${sid},db_unique_name=${db_unique_name},db_name=${sid},$init_common_lst,$init_par_lst \
  $multitenant_options"

  # anonymise the commans by removing the password
  local ano_cmd=$(echo "$cmd" | sed "s/${MmDp}/******/g")
  LogCons "Create database with the command: $ano_cmd"
  LogCons "Log files are located in: ls -ltr /oracle/cfgtoollogs/dbca/${sid}/trace.log_* | tail -n1"
  LogCons "     and $dbca_out"
  LogCons "     and /oracle/cfgtoollogs/sqlpatch for sqlpatch "
  $cmd | tee -a $dbca_out
  local err=$(grep -c "FATAL" $dbca_out)
  if [ "$err" != "0" ]; then
    LogError "Failed to create database. ($?)"
    exit 1
  fi
  if [ "$is_multitenant" == "true" ]; then
    LogCons "Update oratab with PDB information for ${sid}_PDB"
    echo "${sid}_PDB:${engine_path}:PDB" >> $ORATAB
    LogCons "Set the limit max_pdbs to 3"
    DoSqlQStrict "alter system set max_pdbs=3 scope=both;"
  fi
}

function create_init_file() {
  LogCons "Move the spfile in /dbvar/${sid}/admin/ directory"
  if [ -f "$engine_path/dbs/spfile${sid}.ora" ]; then
    mv $engine_path/dbs/spfile${sid}.ora /dbvar/${sid}/admin/
    if [ "$?" != "0" ]; then
      LogError "Unnable to move: cp $engine_path/dbs/spfile${sid}.ora /dbvar/${sid}/admin/"
      exit 1
    fi
  else
    LogError "Unnable to find init file : $engine_path/dbs/spfile${sid}.ora "
    exit 1
  fi

  LogCons "Create the generic  $engine_path/dbs/init${sid}.ora directory"
  echo "spfile='/dbvar/\${ORACLE_SID}/admin/spfile\${ORACLE_SID}.ora'" >> $engine_path/dbs/init${sid}.ora
  if [ "$?" != "0" ]; then
    LogError "Unable to create generic init file : $engine_path/dbs/init${sid}.ora"
    exit 1
  fi
}

function create_init_file() {
  LogCons "Move the spfile in /dbvar/${sid}/admin/ directory"
  if [ -f "$engine_path/dbs/spfile${sid}.ora" ]; then
    mv $engine_path/dbs/spfile${sid}.ora /dbvar/${sid}/admin/
    if [ "$?" != "0" ]; then
      LogError "Unnable to move: cp $engine_path/dbs/spfile${sid}.ora /dbvar/${sid}/admin/"
      exit 1
    fi
  else
    LogError "Unnable to find init file : $engine_path/dbs/spfile${sid}.ora "
    exit 1
  fi

  LogCons "Create the generic  $engine_path/dbs/init${sid}.ora directory"
  echo "spfile='/dbvar/\${ORACLE_SID}/admin/spfile\${ORACLE_SID}.ora'" >> $engine_path/dbs/init${sid}.ora
  if [ "$?" != "0" ]; then
    LogError "Unable to create generic init file : $engine_path/dbs/init${sid}.ora"
    exit 1
  fi
}

# -------------------------------------------------------------------
# Reconfigure the redologs
# -------------------------------------------------------------------
function reconfig_redologs() {
  LogCons "Reconfig Redologs...."
  get_param "database.dir_layout.arch" arch_path
  # by default the dataabse is created with 3 redologs with 2 members.
  # reconfigure it for using one member
  LogCons " ... Put database in mount state"
  #  to remove redologs the shutdown must be forcely immediate
  DoSqlQStrict "shutdown immediate;"
  DoSqlQStrict "startup mount;"

  for idx in 4 5 6; do
    count=$(DoSqlQStrict "select count(*) from v\$logfile where group#=${idx};" | tr -d '[:space:]' )
    LogCons " ... Add logfile group $idx"
    if [ "$count" != "0" ]; then
      DoSqlQStrict "alter database clear unarchived logfile group $idx;"
      DoSqlQStrict "alter database drop logfile group $idx;"
    fi
    DoSqlQStrict "alter database add logfile group $idx size 500M;"
  done
  LogCons " ... Open database"
  DoSqlQStrict "alter database open;"

}

# -------------------------------------------------------------------
# Configure the listener and tnsnames files
# -------------------------------------------------------------------
function config_net_layer () {
  LogCons "Config Oracle Net Layer"
  $OFA_BIN/listener_adm_cli.sh -a add -d $sid -m $hostname_vip -p $db_port
  $OFA_BIN/listener_adm_cli.sh -a restart -d $sid
  $OFA_BIN/tnsnames_adm_cli.sh -a update -d $sid -m $hostname_vip -p $db_port -s $sid

  LogCons "Check listener.ora and tnenames.ora links"
  for fl in tnsnames.ora listener.ora; do
    if [ ! -L "$engine_path/network/admin/$fl" ]; then
      rm -f "$engine_path/network/admin/$fl"
      ln -s $OFA_TNS_ADMIN/$fl "$engine_path/network/admin/"
    fi
  done

  LogCons "Add entry for catalog database if does not exist"
  $OFA_BIN/tnsnames_adm_cli.sh -a update -d RCDPRD  -m RCDPRD-vip -p 1555 -s RCDPRD
}

function config_orapwd() {
  LogCons "Create orapwd file"
  ${engine_path}/bin/orapwd file=${engine_path}/dbs/orapw${sid} force=y password=$MmDp
  if [ "$?" != "0" ]; then
    LogError "Error creating the ${engine_path}/dbs/orapw${sid}  file."
    exit 1
  fi
}

# -------------------------------------------------------------------
# Create all UBP user objects
# -------------------------------------------------------------------
function create_ubp_env() {
  local time_stamp=$(date +"%H%M%S")
  local sql_out=$OFA_LOG/tmp/${OFA_TAG}.sql_script_cmd_out.$$.$PPID.$time_stamp.log
  LogCons "Logfile: $sql_out"
  LogCons "Create password check function on container."
  DoSqlQStrict @$OFA_SQL/cre_pw_check_functions_cdb.sql | tee -a $sql_out
  LogCons "Create UBP user C##UBP_ADMIN environment"
  DoSqlQStrict @$OFA_SQL/cre_ubp_env_user_cdb.sql | tee -a $sql_out

  pdb_list=$(DoSqlQStrict "select name from v\$pdbs where open_mode  = 'READ WRITE';")
  for pdb in $pdb_list; do
    LogCons "Create password check function on PDB $pdb."
    ORACLE_PDB_SID=$pdb DoSqlQStrict @$OFA_SQL/cre_ubp_env_user_cdb.sql | tee -a $sql_out
  done
  LogCons "Create common profiles"
  DoSqlQ @$OFA_SQL/cre_profiles_cdb.sql | tee -a $sql_out

  LogCons "Create database directories"
  DoSqlQStrict "create or replace directory data_pump_dir as '$OFA_DB_BKP/$sid/datapump';"  | tee -a $sql_out

  LogCons "Configure database listener parameter"
  DoSqlQStrict "alter system set local_listener='LISTENER_$sid';" | tee -a $sql_out

  if [ "$is_multitenant" == "true" ]; then
    LogCons "Open all pluggable databases and save the state"
    DoSqlQStrict "alter pluggable database all open;" | tee -a $sql_out
    DoSqlQStrict "alter pluggable database all save state;" | tee -a $sql_out
  fi

  LogCons "Configure the dbsnmp user"
  DoSqlQStrict "alter user dbsnmp identified by ${MmDp};" | tee -a $sql_out
  DoSqlQStrict "alter user dbsnmp account unlock;" | tee -a $sql_out

  LogCons "Set the core_dump_dest parameter"
  DoSqlQStrict "alter system set core_dump_dest='/dbvar/$sid/log/cdump;'" | tee -a $sql_out

  LogCons "Set the log_archive_format parameter"
  DoSqlQStrict "alter system set log_archive_format='${sid}_%t_%s_%r.arc' scope=spfile;" | tee -a $sql_out

  local err_cnt=$(grep -c "ORA-" $sql_out)
  if [ "$err_cnt" != "0" ]; then
    LogError "ORA-* Errors in file $sql_out"
    exit 1
  fi
}

# -------------------------------------------------------------------
# Configure audit
# -------------------------------------------------------------------
function manage_audit () {

  LogCons "Configure audit options"
  is_pure_unified=$(DoSqlQStrict "select value from v\$option where parameter='Unified Auditing';" | tr -d '[:space:]' )
  LogCons "Pure unified is used: <$is_pure_unified>"

  get_param "audit.retention" audit_retention
  LogCons "Configure audit retention to <$audit_retention> days"

  DoSqlQStrict @$OFA_SQL/manage_unified_audit.sql $audit_retention | tee -a $sql_out

}
# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
LogCons "Running on host (uname -n): $my_hostname"

OPTSTRING="h:f:a:c:"

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    a)
      action=${OPTARG}
      ;;
    c)
      config_file=${OPTARG}
      ;;
    f)
      force_flag=$(echo ${OPTARG}  | tr '[:upper:]' '[:lower:]')
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
if [ -z "$action" ] || [ -z "$config_file" ]; then
  LogError "Parameters -a and -c are mandatory"
  usage
fi

if [ ! -r $config_file ]; then
  LogError "Given control file <$config_file> does not exist."
  usage
fi

set_glob_vars

case ${action} in
  "build")
    check_prereq
    clean_env
    build_dirs
    config_net_layer
    create_database
    OraEnv ${sid}
    create_init_file
    reconfig_redologs
    config_orapwd
    create_ubp_env
    manage_audit
    LogCons "Final restart"
    DoSqlQStrict "startup force;"
    ;;
  "build_ubp_env")
    OraEnv ${sid}
    create_ubp_env
    ;;
  "clean")
    clean_env
    ;;
  * )
    LogError "Unknown given action: $action"
    usage
    ;;
esac
LogCons "Database $sid and it's environment succesfully was created."
# print execute time
END_TIME=$(date +%s)
runtime=$((${END_TIME}-${START_TIME}))
runtime_human="$((runtime/60))m$((runtime%60))s"
LogCons "Script duration $runtime_human"
