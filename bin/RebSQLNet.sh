#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

 YesNo $(basename $0) || exit 1 && export RunOneTime=YES

usage ()

{
cat << __EOF
#
##
## Usage: "RebSQLNet.sh" [ADD, TNS or NEW] <SID> <PORT> <HOST> 
## 
## Parameter 1: "ADD" Add entry in the tnsnames and listener files
##              "TNS" Adding entry in the tnsnames
##		"NEW" Create new tnsnames and listener files
##
## Paramater 2: <SID> Database name to be add the tnsnames and/or listener files 
##	        REMARK: Have to be set if using option TNS or ADD
##
##
## Paramater 3: Optional: PORT NUMBER, Only valid with P1=ADD
##
## Paramater 4: Optional: HOST NAME, Only valid with P1=ADD
##
## If the <SID> parameter is NOT set all database in the /etc/oratab file 
## will be configurated in the tnsnames and listener files.
## 
## Reading the host name and port number from LDAP if entry for the 
## Database exist in the LDAP server.
##
## Using the SQL*net templates in ../script/creation/TNS_TEMPLATE
## for the entries in the the tnsnames and listener files
##
#
__EOF
}
# set -vx

ScriptName=$(basename $0)
export OFA_TNS_ADMIN_NEW=$OFA_TNS_ADMIN
OFA_MAIL_RCP_BAD="no mail"
StartTime=`date +%Y_%m_%d_%H%M%S`
OraDbList=$(ListOraDbs | grep -v OEMAGENT | sort)
WhoAmI=$(whoami)
Action=$1
Para2OraSid=$2
StartDate=$(date +%Y%m%d%H%M%S)
NoRestart=$(echo $* | grep NoRestart)
echo "OFA_TNS_ADMIN_NEW: $OFA_TNS_ADMIN_NEW"

if [[ "$Action" == "NEW" ]] || [[ "$Action" == "ADD" ]] || [[ "$Action" == "TNS" ]] 
then
	if [ -f $OFA_TNS_ADMIN_NEW/sqlnet.ora ] ; then
       		 move_old.sh $OFA_TNS_ADMIN_NEW/sqlnet.ora $OFA_TNS_ADMIN_NEW/sqlnet.ora.${StartTime}
	fi

	if [ -f $OFA_TNS_ADMIN_NEW/ldap.ora ] ; then
	        move_old.sh $OFA_TNS_ADMIN_NEW/ldap.ora $OFA_TNS_ADMIN_NEW/ldap.ora.${StartTime}
	fi

	if [ -f $OFA_TNS_ADMIN_NEW/listener.ora ] ; then
	        move_old.sh $OFA_TNS_ADMIN_NEW/listener.ora $OFA_TNS_ADMIN_NEW/listener.ora.${StartTime}
	fi

	if [ -f $OFA_TNS_ADMIN_NEW/tnsnames.ora ] ; then
	        move_old.sh $OFA_TNS_ADMIN_NEW/tnsnames.ora $OFA_TNS_ADMIN_NEW/tnsnames.ora.${StartTime}
	fi
fi


if [ ! -d $OFA_TNS_ADMIN ] ; then
	mkdir -p $OFA_TNS_ADMIN
fi

if [ -f $ORACLE_HOME/network/admin/listener.ora ] && [ ! -L $ORACLE_HOME/network/admin/listener.ora ] ; then
                mv $ORACLE_HOME/network/admin/listener.ora $ORACLE_HOME/network/admin/listener.ora.${StartDate}
fi

if [ -f $ORACLE_HOME/network/admin/tnsnames.ora ] && [ ! -L $ORACLE_HOME/network/admin/tnsnames.ora ] ; then
                mv $ORACLE_HOME/network/admin/tnsnames.ora $ORACLE_HOME/network/admin/tnsnames.ora.${StartDate}
fi

if [ -f $ORACLE_HOME/network/admin/sqlnet.ora ] && [ ! -L $ORACLE_HOME/network/admin/sqlnet.ora ] ; then
                mv $ORACLE_HOME/network/admin/sqlnet.ora $ORACLE_HOME/network/admin/sqlnet.ora.${StartDate}
fi


if [ ! -L $ORACLE_HOME/network/admin/listener.ora ] ; then 
	ln -sf $OFA_TNS_ADMIN/listener.ora $ORACLE_HOME/network/admin/listener.ora
fi	

if [ ! -L $ORACLE_HOME/network/admin/tnsnames.ora ] ; then
	        ln -sf $OFA_TNS_ADMIN/tnsnames.ora $ORACLE_HOME/network/admin/tnsnames.ora
fi

if [ ! -L $ORACLE_HOME/network/admin/sqlnet.ora ] ; then
        ln -sf $OFA_TNS_ADMIN/sqlnet.ora $ORACLE_HOME/network/admin/sqlnet.ora
fi


if [ "$Action"=="ADD" ] ; then
	PORTNUMBER=$(echo $3 | grep -v NoRestart)
	Server=$(echo $4 | grep -v NoRestart)
fi

# if [ -f $OFA_TNS_ADMIN_NEW/sqlnet.ora ] ; then 
# 	move_old.sh $OFA_TNS_ADMIN_NEW/sqlnet.ora $OFA_TNS_ADMIN_NEW/sqlnet.ora.${StartTime}
# fi

# if [ -f $OFA_TNS_ADMIN_NEW/ldap.ora ] ; then
#         mv $OFA_TNS_ADMIN_NEW/ldap.ora $OFA_TNS_ADMIN_NEW/ldap.ora.${StartTime}
# fi

# if [ -f $OFA_TNS_ADMIN_NEW/listener.ora ] ; then
# 	move_old.sh $OFA_TNS_ADMIN_NEW/listener.ora $OFA_TNS_ADMIN_NEW/listener.ora.${StartTime}
# fi

# if [ -f $OFA_TNS_ADMIN_NEW/tnsnames.ora ] ; then
# 	move_old.sh $OFA_TNS_ADMIN_NEW/tnsnames.ora $OFA_TNS_ADMIN_NEW/tnsnames.ora.${StartTime}
# fi


if [ "$Action" == "NEW" ] ; then
	> $OFA_TNS_ADMIN_NEW/tnsnames.ora
	> $OFA_TNS_ADMIN_NEW/listener.ora
	LogCons "New tnsnames and listener will be created"
elif [ "$Action" == "ADD" ] ; then
	LogCons "Adding to the tnsnames and listener"
	if [ -z "$Para2OraSid" ] ; then
		LogError "Parameter 2, missing. Have to be set if P1 is "ADD""
		usage
		exit 1
	fi
elif [ "$Action" == "TNS" ] ; then
	LogCons "Adding the database in the tnsnames"
	if [ -z "$Para2OraSid" ] ; then
		LogError "Parameter 2, missing. Have to be set if P1 is "TNS""
		exit 1
	fi
else 
	LogError "Wrong parameter .........."
	LogError "Usage: RebSQLNet.sh [TNS, ADD or NEW] <SID>"
	usage
	exit 1
fi
	
if [ ! -z "$Para2OraSid" ] ; then
	OraDbList=$Para2OraSid
fi 

ProdHostName=$(hostname | grep prd)

if [ ! -f $OFA_TNS_ADMIN/sqlnet.ora ] ; then
	if [ -z "$ProdHostName" ] ; then
		cp $OFA_SCR/creation/TNS_TEMPLATE/sqlnet.ora $OFA_TNS_ADMIN
	else
		cp $OFA_SCR/creation/TNS_TEMPLATE/sqlnet.ora.PRD $OFA_TNS_ADMIN/sqlnet.ora
	fi
fi 

OraDbList=$(echo $OraDbList | tr "\n" " ")

LogCons "Config for database(s) : $OraDbList"


export TNS_ADMIN=/tmp
echo "NAMES.DIRECTORY_PATH= (LDAP)" > $TNS_ADMIN/sqlnet.ora
cp $OFA_SCR/creation/TNS_TEMPLATE/ldap.ora $TNS_ADMIN

for i in $OraDbList
do
	export TNS_ADMIN=/tmp
	OracleDatabaseName=$i

	if [ "$Action" != "TNS" ] ; then
		OraEnv $OracleDatabaseName
	fi

	OracleOsOwner=$(OraOsOwner)

	if [ $OracleOsOwner == $WhoAmI ] ; then
	LogCons "Config tnsnames and listener for database: $OracleDatabaseName"

	if [ -z "$Server" ] ; then
		Server=$(tnsping ${OracleDatabaseName} | grep HOST | awk -F 'HOST' '{print $2}' | \
		awk -F ')' '{print $1}' | sed s/=//g || echo "ERROR")
	fi

	if [ -z "$PORTNUMBER" ] ; then
		PORTNUMBER=$(tnsping ${OracleDatabaseName} | grep HOST | awk -F 'PORT' '{print $2}' | \
		awk -F ')' '{print $1}' | sed s/=//g || echo "ERROR")
	fi


	LogCons "Host Name: $Server"
	LogCons "Port Number: $PORTNUMBER"


	export ListenerName=LISTENER_${OracleDatabaseName}
	export ListenerTemplate="~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/script/creation/TNS_TEMPLATE/listener.ora"
	export TnsnamesTemplete="~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/script/creation/TNS_TEMPLATE/tnsnames.ora"


	if [ -z "$PORTNUMBER" ] || [ -z $(echo $PORTNUMBER | grep -v ERROR) ]; then
		LogCons "Error by getting Port number via tnsping."
       		LogCons "Please, enter the port number for the database: ${OracleDatabaseName}"
       		read PORTNUMBER
		export PORTNUMBER
	fi

	if [ -z "$Server" ] || [ -z $(echo $PORTNUMBER | grep -v ERROR) ]; then 
		LogCons "Error by getting Host name via tnsping."
       		LogCons "Please, enter the Host name for the database: ${OracleDatabaseName}"
       		read Server
       		export Server
	fi


	if [ "$Action" != "TNS" ] ; then 
		ExistNameList=$([[ -f  $OFA_TNS_ADMIN_NEW/listener.ora ]] && grep -w "LISTENER_$OracleDatabaseName" $OFA_TNS_ADMIN_NEW/listener.ora) > /dev/null 2>&1
		
		if [ ! -z "$ExistNameList" ] ; then
			echo ""
			LogWarning "Listener configuration for Listener: LISTENER_$OracleDatabaseName"
			LogWarning "already exist in the $OFA_TNS_ADMIN_NEW/listener.ora file"
			echo ""
			# exit 1
		fi 

		LogIt "Update listener.ora, Using "${ListenerTemplate}" as template"
		echo "# ------------------------------------------------------------------------------" >> $OFA_TNS_ADMIN_NEW/listener.ora
		echo "# Updated: ${StartTime} ($ScriptName)" >> $OFA_TNS_ADMIN_NEW/listener.ora
		cat ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/script/creation/TNS_TEMPLATE/listener.ora \
		| sed "s/<SID>/$OracleDatabaseName/g" | sed "s/<PORT>/$PORTNUMBER/g" | sed "s/<SERVER>/$Server/g"  >> $OFA_TNS_ADMIN_NEW/listener.ora
	fi

	ExistNameTns=$([[ -f  $OFA_TNS_ADMIN_NEW/tnsnames.ora ]] && grep -w "$OracleDatabaseName" $OFA_TNS_ADMIN_NEW/tnsnames.ora) > /dev/null 2>&1
        if [ ! -z "$ExistNameTns" ] ; then
		echo ""
                LogWarning "Tns configuration for database: $OracleDatabaseName"
                LogWarning "already exist in the $OFA_TNS_ADMIN_NEW/tnsnames.ora file"
		echo ""
                # exit 1
        fi


	echo "# ------------------------------------------------------------------------------" >> $OFA_TNS_ADMIN_NEW/tnsnames.ora
	echo "# Updated: ${StartTime} ($ScriptName)" >> $OFA_TNS_ADMIN_NEW/tnsnames.ora
	LogInfo "Updateing tnsnames.ora, Using "${TnsnamesTemplete}" as template"
	cat ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/script/creation/TNS_TEMPLATE/tnsnames.ora \
	| sed "s/<SID>/$OracleDatabaseName/g" | sed "s/<PORT>/$PORTNUMBER/g" | sed "s/<SERVER>/$Server/g" >> $OFA_TNS_ADMIN_NEW/tnsnames.ora

	if [[ "$Action" != "TNS" ]] && [[ -z $NoRestart ]]
	then
		lsnrctl stop $ListenerName > /dev/null 2>&1
		ProcNumber=$(ps -ef | grep -v grep | grep $ListenerName | awk '{print $2}')
		kill -9 $ProcNumber > /dev/null 2>&1

		lsnrctl start $ListenerName 
		if [ $? -ne 0 ] ; then
			LogError "Can't start the listener: $ListenerName"
			# exit 1
		fi
	fi 

	if [[ "$Action" != "TNS" ]] && [[ -z $NoRestart ]]
	then
		unset TNS_ADMIN
		tnsping ${OracleDatabaseName}
	elif [[ -z $NoRestart ]]
	then 
		unset TNS_ADMIN
		tnsping ${OracleDatabaseName}
	fi 

	if [ $? -ne 0 ] ; then
        	LogError "Can't tnsping the listener: $ListenerName"
		# exit 1
	fi
	else
		echo "Database have other OS owner........"
	fi
	unset PORTNUMBER
done

