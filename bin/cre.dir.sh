#!/bin/ksh
  #
  # load lib
  #
     . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

OFA_MAIL_RCP_BAD=""

  #
  ## Create needed directories for a database enviroment e.g. /DB/$ORACLE_SID.
  ## Usage Usage: cre.dir.sh [v01] or [v02] or [cdb] 
  ## Version parameter v01 (All DB's), v02 (Not Used) 
  #


if [ -z "$1" ] ; then
	LogError "Version parameter missing."
	LogError "Usage: cre.dir.sh [v01] |  [19c] | [cdb]"	
		exit 1
fi	

INST_VERSION=$1

if [ "$INST_VERSION" == "v01" ] || [ "$INST_VERSION" == "19c" ]; then
	LogCons "Create/check directories for v01, 19c"
	FSList="$OFA_DB_DATA \
		$OFA_DB_VAR \
		$OFA_DB_ARCH \
		$OFA_DB_BKP"
	DirList="$OFA_DB_BKP/$ORACLE_SID/datapump \
        	$OFA_DB_BKP/$ORACLE_SID/rman \
        	$OFA_DB_ARCH/$ORACLE_SID \
        	$OFA_DB_DATA/$ORACLE_SID \
        	$OFA_DB_VAR/$ORACLE_SID \
		$OFA_DB_VAR/common \
        	$OFA_DB_VAR/$ORACLE_SID/agent \
        	$OFA_DB_VAR/$ORACLE_SID/log/adump \
        	$OFA_DB_VAR/$ORACLE_SID/log/cdump\
        	$OFA_DB_VAR/$ORACLE_SID/log/inst \
        	$OFA_TNS_ADMIN \
		$ORACLE_HOME/rdbms/audit
        	$OFA_SCR/creation/$ORACLE_SID \
        	$OFA_SCR/mep/$ORACLE_SID \
		$OFA_SCR/expl/$ORACLE_SID \
        	$OFA_SCR/refresh/$ORACLE_SID \
        	$OFA_ORACLE_BASE/cfgtoollogs/"
elif [ "$INST_VERSION" == "cdb" ] ; then
	LogCons "Create/check directories for CDB"
        TYPE_SID="_PDB"
        PDB_SID=${ORACLE_SID}${TYPE_SID}
        FSList="$OFA_DB_DATA \
                $OFA_DB_VAR \
                $OFA_DB_ARCH \
                $OFA_DB_BKP"
        DirList="$OFA_DB_BKP/$ORACLE_SID/datapump \
                $OFA_DB_BKP/$ORACLE_SID/rman \
                $OFA_DB_ARCH/$ORACLE_SID \
                $OFA_DB_DATA/$ORACLE_SID \
                $OFA_DB_DATA/$ORACLE_SID/pdbseed \
		$OFA_DB_BKP/$PDB_SID/datapump \
                $OFA_DB_BKP/$PDB_SID/rman \
                $OFA_DB_DATA/$PDB_SID \
                $OFA_DB_VAR/$ORACLE_SID \
                $OFA_DB_VAR/common \
                $OFA_DB_VAR/$ORACLE_SID/agent \
                $OFA_DB_VAR/$ORACLE_SID/log/adump \
                $OFA_DB_VAR/$ORACLE_SID/log/cdump\
                $OFA_DB_VAR/$ORACLE_SID/log/inst \
                $OFA_TNS_ADMIN \
                $ORACLE_HOME/rdbms/audit
                $OFA_SCR/creation/$ORACLE_SID \
        	$OFA_SCR/mep/$PDB_SID \
        	$OFA_SCR/mep/$ORACLE_SID \
        	$OFA_SCR/refresh/$PDB_SID \
        	$OFA_SCR/refresh/$ORACLE_SID \
                $OFA_ORACLE_BASE/cfgtoollogs/"
elif [ "$INST_VERSION" == "v02" ] ; then
	LogError "Not used.......... v02, use v01 or cdb"
else
                LogError "Wrong version number: ${INST_VERSION}"
                exit 1
fi
	

for i in $FSList
do
	if [ ! -x ${i} ] ; then
		LogError "Directory: ${i} don't exist"
		exit 1
	fi
	LogInfo "Directory: ${i} Ok! "
done

OLD_UMASK=`umask`
umask 0027
for i in $DirList
do
	if [ ! -d  ${i} ] ; then
           mkdir -p ${i}
	   if [ $? -ne 0 ] ; then
		LogError "Can't create directory: ${i}"
		exit 1
	   fi
	   LogCons "Created directory: ${i}"
	else
           LogCons "Directory: ${i} exist!"
        fi

done 
umask ${OLD_UMASK}
