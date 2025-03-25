#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22 > /dev/null 2>&1

OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"
OFA_MAIL_RCP_BAD="no mail"
MasterFile=$ORACLE_HOME/MasterCheckSum.txt
LocalFile=$ORACLE_HOME/LocalCheckSum.txt
ExcludeLog=$LOGFILE.exclude
# Exclude names "|" between each file/dir name.
# If a special char a "\" before the char
# e.g. ExcludeFiles="\.\/inventory|\.\/demo"
ExcludeFiles="NotFilesExcluded"
#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: SysCheck.sh [FUNC] 
##
## System check script.
##
## Paramaters:
##          ALL - Runs all check functions
##          LINK - Checks \$ORACLE_HOME links.
##          VER - Checks \$ORACLE_HOME version.
##	    PROC - Check that the PMON process are running from the ORACLE_HOME
##
##
#
_EOF
LogError "Wrong parameter....."
exit 1
#          ORA - Checks \$ORACLE_HOME oracle binary
# How to build MasterCheckSum.txt file after created a new software Image.
#
# cd [to the new image dir.]
# find . -type f -exec md5sum {} \; | sort -k 2 > MasterCheckSum.txt  
}
#----------------------------------------------------------------------------------------
CheckOraHome ()
#----------------------------------------------------------------------------------------
{
LogCons "Running: checks oracle binary ORACLE_HOME: $ORACLE_HOME"
LogCons "Excluding Dir./Files: $ExcludeFiles"
if [[ ! -f $MasterFile ]]
then
	LogError "Masten check sum file missing. (File name:$MasterFile)"
	exit 1
fi

LogCons "Using master check sum file:$MasterFile" 

MasterNumberLines=$(wc -l $MasterFile | awk '{print $1}')
LogCons "Building Local check sum file: $LocalFile"
cd $ORACLE_HOME
find . -type f -exec md5sum {} \; | sort -k 2 > $LocalFile 

LoopCount=1

while read MasterLine; do 
# set -xv
	MasterCheckSum=$(echo $MasterLine | awk '{print $1}')
	MasterFileName=$(echo $MasterLine | awk '{print $2}')

# echo "MasterCheckSum $MasterCheckSum"
# echo "MasterFileName $MasterFileName"
# echo "MasterLine $MasterLine"

	LocalLine=$(awk -v name="$MasterFileName" '$2 == name' $LocalFile) 
# echo "LocalLine -$LocalLine-"
	# LocalLine=$(grep -w "$MasterFileName" $LocalFile) 
# echo "LocalLine *$LocalLine*"




        LocalCheckSum=$(echo $LocalLine | awk '{print $1}')
        LocalFileName=$(echo $LocalLine | awk '{print $2}')

# echo "LocalCheckSum $MasterCheckSum"
# echo "LocalFileName $MasterFileName"

# read

unset ExcludeOrNotExclude
# echo "ExcludeFiles: $ExcludeFiles"
# echo "MasterFileName: $MasterFileName"
ExcludeOrNotExclude=$(echo $MasterFileName | egrep -v "$ExcludeFiles")

# echo "ExcludeOrNotExclude: $ExcludeOrNotExclude"

if [[ ! -z $ExcludeOrNotExclude ]]
then
	if [[ -z $LocalLine ]]
	then
		echo ""
		LogCons "File: $MasterFileName missing....."
		ErrorFileMissing=1
	else
	        if [[ $MasterCheckSum != $LocalCheckSum ]]
        	then
               		 echo ""
                	LogCons "Error in check sum file."
                	LogCons "Master: $MasterLine"
                	LogCons "Local:  $LocalLine"

                	ErrorCheckSum=1
        	fi

	fi
else
	LogCons "exclude:$MasterFileName" >> $ExcludeLog
fi

	echo -en "\r Check file number: $LoopCount of $MasterNumberLines" 
	let LoopCount=$LoopCount+1
# if [[ $LoopCount -eq 10 ]] 
# then
# exit
# fi 

done < $MasterFile

echo ""

if [[ $ErrorFileMissing -ne 0 ]]
then 
	LogError "File missing ......"
	
fi

if [[ $ErrorCheckSum -ne 0 ]]
then
        LogError "Error in check sum ......."
fi

}
#----------------------------------------------------------------------------------------
CheckOracleVersion ()
#----------------------------------------------------------------------------------------
{
LogCons "###################### Checks Oracle home: $ORACLE_HOME versions.###################### "
LogCons "***************** Version info from binary *****************"
SqlplusVer=$(DoSqlV | grep "SQL\*Plus" | awk '{print $3}')
LogCons "Sql*Plus version:		$SqlplusVer"

OraBinary=$(strings $ORACLE_HOME/bin/oracle | grep 'NLSRTL Version' | awk '{print $3}')
LogCons "Oracle binary version:	$OraBinary"

OraVerFromOpatch=$($ORACLE_HOME/OPatch/opatch lsinventory | grep "Oracle Database" | awk '{print $4}')
LogCons "Oracle version from opatch: $OraVerFromOpatch"

if [[ $(OraDbStatus) == "OPEN" ]]
then
LogCons "************** Version info from the database **************"
DBDatabase=$(DoSqlQ "select * from v\$version;" | grep "Oracle Database" | awk '{print $7}')
LogCons "Enterprise Edition Release:	$DBDatabase"

DBPlSql=$(DoSqlQ "select * from v\$version;" | grep "CORE" | awk '{print $2}')
LogCons "CORE:			$DBPlSql"

DBTns=$(DoSqlQ "select * from v\$version;" | grep "TNS" | awk '{print $5}')
LogCons "TNS Version:		$DBTns"

DBNlsrtl=$(DoSqlQ "select * from v\$version;" | grep "NLSRTL" | awk '{print $3}')
LogCons "NLSRTL Version:		$DBNlsrtl"
else
	LogError "Database: $ORACLE_SID are not in OPEN state."
fi
# Check if versions are the same


for var in $SqlplusVer $OraBinary $OraVerFromOpatch $DBDatabase $DBPlSql $DBTns $DBNlsrtl; do
	for var1 in $OraBinary $OraVerFromOpatch $DBDatabase $DBPlSql $DBTns $DBNlsrtl $SqlplusVer; do
	if [[ $var != $var1 ]]
	then
		ErrorMismash=1	
	fi
	done
done

if [[ "$ErrorMismash" -ne 0 ]]
then 
		LogError "Mismash in version numbers !!!!!!!!!!!!!!!!!!!!!!"
fi
}
#----------------------------------------------------------------------------------------
CheckOracleLinks ()
#----------------------------------------------------------------------------------------
{
LogCons "###################### Checks Oracle home: $ORACLE_HOME links.###################### " 
OracleHomeLinks=$(find $ORACLE_HOME -type l -exec ls -l {} \; | awk '{print $11}' | grep $ORACLE_BASE | grep -v $OFA_TNS_ADMIN)
for i in $OracleHomeLinks
do
	LogCons "Link that contain \$ORACLE_BASE path: $i"
	LinkHome=$ORACLE_BASE/$(echo $i | awk -F "/" '{print $3}')
	LogCons "LinkHome: $LinkHome"
	
	if [[ "$ORACLE_HOME" != "$LinkHome" ]]
	then
		LogError "Oracle home: $ORACLE_HOME, are different from the link home: $LinkHome"
	fi
done
}
#----------------------------------------------------------------------------------------
CheckOracleProcess ()
#----------------------------------------------------------------------------------------
{
LogCons "###################### Check oracle process HOME ###################### "
PmonProcessNo=$(ps -ef | grep pmon_$ORACLE_SID | grep -v grep | awk '{print $2}')
PmonProcessName=$(ps -ef | grep pmon_$ORACLE_SID | grep -v grep | awk '{print $8}')
LogCons "Process Name: $PmonProcessName, Process No.: $PmonProcessNo"
PmonProcessHome=$(ls -l /proc/$PmonProcessNo/cwd | awk '{print $11}' )
LogCons "Pmon process home: $PmonProcessHome"
if [[ ! -z $(echo $PmonProcessHome | grep -v $ORACLE_HOME) ]]
then
	LogError "Pmon process: $PmonProcessHome and ORACLE_HOME: $ORACLE_HOME are differant !!!!!"
fi
}
#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------
Func=$1

    LogIt "Check variable completeness"
    CheckVar                       \
        Func                       \
     && LogIt "Variables complete" \
     || Usage

if [[ "$Func" == "ORA" ]]
then
	CheckOraHome
	LogCons "Excluding Dir./Files: $ExcludeFiles"
	LogCons "Exclude log file:$ExcludeLog"
elif [[ "$Func" == "VER" ]]
then
	CheckOracleVersion
elif [[ "$Func" == "PROC" ]]
then
        CheckOracleProcess
elif [[ "$Func" == "LINK" ]]
then
        CheckOracleLinks
elif [[ "$Func" == "ALL" ]]
then
        CheckOracleLinks
	CheckOracleVersion
	CheckOracleProcess
else		
	Usage

fi




