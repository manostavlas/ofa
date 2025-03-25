#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD="no mail"

YesNo $(basename $0) || exit 1 && export RunOneTime=YES

# set -vx
##
## Usage: "CreLinkHome.sh"
##
## Creation of links for each database home.
##      Parameters:
##      [ALL] Create links for all databases.
##      or
##      [SID] Create link for the database.
##
## 	$ORACLE_HOME -> /oracle/[SID]
##      The link are used in GRID control, database and listener configuration.
##
#

ParMeter1=$1

CheckVar ParMeter1 || BailOut "Missings paramater"

if [ "$ParMeter1" == "ALL" ] ; then
	DatabaseList=$(ListOraDbs)
else
	DatabaseList=$ParMeter1
fi



for i in $DatabaseList
do
	LinkName="$OFA_ORACLE_BASE/$i"
	DbHome=$(egrep "^$i:[^:][^:]*:" $ORATAB|cut -d":" -f2)

	if [ -z "$DbHome" ] ; then
		LogError "Database: $ParMeter1  don't exist."
		exit 1
	fi


	LogCons  " Running: ln -sf $DbHome $OFA_ORACLE_BASE/$i" 
	
        if [ -h "$LinkName" ] ; then
	       rm $LinkName 
	fi

	ln -sf $DbHome $LinkName 

	if [ "$?" -ne "0" ] ; then 
		LogCons "Error create link ln -sf $DbHome $OFA_ORACLE_BASE/$i"
	fi

	if [ -h "$LinkName" ] ; then
		LogCons "Link OK! $LinkName" 
	else
		LogError "$LinkName is NOT a link !!!!!!"
	fi

done
