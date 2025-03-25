#!/bin/bash
OFA_TAG="tnsnames_adm_cli"
unset OFA_CONS_VOL
if [ "$OFA_STD_SETTINGS_LOADED" != "1" ]; then
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
fi

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

TNSNAMES_ORA="${OFA_TNS_ADMIN}/tnsnames.ora"

# Ensure the file existsadrci 
if [[ ! -f "$TNSNAMES_ORA" ]]; then
    LogCons "$TNSNAMES_ORA missing. Create the first one"
    echo "#--------------------------------------------" > $TNSNAMES_ORA
    echo "# Generated file by tnsnames_adm_cli.sh script" >> $TNSNAMES_ORA
    echo "# Do NOT edit manually. " >> $TNSNAMES_ORA
    echo "#--------------------------------------------" >> $TNSNAMES_ORA
fi

# Function to check if an entry exists
entry_exists() {
    local alias=$(echo "$1" |  tr '[:lower:]' '[:upper:]')
    return $(grep -q "^\s*$alias\s*=" "$TNSNAMES_ORA")
}

# Function to add an entry in one line if it does not exist
add_entry() {
    LogCons "Add entry  Alias:'$alias' Host:'$host' Port:'$port' UniqueName:'$service_name'"

    if entry_exists "$alias"; then
        LogCons "Entry '$alias' already exists in $TNSNAMES_ORA. SKIP."
    else
        echo "$alias=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host)(PORT=$port))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$service_name)))" >> "$TNSNAMES_ORA"
        echo "LISTENER_$alias=(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=$host)(PORT=$port)))" >> "$TNSNAMES_ORA"
        LogCons "Entry '$alias' added successfully."
        return 0
    fi
}

# Function to remove an entry
remove_entry() {
    if ! entry_exists "$alias"; then
        LogCons "Entry '$alias' missing from $TNSNAMES_ORA. Nothing to do."
    else
        # Backup original file
        cp "$TNSNAMES_ORA" "${TNSNAMES_ORA}.bak"
        # Remove the matching line
        sed -i "/^$alias\s*=/d" "$TNSNAMES_ORA"
        sed -i "/^LISTENER_$alias\s*=/d" "$TNSNAMES_ORA"
        LogCons "Entry '$alias' removed successfully."
    fi

}

# Function to search for an entry
search_entry() {
    grep "^\s*$alias\s*=" "$TNSNAMES_ORA"
}

# Function to check all TNS entries using tnsping
check_entries() {
    LogCons "Checking all TNS entries in $TNSNAMES_ORA ..."
    grep -o "^[A-Za-z0-9_]\+\s*=" "$TNSNAMES_ORA" | sed 's/=//' | while read -r alias; do
        if tnsping "$alias" > /dev/null 2>&1; then
            LogCons "Checking $alias ...  ✅ Connection OK"
        else
            LogCons "Checking $alias ...❌ Connection FAILED"
        fi
    done
}

#---------------------------------------------
function usage ()
#---------------------------------------------
{
LogCons "
#
##
## Usage: manage_tnsnames.ora [-h help] [-a build|check|update|remove] [-d <database_name> ] [-m hostname] [-p port] -s [service_name]
##
## SYNOPSYS: Create a standby (Data Guard) database.
##
## OPTIONS:
## -h                     This help
## -a                     The action to be executed. This option is MANDATORY.
##                            add    : add an entry. If the entry exist it will exit.
##                            remove : remove an entry. If the entry does not exist it will exit
##                            update : remove an entry and add it with the new parameters
##                            check  : check that tnsnames.ora file is correctly defined with all entries on only one line
## -d                     The database name for the tnsnames. The entry in the tnsnames.ora will be <dbname>=
## -m                     The hostname. This option is MANDATORY for 'add | update' actions.
## -p                     The port to be used. If not used 1555 will be used.
## -s                     The service.
##
## NOTE:                  The script will change the tnsnames.ora file by adding each entry on one line.
##                        Do not edit tnsnames.ora manually.
##
## EXAMPLE:
##                   Add a new tnsnames on port 1555
##                       $OFA_BIN/tnsnames_adm_cli.sh -a add -d DBDEV1 -m DBDEV101-VIP -s- DBDEV101
##                   Remove a n tnsnames alias
##                       $OFA_BIN/tnsnames_adm_cli.sh -a remove -d DBDEV1

##"
exit 22
}


LogCons "File used: $TNSNAMES_ORA"
# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
OPTSTRING="h:a:d:m:p:s:"

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
    s)
      service_name=$(echo "${OPTARG}" |  tr '[:lower:]' '[:upper:]')
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
      if [ -z "$service_name" ]; then
        LogError "-s Manadatory parameters is missing."
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
    check_entries
    ;;
  * )
    LogError "Unknown given action: $action"
    usage
    ;;
esac
# remove 2 blanc lines consecutives
sed -i '/^$/N;/^\n$/D' $TNSNAMES_ORA