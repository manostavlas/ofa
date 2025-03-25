#!/bin/ksh
#
## Name: gen_roratab.sh
##
## In:  n.a
## Out: n.a.
## Ret: 0/1
##
## Synopsis: Generate a new $RORATAB.
##
## Usage: gen.roratab
##
## Description:
##
##  - Login on all servers defiend in $OFATAB
##  - Retrieve server and database informations.
##  - Copy the old $RORATAB to $RORATAB_YYYY_MM_DD_HHMMSS
##
##
##  -ONLY runs on the OFA master server as ofaadm !!!!!!!!!!!!!!
##
## Note:
##    Interactive only
##
#  ------------------------------------------------------------------------------
# set -xv

  #
  # load lib
  #
     . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

StartTime=`date +"%Y_%m_%d_%H%M%S`
OutputFile=/tmp/roratab
OldRoratabFile="${RORATAB}_${StartTime}"

RORATAB=/ofaadm/OFA/master/ofa/local/oracle/etc/oracle/roratab

LogCons "Using file OFATAB: $OFATAB"
LogCons "Using file RORATAB: $RORATAB"

if [ ! -w "$RORATAB" ]; then
	LogError "File: $RORATAB don't exist"
	exit 1
fi

if [ ! -w "$OFATAB" ]; then
        LogError "File: $OFATAB don't exist"
        exit 1
fi



LogCons "Generating a new roratab file. ($RORATAB)"

LogCons "Using ofatab file: $OFATAB"


cp $RORATAB $OldRoratabFile 

if [ $? -ne 0 ] ; then
	LogError "Can't save old roratab file."
	exit 1
else
	LogCons "Saved old roratab file. ($OldRoratabFile)."
fi


echo "# "> $OutputFile
echo "# roratab " >> $OutputFile
echo "# Record format: sid : version : startup_flag : user :  host : env : zone : created : creator : active : application : comments" >> $OutputFile
echo "# -----------------------------------------------------------------------------------------------------------------------------" >> $OutputFile
echo "# " >> $OutputFile

# set -xv
ServerList=$(cat $OFATAB | grep oracle | awk '{print $1}' | grep -v "#")

for i in ${ServerList}
do
	OsType=`ssh ${i} uname -a | awk '{print $1}'`
		
	if [ $? != 0 ] ; then
		LogError "Can't connect to server: ${i}"

	else 

		if [ "SunOS" == "$OsType" ] ; then
			ORATAB="/var/opt/oracle/oratab"
		else
			ORATAB="/etc/oratab"
		fi

		OratabLine=$(ssh ${i} cat $ORATAB | sed '/^$/d' | grep -v "#" | grep -v "+ASM" | grep -v "*")

	        if [ $? != 0 ] ; then
        	        LogError "Can't get info from $ORATAB to server: ${i}"
		fi 

		if [ -z "$OratabLine" ] ; then
			LogError "No Databases is the $ORATAB file. Server: ${i}"
		fi

		for LINE in $OratabLine
		do
  			OracleSid=`echo $LINE | awk -F: '{print $1}' -`
  			OracleHome=`echo $LINE | awk -F: '{print $2}' -`
  			StartPara=`echo $LINE | awk -F: '{print $3}' -`
  			HostName=`echo $i | awk -F@ '{print $2}' -`
  			UserName=`ssh ${i} ls -ld $OracleHome | awk '{print $3}'`

		        if [ $? != 0 ] ; then
                	        LogError "Can't get User info. Server ${i} Database: $OracleSid"
                	fi

		if [ $StartPara != "D" ] ; then
			if [ -z "$UserName" ] ; then
				UserName=n.a
			fi
	
			if [ -n "`echo $OracleSid | grep PRD`" ] ; then 
				EnvName=PROD
			elif [ -n "`echo $OracleSid | grep POC`" ] ; then
				EnvName=POC
       	        	elif [ -n "`echo $OracleSid | grep TST`" ] ; then
       	                	EnvName=TST
       	         	elif [ -n "`echo $OracleSid | grep UAT`" ] ; then
       	                	EnvName=UAT
       	         	elif [ -n "`echo $OracleSid | grep DEV`" ] ; then
       	                	EnvName=DEV
       	         	elif [ -n "`echo $OracleSid | grep EV1`" ] ; then
       	                	EnvName=EV1
       	         	elif [ -n "`echo $OracleSid | grep EV2`" ] ; then
       	                	EnvName=EV2
       	         	elif [ -n "`echo $OracleSid | grep EV3`" ] ; then
       	                	EnvName=EV3
       	         	elif [ -n "`echo $OracleSid | grep ev4`" ] ; then
       	                	EnvName=ev4
       	         	elif [ -n "`echo $OracleSid | grep TST`" ] ; then
       	                	EnvName=TST
			else
				EnvName=n.a
			fi
	
			ZoneName=none
			CreateDate=none
			CreatorName="[?]"
			ActiveName=?
			ApplName=none
			Commen="none"

  			printf "%-10s":\ "%-30s":\ "%-2s":\ "%-10s":\ "%-20s":\ "%-5s":\ "%-5s":\ "%-5s":\ "%-4s":\ "%-2s":\ "%-5s":\ "%-5s\n"  $OracleSid $OracleHome $StartPara $UserName $HostName $EnvName $ZoneName $CreateDate $CreatorName $ActiveName $ApplName $Commen >> $OutputFile 
		fi

		LogCons "Retrieved info from Server: ${i}, Database: $OracleSid"
		done



	fi

done

cp $OutputFile $RORATAB

if [ $? != 0 ] ; then
	LogError "Can't save new roratab file."
fi 
