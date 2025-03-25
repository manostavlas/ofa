cd $1
OWNER=`whoami`
FILES=`find . -user $OWNER -name "$2" -type f -exec ls  {} \; 2>/dev/null`
for f in "$FILES"
do
	dos2unix $f $f
done 
