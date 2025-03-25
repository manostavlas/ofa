#!/bin/ksh
#
##
## Usage "RenameSqlnetLink.sh" 
##
## Change all Sql*net links (tnsnames.ora, sqlnet.ora, listener.ora, ldap.ora)
## to the files in /dbvar/common/admin/tns_admin
##
#
NewDir=/oracle/rdbms/admin/tns_admin/

FileToRename=$(find / -name tnsnames.ora  -exec ls -l {} \; -o -name sqlnet.ora  -exec ls -l {} \; -o -name listener.ora  -exec ls -l {} \; -o -name ldap.ora -exec ls -l {} \; 2>/dev/null | grep -v samples | grep -v TNS_TEMPLATE | grep lrwxrwxrwx | awk '{print $9'})

echo "---------------------------------- Before ----------------------------------"
find / -name tnsnames.ora  -exec ls -l {} \; -o -name sqlnet.ora  -exec ls -l {} \; -o -name listener.ora  -exec ls -l {} \; -o -name ldap.ora -exec ls -l {} \; 2>/dev/null | grep -v samples | grep -v TNS_TEMPLATE | grep lrwxrwxrwx 
echo "----------------------------------------------------------------------------"

for i in $FileToRename
do
	FileName=$(echo $i | awk -F "/" '{print $NF}')
	echo "Deleting: $(ls -l $i)"
	rm $i
	echo "Linking: ${NewDir}${FileName} -> $i"
	ln -s ${NewDir}${FileName} $i
done  

echo "---------------------------------- After ----------------------------------"

find / -name tnsnames.ora  -exec ls -l {} \; -o -name sqlnet.ora  -exec ls -l {} \; -o -name listener.ora  -exec ls -l {} \; -o -name ldap.ora -exec ls -l {} \; 2>/dev/null | grep -v samples | grep -v TNS_TEMPLATE | grep lrwxrwxrwx 

echo "------------------------------- Sql*Net files exist --------------------------------------------"

find / -name tnsnames.ora  -exec ls -l {} \; -o -name sqlnet.ora  -exec ls -l {} \; -o -name listener.ora  -exec ls -l {} \; -o -name ldap.ora -exec ls -l {} \; 2>/dev/null | grep -v samples | grep -v TNS_TEMPLATE | grep -v lrwxrwxrwx

echo "------------------------------------------------------------------------------------------------"
