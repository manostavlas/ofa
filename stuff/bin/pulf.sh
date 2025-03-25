#!/bin/ksh
#                                                     
## Name: pulf.sh
##                                                    
## In:  remote files
## Out: local files
## Ret: 0/1
##                                                    
## Synopsis: pulls over files of interest from deployment targets
##                                                    
## Usage: pulf.sh <tag>
##
##     With <tag> a graft product (oracle, sybase ...)
##     Supported products so far:
##      - oracle
##
#  ------------------------------------------------------------------------------                                                   
  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc $@ || exit 22

    OFA_TRAP_XIT=""

  #
  # check arg1 $1
  #
    [[ ! -n $1 ]] && Usage "ERROR: Supply <graft product> as arg1, pls" 


    SRV_SEEN=":"
    for TGT in $(
        egrep "$FILTER" $LOCAL_RESOURCE_FILE \
      | egrep "^[${_SPACE_}]*[${_ALPHA_}]" \
      | awk '{print $1}'
    )
    do
        TGT_ACC=$(echo $TGT | cut -d"@" -f1)
        TGT_SRV=$(echo $TGT | cut -d"@" -f2)
        PUT_DIR_SUB=$PUT_DIR/$TGT_SRV

        mkdir -p $PUT_DIR_SUB
        for TGT_DIR in $FILE_D_LIST
        do
            echo $SRV_SEEN | egrep ":$TGT_SRV:" >/dev/null && continue
            LogCons "Attempting scp $TGT:$TGT_DIR/$FILE_N_PAT $PUT_DIR_SUB"
            scp $TGT:$TGT_DIR/$FILE_N_PAT $PUT_DIR_SUB 2>/dev/null
            if [[ $? -ne 0 ]] 
            then
                LogCons "(NOK)"
                continue
            fi
            LogCons "(OK)"
            echo $SRV_SEEN | egrep ":$TGT_SRV:" >/dev/null || SRV_SEEN="$SRV_SEEN$TGT_SRV:"
        done
    done

  #
  # post-process data
  #
    aggfunc

