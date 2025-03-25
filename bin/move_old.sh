#/bin/ksh
# set -xv
usage ()
{
cat << __EOF
#
##
## Copy file, if exist to FileName.YY_MM_DD_HHMISS
## and delete old version but leave the last 5 version"
##
## Usage: move_old.sh [FILE_NAME]
## 
#
__EOF
}
FileName=$1
TimeStamp=$(date +"%Y_%m_%d_%H%M%S")


if [ -z "$FileName" ] ; then
	echo "Error: parameter missing"
	usage
	exit 1
fi

if [[ -r $FileName ]]
then
 cp $FileName $FileName.$TimeStamp 
 echo "Copy $FileName to $FileName.$TimeStamp"
fi

FilesToDelete=$(ls -1rt $FileName.????_??_??_?????? 2>/dev/null | awk '{buf[NR-1]=$0;}END{ for ( i=0; i < (NR-30); i++){ print buf[i];} }')

echo "FilesToDelete: $FilesToDelete"

for i in $FilesToDelete
do 
	echo "Remove file: $i"
	rm $i
done
