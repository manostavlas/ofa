#!/bin/bash


OFA_TAG="listener_adm_cli"
unset OFA_CONS_VOL
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi


#---------------------------------------------
function usage ()
#---------------------------------------------
{
LogCons "
#
##
## Usage: listener_adm_cli.sh [-h help] [-a add|remove|update|start|stop|restart] [-d <database_name> ] [-m hostname] [-p port] -s [service_name]
##
## SYNOPSYS: Create a standby (Data Guard) database.
##
## OPTIONS:
## -h                     This help
## -a                     The action to be executed. This option is MANDATORY.
##                            add    : add an entry. If the entry exist it will exit.
##                            remove : remove an entry. If the entry does not exist it will exit
##                            update : remove an entry and add it with the new parameters
##                            check  : check that listener.ora file is correctly defined with all entries on only one line
##                            start  : start the lsitener for the given database
##                            stop   :  stop the listener for the given database
##                            restart: Restart  the listener for the given database
## -d                     The database name for the listener. The entry in the listener.ora will be LISTENER_<dbname>
## -m                     The hostname. This option is MANDATORY for 'add | update' actions.
## -p                     The port to be used. If not used 1555 will be used.
## -u                     The db_unique_name. This is used to add also the static DGMGRL_db_unique_name
##                           static service for dataguard
##
## NOTE:                  The script will change the listener.ora file by adding each entry on one line.
##                        Do not edit listener.ora manually.
##
## EXAMPLE:
##                   Add a new listener on port 1555
##                       $OFA_BIN/listener_adm_cli.sh -a add -d DBDEV1 -m DBDEV101-VIP
##                   Add a new listener with the DGMRL service for dataguard
##                       $OFA_BIN/listener_adm_cli.sh -a add -d DBDEV1 -m DBDEV101-VIP -u DBDEV101
##                   Remove a listener
##                       $OFA_BIN/listener_adm_cli.sh -a remove -d DBDEV1

##"
exit 22
}

LISTENER_ORA="${OFA_TNS_ADMIN}/listener.ora"

# Ensure the file exists
if [[ ! -f "$LISTENER_ORA" ]]; then
    LogCons "$LISTENER_ORA does not exist. Create the first one"
    echo "#--------------------------------------------" > $LISTENER_ORA
    echo "# Generated file by listener_adm_cli.sh script" >> $LISTENER_ORA
    echo "# Do NOT edit manually. " >> $LISTENER_ORA
    echo "#--------------------------------------------" >> $LISTENER_ORA
fi

# Function to check if an entry exists
function entry_exists() {
    return $(grep -q "^\s*LISTENER_$alias\s*=" "$LISTENER_ORA")
}

# Function to add an entry in one line if it does not exist
function add_entry() {
    LogCons "Add entry  Alias:'$alias' Host:'$host' Port:'$port' UniqueName:'$unique_name'"
    if entry_exists "$alias"; then
        LogCons "Entry '$alias' already exists in $LISTENER_ORA . SKIP."
    else
        echo "" >> "$LISTENER_ORA"
        echo "LISTENER_$alias=(DESCRIPTION_LIST=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host)(PORT=$port))(ADDRESS=(PROTOCOL=IPC)(KEY=EXTPROC_$alias))))" >> "$LISTENER_ORA"
        if [ -n "$unique_name" ]; then
          echo "SID_LIST_LISTENER_$alias=(SID_LIST=(SID_DESC=(GLOBAL_DBNAME=${unique_name}_DGMGRL)(SID_NAME=$alias))(SID_DESC=(SID_NAME=$alias)))" >> "$LISTENER_ORA"
        else 
          echo "SID_LIST_LISTENER_$alias=(SID_LIST=(SID_DESC=(SID_NAME=$alias)))" >> "$LISTENER_ORA"
        fi
        echo "ADR_BASE_LISTENER_$alias=/dbvar/$alias" >> "$LISTENER_ORA"
        echo "USE_SID_AS_SERVICE_LISTENER_$alias = on"
        LogCons "Entry '$alias' added successfully."
    fi
}

# Function to remove an entry
function remove_entry() {
    if ! entry_exists "$alias"; then
        LogCons "Entry '$alias' missing from $LISTENER_ORA . SKIP"
    else
        # Backup original file
        cp "$LISTENER_ORA" "${LISTENER_ORA}.bak"
        # Remove the matching line
        sed -i "/^SID_LIST_LISTENER_$alias\s*=/d" "$LISTENER_ORA"
        sed -i "/^LISTENER_$alias\s*=/d" "$LISTENER_ORA"
        sed -i "/^ADR_BASE_LISTENER_$alias\s*=/d" "$LISTENER_ORA"
        sed -i "/^USE_SID_AS_SERVICE_LISTENER_$alias\s*=/d" "$LISTENER_ORA"
        LogCons "Entry '$alias' removed successfully."
    fi
}

# Verify that the listener. ora file is correct (all entries on one line)
function check_lsitener_file() {
  invalid_lines=$(grep -Ev '^\s*$|^#' "$LISTENER_ORA" | grep -v '^LISTENER_' | grep -v '^SID_LIST_LISTENER_' | grep -v '^ADR_BASE_LISTENER_' )
  if [ -n "$invalied_lines" ]; then 
    LogError "$LISTENER_ORA contains invalid lines: "
    LogError "$invalied_lines"
    exit 1
  else 
    LogCons "File $LISTENER_ORA is correct <$invalied_lines>"
  fi
}

function check_listener_status() {
  local cmd_out
  local status="UNDEF"
  local _ret_val=$1

  if ! command -v lsnrctl 2>&1 >/dev/null
  then
    LogCons "Comand lsnrctl could not be found."
    exit 1
  fi
  # check listener exist
  cmd_out=$(lsnrctl status LISTENER_$alias | grep -c TNS-01101)
  if [ "$cmd_out" != "0" ]; then
    LogCons "Listener LISTENER_$alias  cannot be found."
    exit 1
  fi

  # check listener is started
  cmd_out=$(lsnrctl status LISTENER_$alias | grep -c TNS-12541)
  if [ "$cmd_out" != "0" ]; then
    status="DOWN"
  fi

  # check if listener is up
  cmd_out=$(lsnrctl status LISTENER_$alias | grep -c 'Listening Endpoints Summary')
  if [ "$cmd_out" == "1" ]; then
    status="UP"
  fi
  LogCons "Listener LISTENER_$alias status is <$status>."
  eval $_ret_val="'$status'"

}

function start_listener() {
  check_listener_status listener_state
  if [ "$listener_state" == "DOWN" ]; then 
    lsnrctl start LISTENER_$alias
    if [ "$?" != 0  ]; then 
      LogError "Failed to start listener LISTENER_$alias"
      exit 1;
    fi
  else
    LogCons "Listener LISTENER_$alias already started. SKIP"
  fi
}

function stop_listener() {
  check_listener_status listener_state
  if [ "$listener_state" == "UP" ]; then 
    lsnrctl stop LISTENER_$alias
    if [ "$?" != 0  ]; then 
      LogError "Failed to start listener LISTENER_$alias"
      exit 1;
    fi
  else
    LogCons "Listener LISTENER_$alias already stopped. SKIP"
  fi
}

LogCons "File used: $LISTENER_ORA"
# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
OPTSTRING="h:a:d:m:p:u:"

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    a)
      action=${OPTARG}
      ;;
    d)
      alias=$(echo "${OPTARG}" |  tr '[:lower:]' '[:upper:]')
      ;;
    m)
      host=${OPTARG}
      ;;
    p)
      port=${OPTARG}
      ;;
    u)
      unique_name=$(echo "${OPTARG}" |  tr '[:lower:]' '[:upper:]')
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


if [ -z "$action" ]; then
  LogError "Parameters -a is MANDATORY "
  usage
fi

case "$action" in
  "add"|"update" )
      echo "$action"
      if [ -z "$alias" ]; then 
        LogError "-d Manadatory parameters is missing."
        usage
      fi
      if [ -z "$host" ]; then
        LogError "-m Manadatory parameters is missing."
        usage
      fi
      if [ -z "$port" ];then
        port=1555
      fi
      if [ "$action" == "add" ];then
        add_entry
      fi
      if [ "$action" == "update" ];then
        remove_entry
        add_entry
      fi
      ;;
  "remove")
    if [ -z "$alias" ]; then 
        LogError "-d Manadatory parameters is missing."
        usage
      fi
    remove_entry
    ;;
  "check")
    check_lsitener_file
    ;;
  "start")
    start_listener
    ;;
  "stop")
    stop_listener
    ;;
  "restart")
    stop_listener
    start_listener
    ;;
  * )
    LogError "Unknown given action: $action"
    usage
    ;;
esac
# remove 2 blanc lines consecutives
sed -i '/^$/N;/^\n$/D' $LISTENER_ORA
