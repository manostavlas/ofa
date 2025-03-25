#!/bin/ksh
  #
  # load lib
  #
      . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD="no mail"
OFA_MAIL_RCP_DFLT="no mail"

export LogFile=/dbvar/$ORACLE_SID/log/inst/DBCheck.log
cd /dbvar/$ORACLE_SID/log/inst/
DoSqlLogged $OFA_SQL/DBCheck.sql > $LogFile 2>&1

ErrorMessage=$(grep INVALID $LogFile)

if [ ! -z "$ErrorMessage" ] ; then
	LogError "INVALID package(s) or object(s), check log file: ${LogFile}" 
fi 
