#!/bin/ksh
  #
  # load lib
  #

  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: CheckPack.sh  [ORACLE_VERSION]
##
##
## Paremeter:
##
## ORACLE_VERSION:
##      Main Oracle version 19c 
##
## Check needed Unix pacakes for Oracle. 
##
#
__EOF
exit 1
}

OracleVersion=$1


#---------------------------------------------
# Main
#---------------------------------------------

    LogIt "Check variable completeness"
    CheckVar                       \
        OracleVersion              \
     && LogIt "Variables complete" \
     || usage

if [[ $OracleVersion == 19c ]]
then
List="
bc
binutils
compat-libcap1
compat-libstdc++-33
elfutils-libelf
fontconfig-devel
glibc
glibc-devel
ksh
libaio
libaio-devel
libXrender
libXrender-devel
libX11
libXau
libXi
libXtst
libgcc
libstdc++
libstdc++-devel
libxcb
make
net-tools
sysstat
"
else
	Usage
fi
TimeStamp=$(date +"%H%M%S")
TmpFile=$OFA_LOG/tmp/YumList.$$.$PPID.$TimeStamp.log
TmpFileMissing=$OFA_LOG/tmp/YumListMissing.$$.$PPID.$TimeStamp.log
>$TmpFileMissing

for i in $List
do
i=$(echo $i | grep -v "#")
>$TmpFile

if [[ ! -z $i ]]
then
	yum list $i > $TmpFile  > /dev/null 2>&1	
	Error=$?
	
	if [[ $Error -ne 0 ]]
	then
		LogError "Package: $i DON'T exist"
		echo $i >> $TmpFileMissing
	 	ExitCode=1	
	else
		LogCons "Package: $i OK!"
	fi
	cat $TmpFile 
fi
done

if [[ $ExitCode -ne 0 ]]
then
	echo ""

	# MissingPack=$(cat $TmpFileMissing | tr -d '\r')
	LogError "Package(s) missing !"
	exit 1
fi
