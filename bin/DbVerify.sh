#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

DbSid=$1
NumChannels=$2
VerifyScript=$OFA_LOG/tmp/DbVerify.$DbSid.$$.$PPID.ksh
VerifyScriptLog=$OFA_LOG/tmp/DbVerify.$DbSid.$$.$PPID.log
VerifyScriptLogTmp=$OFA_LOG/tmp/DbVerify.Tmp.$DbSid.$$.$PPID.log
SqlLogFree=$OFA_LOG/tmp/SqlLogFree.$DbSid.$$.$PPID.log
SqlLogCorr=$OFA_LOG/tmp/SqlLogCorr.$DbSid.$$.$PPID.log
RmanValLog=$OFA_LOG/tmp/RmanValLog.$DbSid.$$.$PPID.log
RmanValScript=$OFA_LOG/tmp/RmanValScript.$DbSid.$$.$PPID.log

#---------------------------------------------
usage ()
#---------------------------------------------
{
cat << __EOF
#
##
## Usage: DbVerify.sh  [SID] <NUMBER_OF_CHANNELS>
##
##
## Paremeter:
##
## SID: Name of the database
##
## NUMBER_OF_CHANNELS: number of parallel process running verify.
##                     Default: 4 
##
## Check database for corrupted blocks
##
#
__EOF
exit 1
}
#---------------------------------------------

    LogIt "Check variable completeness"
    CheckVar                       \
        DbSid                      \
     && LogIt "Variables complete" \
     || usage

        OraEnv $DbSid
        ExitCode=$?
        if [[ "$ExitCode" -ne 0 ]]
        then
                LogError "Database: $DbSid don't exist...."
                exit 1
        fi
#------------------------------------------------------
RunVerify ()
#------------------------------------------------------ 
{
LogCons "Create verify script: $VerifyScript"
LogCons "Log file: $VerifyScript"
sqlplus -s "/as sysdba" << __EOF >> $VerifyScript 2>&1
set echo off 
set feedback off 
set verify off 
set pages 0 
set termout off 
set timing off

	select 'dbv file=' || name || ' blocksize=' || block_size || ' feedback=' || round(blocks*.10,0) -- 10 dots per file   
        from v\$datafile;
__EOF


ErrorMsg=$(grep ORA- $VerifyScript)
if [[ ! -z "$ErrorMsg" ]]
then
        LogError "Error: Creating verify script Log: $VerifyScript"
	exit1
fi


grep -e FILE -e "Total Pages Marked Corrupt" -e FILE $VerifyScriptLog 


LogCons "Running DB verify step(s): $VerifyScript"
LogCons "Log file: $VerifyScriptLog"

>$VerifyScriptLog

OLDIFS="$IFS"
IFS=$'\n' 
for line in $(cat $VerifyScript)
do
  printf '%s\n' "$line"
  eval $line LOGFILE=$VerifyScriptLogTmp
	if [[ $? -ne 0 ]]
	then
		LogError "Error running $line Log file: $VerifyScriptLogTmp"
	fi

  cat $VerifyScriptLogTmp >> $VerifyScriptLog
  NumOfCorrBlock=$(grep "Total Pages Marked Corrupt" $VerifyScriptLogTmp | sed 's/ //g' | awk -F ":" '{print $2}')
  DataFile=$(echo $line | awk -F "=" '{print $2}' | awk '{print $1}')
  LogCons "Number of corruption: ${NumOfCorrBlock} in data file: ${DataFile}"
  if [[ $NumOfCorrBlock  -ne 0 ]]
  then
	echo "ERROR: Data file: $DataFile Number of corrupted pages: $NumOfCorrBlock"
  fi 
  echo ""
done
IFS="$OLDIFS"
}
#------------------------------------------------------
RmanValidate ()
#------------------------------------------------------
{
echo ""
LogCons "Running Database validate check logical"
if [[ -z $NumChannels ]]
then
	NumChannels=4
	LogCons "Number of channels: 4 (default)"
else
	LogCons "Number of channels: $NumChannels"
fi

LogCons "Script file: $RmanValScript"
LogCons "Log file: $RmanValLog"

echo "run {" >> $RmanValScript
  #
  # Allocate channels
  #
   i=$NumChannels
   while [[ $i -gt 0 ]];do
       echo "    allocate channel c$i type disk;" >> $RmanValScript
       let i-=1
   done | sort
echo "backup validate check logical database;" >> $RmanValScript
echo "}" >> $RmanValScript

rman target / cmdfile=$RmanValScript 2>&1 > $RmanValLog

# rman << ___EOF > $RmanValLog 2>&1
# connect target /
# run {
# allocate channel d1 type disk;
# allocate channel d2 type disk;
# allocate channel d3 type disk;
# allocate channel d4 type disk;
# backup validate check logical database;
# }
# ___EOF
}
#------------------------------------------------------
# Main
#------------------------------------------------------

# Check for corrupted blocks in objects

RmanValidate

echo ""
LogCons "List all corrupted blocks in objects..."
LogCons "Log file: $SqlLogCorr"
echo ""
sqlplus -s "/as sysdba" << __EOF 
set timing off
prompt flush cache/pool
alter system flush shared_pool; 
alter system flush buffer_cache;
__EOF

sqlplus -s "/as sysdba" << __EOF > $SqlLogCorr 2>&1

set heading on;
set timing off
set linesize 280

col SEGMENT_NAME form a40;
col PARTITION_NAME form a40;
col SEGMENT_TYPE form a18;
col DESCRIPTION form a25;

SELECT e.owner, e.segment_type, e.segment_name, e.partition_name, c.file#
     , greatest(e.block_id, c.block#) corr_start_block#
     , least(e.block_id+e.blocks-1, c.block#+c.blocks-1) corr_end_block#
     , least(e.block_id+e.blocks-1, c.block#+c.blocks-1)
       - greatest(e.block_id, c.block#) + 1 blocks_corrupted
     , corruption_type description
  FROM dba_extents e, v\$database_block_corruption c
 WHERE e.file_id = c.file#
   AND e.block_id <= c.block# + c.blocks - 1
   AND e.block_id + e.blocks - 1 >= c.block#
UNION
SELECT s.owner, s.segment_type, s.segment_name, s.partition_name, c.file#
     , header_block corr_start_block#
     , header_block corr_end_block#
     , 1 blocks_corrupted
     , corruption_type||' Segment Header' description
  FROM dba_segments s, v\$database_block_corruption c
 WHERE s.header_file = c.file#
   AND s.header_block between c.block# and c.block# + c.blocks - 1;
__EOF

CorrBlocks=$(grep "no rows selected" $SqlLogCorr)


if [[ -z $CorrBlocks ]]
then
	LogError "Corrupted blocks in the database !!!!"
	cat $SqlLogCorr
	LogCons "Log file: $SqlLogCorr"
else
	LogCons "No object with corrupted block in the DB: $DbSid"
fi

echo ""

# Check for corrupted blocks in free blocks

LogCons "List all corrupted blocks in FREE blocks.."
LogCons "Log file: $SqlLogFree"

sqlplus -s "/as sysdba" << __EOF > $SqlLogFree 2>&1
set heading on;
set timing off
set linesize 280

col SEGMENT_NAME form a40;
col PARTITION_NAME form a40;
col SEGMENT_TYPE form a18;
col DESCRIPTION form a25;

SELECT null owner, null segment_type, null segment_name, null partition_name, c.file#
     , greatest(f.block_id, c.block#) corr_start_block#
     , least(f.block_id+f.blocks-1, c.block#+c.blocks-1) corr_end_block#
     , least(f.block_id+f.blocks-1, c.block#+c.blocks-1)
       - greatest(f.block_id, c.block#) + 1 blocks_corrupted
     , 'Free Block' description
  FROM dba_free_space f, v\$database_block_corruption c
 WHERE f.file_id = c.file#
   AND f.block_id <= c.block# + c.blocks - 1
   AND f.block_id + f.blocks - 1 >= c.block#
order by file#, corr_start_block#;
__EOF

CorrBlocks=$(grep "no rows selected" $SqlLogFree)


if [[ -z $CorrBlocks ]]
then
        LogWarning "Free Corrupted blocks in the database !!!!"
        cat $SqlLogFree
        LogCons "Log file: $SqlLogFree"
else
        LogCons "No "free" corrupted block in the DB: $DbSid"
fi

