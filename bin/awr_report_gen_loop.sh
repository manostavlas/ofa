#!/bin/ksh

  #
  # load lib
  #
  . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22  > /dev/null 2>&1

# Usage: $ScriptName [SID] [START_SNAPID] [END_SNAPID] [MAIL_LIST]

DbName=$1
StartSnap=$2
EndSnap=$3
MailList=$4

LogCons "DbName=$DbName, StartSnap=$StartSnap, EndSnap=$EndSnap, MailList=$MailList"

StartSnapLoop=$StartSnap
StopLoop=$EndSnap

while [[ $StartSnapLoop < $StopLoop ]];do
	let EndSnapLoop=$StartSnapLoop+1
	LogCons "Running: awr_report_gen.sh $DbName $StartSnapLoop $EndSnapLoop $MailList"
	$OFA_BIN/awr_report_gen.sh ${DbName} ${StartSnapLoop} ${EndSnapLoop} ${MailList}
	let StartSnapLoop=$StartSnapLoop+1
done
