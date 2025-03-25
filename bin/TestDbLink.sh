#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22 > /dev/null 2>&1

OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"
OFA_MAIL_RCP_BAD="no mail"

#----------------------------------------------------------------------------------------
Usage ()
#----------------------------------------------------------------------------------------
{
cat << _EOF
#
##
## Usage: TestDbLink.sh [SID]
##
## Check DB Links TNS names.
##
#
_EOF
LogError "Wrong parameter....."
exit 1
}
#----------------------------------------------------------------------------------------

if [ ! -z $1 ]; then
	DbList=$1
else
	DbList=$(ListOraDbs | sort | tr "\n" " ")
fi

LogCons "Database List: *$DbList*"
for i in $DbList
do 
	OraEnv $i  > /dev/null 2>&1
	LogCons "-----------------------------------------------------------------------------"
	LogCons "Database: $ORACLE_SID status: $(OraDbStatus)"
	LogCons "-----------------------------------------------------------------------------"
	if [ "$(OraDbStatus)" == "OPEN" ] ; then
		LogCons "Connecting to Database: $ORACLE_SID"
		unset HostForLinks
		HostForLinks=$(DoSqlQ "select distinct HOST from dba_db_links;" | tr "\n" " ")
		if [ ! -z "$HostForLinks" ]; then
			LogCons "TNS names used:"
			LogCons "$HostForLinks"
			for i in $HostForLinks
			do
				UsedBy=$(DoSqlQ "select '('||DB_LINK||':'||owner||')' from dba_db_links where HOST='$i';" | tr "\n" " ")
				tnsping $i >/dev/null 2>&1
				if [ $? -ne 0 ] ; then
					LogError "Connection to TNS name: $i FAILED!"
					LogCons "Used by DB link(s): $UsedBy"
				else 
					LogCons "Connection to TNS name: $i OK!"
					LogCons "Used by DB link(s): $UsedBy"
					DbLinksPublic=$(DoSqlQ "select DB_LINK from dba_db_links where HOST='$i' and owner='PUBLIC';")
					for j in $DbLinksPublic
					do
						LogCons "Test DB Link: $j"
						TestResult=$(DoSqlQ "select count(*) from user_tables@$j;" | grep ORA-)
						if [ -z "$TestResult" ] ; then
							LogCons "Link ok!"
						else
							LogCons "Error: $TestResult"
						fi
					done
				fi 
				# LogCons "Used by DB link(s): $(DoSqlQ "select '('||DB_LINK||':'||owner||')' from dba_db_links where HOST='$i';" | tr "\n" " ")"
			done

		else
			LogCons "NO database links in the database"
		fi
	else
        	LogError "Can't connect to database $ORACLE_SID database is NOT in OPEN "mode""
        fi
done



VolSet -10000
