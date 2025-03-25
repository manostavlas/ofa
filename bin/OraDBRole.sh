#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1
OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"
OFA_MAIL_RCP_GOOD="no mail"

DbSid=$1
Action=$2

VolMin

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: OraDBRole.sh [SID] <ALL>
##
## Return the role of the batabase.
##
## Output: "STANDALONE" or "PRIMARY" or "PHYSICAL STANDBY"
##
## Parameters:
##	SID: Name of database to check
##	ALL: Show all info
##
#
__EOF
exit 1
}
#---------------------------------------------
# Main
#---------------------------------------------
  CheckVar DbSid         \
  || BailOut
LogCons "Get Role of database: $DbSid"

OraEnv $DbSid > /dev/null
Error=$?

if [[ "$Error" -ne "0" ]]
then
VolSet 1
	LogError "Error select database: $DbSid"
	exit 1
fi




if [[ $Action == ALL ]]
then
	OraDBRole
else
	OraDBRole | awk -F ":" '{print $1}'
fi 
