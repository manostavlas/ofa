#!/bin/bash

OFA_TAG="manage_audit_cli.sh"
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi
YesNo $(basename $0) || exit 1 && export RunOneTime=YES

unset ORACLE_PATH
unset SQLPATH
my_hostname=$(uname -n)
START_TIME=$(date +%s)

#---------------------------------------------
function usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: manage_audit_cli.sh [-h help] [-c config_file]
##
## SYNOPSYS: Configure the audit poptions on the database
##
## OPTIONS:
## -h                     This help
##
## -c                     The YAML config file keeping the options
## -f                     force: drop existent if exist. Otherwise it will stop.
##
## NOTE:                  The script can be executed on single instanmce or multitenant instance.
##                        If the script is executes a CDB level the PDB and all opened PDBS will be configured 
##
##                        The script will create the AUDIT_DATA tablespace and it will create the purge jop
##                        All audit fields for unified audit will be moved to thsi tablespaces
##
##                        The retention of audit is configured by the parameter
##                        audit.retention from the configuration file
##
##                        The database on which the action is executed is get by the parameter
##                        database.db_name of the configuration file
##
##
## EXAMPLE:
##                         manage_audit_cli.sh -c DBDEV1_config.yml
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

function manage_audit() {
  get_param "database.db_name" sid
  OraEnv ${sid}
  get_param "audit.retention" audit_retention
  LogCons "Configure the audit on the database $sid."
  LogCons "Audit retention is $audit_retention."
  DoSqlQStrict @$OFA_SQL/manage_unified_audit.sql $audit_retention | tee -a $sql_out
  LogCons "Audit JOB information: "
  DoSqlQStrict "select job_name, job_status, job_frequency from DBA_AUDIT_MGMT_CLEANUP_JOBS;"
  LogCons "Parameter of the audit:  "
  DoSqlQStrict "select parameter_name, parameter_value from DBA_AUDIT_MGMT_CONFIG_PARAMS where audit_trail='UNIFIED AUDIT TRAIL';"
}

OPTSTRING="h:c:"

while getopts ${OPTSTRING} opt; do
  case ${opt} in
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
if [ -z "$config_file" ]; then
  LogError "Parameter -c is mandatory"
  usage
fi

if [ ! -r $config_file ]; then
  LogError "Given control file <$config_file> does not exist."
  usage
fi

manage_audit


LogCons "Audit on $sid was succesfully configured."
# print execute time
END_TIME=$(date +%s)
runtime=$((${END_TIME}-${START_TIME}))
runtime_human="$((runtime/60))m$((runtime%60))s"
LogCons "Script duration $runtime_human"