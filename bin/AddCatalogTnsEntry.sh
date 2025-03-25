#!/bin/ksh
echo "DEPRECATED script. Do not use it anymore. use $OFA_BIN/tnsnames_adm_cli.sh instead"
$OFA_BIN/tnsnames_adm_cli.sh -a update -d RCDPRD  -m RCDPRD-vip -p 1555 -s RCDPRD
