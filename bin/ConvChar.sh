#!/bin/ksh

  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"


# set -x


StartDate=$(date +%Y%m%d%H%M%S)
SourceDir=$1
TargetDir=$SourceDir/OutPut_${StartDate}
FromChar="UTF-8"
ToChar="ISO8859-1"

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: ConvChar.sh [SOURCE_DIR]
##
## Convert file from "UTF-8" to "ISO8859-1" 
##
#

__EOF
}
  CheckVar SourceDir         \
  || usage




LogCons "Source dir.: ${SourceDir}"
LogCons "TargetDir dir.: ${TargetDir}"
LogCons "From Char: $FromChar"
LogCons "To Char: $ToChar"

if [[ ! -d  $SourceDir ]]
then
	LogError "Source Dir.: ${SourceDir} don't exist"
	exit 1 
fi

mkdir ${TargetDir}
        ErrorCode=$?
        if [[ $ErrorCode -ne 0 ]]
        then
                LogError "Error create dir.: ${TargetDir}"
                exit 1
        fi

FileList=$(ls -1 $SourceDir | sort )

for i in $FileList
do
FileToConv=${SourceDir}/${i}
	if [[ -f $FileToConv ]]
	then
		LogCons "Convert file $FileToConv to $TargetDir/$i"
		iconv -f ${FromChar} -t ${ToChar} $FileToConv > $TargetDir/$i
		ErrorCode=$?
        	if [[ $ErrorCode -ne 0 ]]
        	then
                	LogError "Error Convert file $FileToConv to $TargetDir/$i"
			# exit 1
        	fi
	else 
		LogCons "Not a ordinary $FileToConv "
	fi
done 

LogCons "Converted file are in dir.: ${TargetDir}"
