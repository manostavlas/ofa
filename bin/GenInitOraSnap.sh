#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -vx
##
## Usage: "GenInitOra.sh [SID]
##
## Generate a new init.ora using the $ORACLE_HOME/dbs/init[SID].ora as source by default. 
## If $ORACLE_HOME/dbs/init[SID].ora don't exist, the init file from the backup will be used /backup/[SID]/rman/init[SID].ora.
##
## If the template file exist (../refresh/[SID]/init[SID].ora), 
## it will overwrite/add the parameter from the template file to the init file.
## Parameter:
## *.<PARAMETER_NAME>=<VAULE> (Remember the "*." in front of the line.)
## 

#----------------------------------
GetControlInfo ()
#----------------------------------
{
ControlFileName=$(ls -1rt /backup/$TargetDatabaseSid/rman/controlfile*.trc | tail -1 2>/dev/null)

if [ ! -r "$ControlFileName" ] ; then
	LogError "Control file don't exits: /backup/$TargetDatabaseSid/rman/controlfile*.trc)"
	exit 1
fi 

LogCons "Control file: $ControlFileName"

SourceSid=$(cat $ControlFileName | grep "CREATE CONTROLFILE" | awk  -F '"' '{print $2}' | head -1)

if [ -z "$SourceSid" ] ; then
        LogError "Can't get Source SID from control file: $ControlFileName"
        exit 1
fi

LogCons "Source SID: ${SourceSid}"


while read line
do
# echo "line: $line"
	if [ "$DataFileSec" == "Y" ] && [ -z "$DataFileDir" ] ; then
		SourceDataFileDir=$(echo $line | grep -v "\-\-" | grep ${SourceSid} | awk -F '/' '{print $2}')

		if [ ! -z "$SourceDataFileDir" ] ; then
			DataFileDir="/${SourceDataFileDir}/${SourceSid}"
			LogCons "Data file directory: $DataFileDir"
			LogCons "Data file directory: $DataFileDir"
			DataFileSec=N
		fi
	fi

        if [ "$LogFileSec" == "Y" ] && [ -z "$LogFileDir" ] ; then
                SourceLogFileDir=$(echo $line | grep -v "\-\-" | grep ${SourceSid} | awk -F '/' '{print $2}')

                if [ ! -z "$SourceLogFileDir" ] ; then
			LogFileDir="/${SourceLogFileDir}/${SourceSid}"
                	LogCons "Redo Log file directory: $LogFileDir"
			LogCons "Redo Log file directory: $LogFileDir"
                        LogFileSec=N
		fi
        fi


        if [ "$line" == "LOGFILE" ] ; then
                LogFileSec=Y
        fi

	if [ "$line" == "DATAFILE" ] ; then
		DataFileSec=Y
	fi


done < "$ControlFileName"
}
#----------------------------------
SetInit ()
#----------------------------------
{
if [ -f "$ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora" ] ; then
	InitFileBck=$ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora
        LogCons "Init file $ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora used"
elif [ -f "/backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora" ] ; then  
	InitFileBck=/backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora
        LogCons "Init file /backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora used"
else 
	BailOut "No init file found."
fi


if [ ! -f "$InitFileBck" ] ; then
	LogError "Source init.ora file: $InitFileBck  missing"
	exit 1
else 
	LogCons "Source init.ora file: $InitFileBck"
fi

# if [ -d "/DB/${TargetDatabaseSid}" ] ; then
# 	TargetDataFileDir=/DB/${TargetDatabaseSid}
# 	BaseTargetDataFileDir=DB
# elif [ -d "/ODB/${TargetDatabaseSid}" ] ; then
# 	TargetDataFileDir=/ODB/${TargetDatabaseSid}
# 	BaseTargetDataFileDir=ODB
# else
# 	LogError "Datafile directory don't exist: /DB/${TargetDatabaseSid} or /ODB/${TargetDatabaseSid}"
# 	exit 1
# fi

# if [ -d "/RD/${TargetDatabaseSid}" ] ; then
# 	TargetLogFileDir=/RD/${TargetDatabaseSid}
# else 
# 	TargetLogFileDir=$TargetDataFileDir
# fi

# LogCons "Target Data file Directory: $TargetDataFileDir"
# LogCons "Target Redo log file Directory: $TargetLogFileDir"

# Set convert

# cat $InitFileBck | grep -v "DB_FILE_NAME_CONVERT" | grep -v "LOG_FILE_NAME_CONVERT"  \
# | sed "s/$SourceSid/$TargetDatabaseSid/g" \
# | sed "s/$SourceDataFileDir/$BaseTargetDataFileDir/g" \
#  > $InitFileBck.tmp

cat $InitFileBck > $InitFileBck.tmp

InitTemplateDB=/ofa/local/oracle/script/refresh/${TargetDatabaseSid}/init${TargetDatabaseSid}.ora
# LogCons "Init Template file: $InitTemplateDB"

if [[ ! -r ${InitTemplateDB} ]]
then
        LogError "init refresh file missing: ${InitTemplateDB}"
        exit 1
fi

# remove blanck lines.
# sed -i '/^$/d' ${InitTemplateDB}
grep -v '^$'  ${InitTemplateDB} > ${InitTemplateDB}.temp
mv ${InitTemplateDB}.temp ${InitTemplateDB}



if [ -f $InitTemplateDB ] ; then
	LogCons "Init template file exist. File: $InitTemplateDB"
	>/tmp/RemoveLine
	while read line
	do
#  echo "*$line*"
		ParameterName=$(echo $line | awk -F "=" '{print $1}' | awk -F "." '{print $2}')
		LogCons "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
		LogCons "Paramater Value: $line"
		LogCons "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
		LogCons "Paramater Value: $line"
		echo $ParameterName >> /tmp/RemoveLine
	done < "$InitTemplateDB"

	grep -v -i -f /tmp/RemoveLine $InitFileBck.tmp > $InitFileBck.new
	cat ${InitTemplateDB} >> $InitFileBck.new
else
	cat $InitFileBck.tmp > $InitFileBck.new
fi

# echo "*.DB_FILE_NAME_CONVERT='${DataFileDir}','${TargetDataFileDir}'" >> $InitFileBck.new
# echo "*.LOG_FILE_NAME_CONVERT='${LogFileDir}','${TargetLogFileDir}'" >> $InitFileBck.new
cat $InitFileBck.new | grep -v "${TargetDatabaseSid}.__" > $InitFileBck.new.01
cp $InitFileBck.new.01 $ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora
}
#----------------------------------
# Main
#----------------------------------

 [[ ! -n $1 ]] \
        && Usage "Database SID parameter missing" \
        || TargetDatabaseSid=$1

# GetControlInfo
SetInit
