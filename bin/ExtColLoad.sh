#!/bin/ksh

# set -xv

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

# set -xv

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_GOOD="no mail"

TargetDB=$1
LoadFileName=$2

LoadFileNameFullPath=${OFA_DB_BKP}/${TargetDB}/sqlloader/${LoadFileName}
LoadFileBad=${OFA_DB_BKP}/${TargetDB}/sqlloader/${LoadFileName}.bad
LoadFileDsc=${OFA_DB_BKP}/${TargetDB}/sqlloader/${LoadFileName}.dsc
LoadFileLog=${OFA_DB_BKP}/${TargetDB}/sqlloader/${LoadFileName}.log
CtlFile=$OFA_LOG/tmp/ExtColLoad.CtlFile.${TargetDB}.${LoadFileName}.$$.$PPID.ctl
ParFile=$OFA_LOG/tmp/ExtColLoad.ParFile.${TargetDB}.${LoadFileName}.$$.$PPID.par
SqlLog=$OFA_LOG/tmp/ExtColLoad.SqlLog.$TargetDB.${LoadFileName}.$$.$PPID.log

TimeStampLong=$(date +"%y%m%d_%H%M%S")
TimeStamp=$(date +"%H%M%S")


#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ExtColLoad.sh [DB_SID] [FILE_NAME] 
##
##
## Paremeter:
##
## DB_SID:        Name of DB to load the file into
##                File will be loaded into table: COLDIFF.T_COL_DIFF_DB. 
##
## FILE_NAME:     File name to load.
##                Have to be in Directory ${OFA_DB_BKP}/[DB_SID]/sqlloader.
##          
## Function:
## 
## Script loading column data from file into the table COLDIFF.T_COL_DIFF_DB. 
## 
##
#
__EOF
exit 1
}
#---------------------------------------------------------
CleanUp ()
#---------------------------------------------------------
{
SourceDbName=$(head -1 ${LoadFileNameFullPath} | awk -F "," '{print $1}')

LogCons "Delete all column info for database: ${SourceDbName}"

sqlplus -s "/as sysdba" << __EOF > $SqlLog 2>&1
delete COLDIFF.T_COL_DIFF_DB where instance_name='$SourceDbName';
commit;
__EOF

LogCons "Log file:$SqlLog"

LogCons "Remove all old load files: ${OFA_DB_BKP}/${TargetDB}/sqlloader/*${SourceDbName}*.*.* "

ls -l ${OFA_DB_BKP}/${TargetDB}/sqlloader/*${SourceDbName}*.*.*

rm ${OFA_DB_BKP}/${TargetDB}/sqlloader/*${SourceDbName}*.*.* >/dev/null 2>&1

}
#---------------------------------------------------------
CreCtlFile ()
#---------------------------------------------------------
{
LogCons "Check input file: ${LoadFileNameFullPath}" 

if [[ ! -r $LoadFileNameFullPath ]]
then
	LogError "Input file missing..... ${LoadFileNameFullPath}"
	usage
	exit 1
fi

LogCons "Creating control file: $CtlFile"

cat << __EOF > $CtlFile
load data
infile '${LoadFileNameFullPath}'
badfile '${LoadFileBad}'
discardfile '${LoadFileDsc}'
APPEND
into table COLDIFF.T_COL_DIFF_DB
fields terminated by "," trailing nullcols
(
  INSTANCE_NAME,
  OWNER,
  TABLE_NAME,
  COLUMN_NAME,
  DATA_TYPE,
  CHAR_LENGTH,
  EXTRACT DATE "YYMMDD_HH24MISS"
)
__EOF

cat $CtlFile

LogCons "Creating parameter file: ${ParFile}"

cat << __EOF > ${ParFile}
control=${CtlFile}
log=${LoadFileLog}
ERRORS=0
direct=true
__EOF

cat ${ParFile}

}
#---------------------------------------------------------
LoadFile ()
#---------------------------------------------------------
{
sqlldr \'/ as sysdba\' parfile=${ParFile}

ErrorCode=$?
if [[ $ErrorCode -eq 0 ]]
then
	LogCons "Remove: ${LoadFileNameFullPath}"
 	rm ${LoadFileNameFullPath} >/dev/null
else
	LogError "Error load ${LoadFileNameFullPath} into DB: ${TargetDB}"
fi
}
#---------------------------------------------------------
# Main
#---------------------------------------------------------
    LogIt "Check variable completeness"
    CheckVar                       \
        TargetDB                   \
        LoadFileName               \
     && LogIt "Variables complete" \
     || usage

OraEnv $TargetDB || BailOut "Failed OraEnv \"$TargetDB\""

LogCons "Check input file: ${LoadFileNameFullPath}"

if [[ ! -r $LoadFileNameFullPath ]]
then
        LogError "Input file missing..... ${LoadFileNameFullPath}"
        usage
        exit 1
fi

CleanUp
CreCtlFile
LoadFile
