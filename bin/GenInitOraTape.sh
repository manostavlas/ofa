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

SetInit ()
#----------------------------------
{


if [ -f "$ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora" ] ; then
        InitFileBck=$ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora
        LogInfo "Init file $ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora used"
elif [ -f "/backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora" ] ; then
        InitFileBck=/backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora
        LogInfo "Init file /backup/${TargetDatabaseSid}/rman/init${SourceSid}.ora used"
else
        BailOut "No init file found."
fi


if [ ! -f "$InitFileBck" ] ; then
        LogError "Source init.ora file: $InitFileBck  missing"
        exit 1
else
        LogInfo "Source init.ora file: $InitFileBck"
fi

if [ -d "/DB/${TargetDatabaseSid}" ] ; then
        TargetDataFileDir=/DB/${TargetDatabaseSid}
        BaseTargetDataFileDir=DB
        SourceDataFileDir=DB
elif [ -d "/ODB/${TargetDatabaseSid}" ] ; then
        TargetDataFileDir=/ODB/${TargetDatabaseSid}
        BaseTargetDataFileDir=ODB
else
        LogError "Datafile directory don't exist: /DB/${TargetDatabaseSid} or /ODB/${TargetDatabaseSid}"
        exit 1
fi

if [ -d "/RD/${TargetDatabaseSid}" ] ; then
        TargetLogFileDir=/RD/${TargetDatabaseSid}
else
        TargetLogFileDir=$TargetDataFileDir
fi

LogInfo "Target Data file Directory: $TargetDataFileDir"
LogInfo "Target Redo log file Directory: $TargetLogFileDir"


# Set convert

cat $InitFileBck | grep -v "DB_FILE_NAME_CONVERT" | grep -v "LOG_FILE_NAME_CONVERT"  \
| sed "s/$SourceSid/$TargetDatabaseSid/g" \
| sed "s/$SourceDataFileDir/$BaseTargetDataFileDir/g" \
 > $InitFileBck.tmp

InitTemplateDB=/ofa/local/oracle/script/refresh/${TargetDatabaseSid}/init${TargetDatabaseSid}.ora
# LogInfo "Init Template file: $InitTemplateDB"

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
        LogInfo "Init template file exist. File: $InitTemplateDB"
        >/tmp/RemoveLine
        while read line
        do
#  echo "*$line*"
                ParameterName=$(echo $line | awk -F "=" '{print $1}' | awk -F "." '{print $2}')
                LogInfo "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
                LogInfo "Paramater Value: $line"
                LogCons "Change Parameter: $ParameterName Read from File: $InitTemplateDB"
                LogCons "Paramater Value: $line"
                echo $ParameterName >> /tmp/RemoveLine
        done < "$InitTemplateDB"

        grep -v -i -f /tmp/RemoveLine $InitFileBck.tmp > $InitFileBck.new
        cat ${InitTemplateDB} >> $InitFileBck.new
else
        cat $InitFileBck.tmp > $InitFileBck.new
fi

echo "*.db_file_name_convert='${OFA_DB_DATA}/${SourceSid}/','${OFA_DB_DATA}/${REF_SID}/','$OFA_DB_DATA/${SourceSid}_PDB/','$OFA_DB_DATA/$REF_SID}_PDB/'" >> $InitFileBck.new
echo "*.log_file_name_convert='${OFA_DB_DATA}/${SourceSid}/','${OFA_DB_DATA}/${REF_SID}/','$OFA_DB_ARCH/${SourceSid}/','$OFA_DB_ARCH/${REF_SID}/'" >> $InitFileBck.new
cat $InitFileBck.new | grep -v "${TargetDatabaseSid}.__" > $InitFileBck.new.01
cp $InitFileBck.new.01 $ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora

DoSqlQ "CREATE SPFILE='${ORACLE_HOME}/dbs/spfile${REF_SID}.ora' from PFILE='$ORACLE_HOME/dbs/init${TargetDatabaseSid}.ora';"

}
#----------------------------------
# Main
#----------------------------------

 [[ ! -n $1 ]] \
        && Usage "Database SID parameter missing" \
        || TargetDatabaseSid=$1

SetInit
