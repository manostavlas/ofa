#!/bin/ksh
  #                                                     
  ## Name: revoke_file.sh
  ##
  ## In:  file paths relative to OFA_ROOT
  ## Out: files deleted
  ## Ret: 0/1
  ##
  ## Synopsis: revoke stray or obsolete files from ofa environments
  ##
  ## Usage: RevokeFile <file-path|list-of-file-paths> [filter]
  ##
  ## Note:
  ## - <file-path> is relative from $OFA_ROOT
  ##    for the relevant portion, use LsInOfaRoot on the file(s)
  ## - Multiple paths can be supplied using a file
  ## - <filter> works cumulative on $OFATAB to restrict scope.
  ##
  ## Description:
  ##
  ## - This function iterates over $OFATAB as per <filter>, connects to host string 
  ##   found in record and if found, deletes there, permissions permitting.
  ## 
  ## Caution:
  ##    This script prompts:
  ##  - once for the file
  ##  - once for the target list
  ## After that, processing is automatic non stop.
  ## 
  ## Note:
  ## This script NEVER deletes a file at the master.
  ## See to this manually if needed.
  #
  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

    function DoFile {
    
        if [[ "$FTR" = *"stuff/"* ]]
        then
          # -- files in "stuff" are owned by the core library owner, OFA_O
            SSH_U="\$OFA_O"
        elif [[ "$FTR" = *"local/"* ]]
        then
          # -- files in "local" are owned by the graft product owner, GRF_O
            SSH_U="\$GRF_O"
        else
            LogError "File Path not in ofa ecosystem -- cannot proceed"
        fi

        for REC in $(
          #
          # Filling spaces in OfaTabIter output with colons.
          # so this "for"-loop processes each record as one item.
          # A while loop would be compromised by the pipes in the loop body
          #
            OfaTabIter $TGT_FILTR | sed "s/[${_SPACE_}]/:/g"
        );do
          #
          # clean out space fillings inserted above
          # 
            REC="$(echo $REC | sed "s/::*/ /g")"

            LongBanner "$REC" | LogStdIn
            ! OfaTabParseLine $REC \
            && LogWarning "Bad Parse: \"$REC\" - skip on" \
            && return
    
          # -- assign ssh user
          #
            eval SSH_U=$SSH_U
            ! CheckVar SSH_U \
            && LogWarning "ssh user void - problem parsing line from \$OFATAB: \"$REC\" - skip on" \
            && return

          # -- under local/*, replace immediate subdir by grat name (GRF_N)
          #
            if [[ "$FTR" = "local/"* ]] && [[ CROSS_GRAFT_BOUNDARIES = "Y" ]]
            then
                FTR_ORIG="$FTR"
                FTR="$(echo $FTR | sed "s@local/[^/][^/]*\(.*\)@local/$GRF_N\1@")"
                [[ "$FTR_ORIG" != "$FTR" ]] \
                && LogIt "substituted product name in path:" \
                && LogIt "from: $FTR_ORIG" \
                && LogIt "to  : $FTR" 
            fi
    
          # -- assign FQFP end FDIR
          #
            FQFP="$OFA_R/$FTR"
            FDIR="$(dirname $FQFP)"
    
          # -- make sure of trusted ssh connection
          #
            ssh $SSH_U@$SRV_N "date 2>/dev/null >/dev/null"
            [[ $? -ne 0 ]] \
            && LogWarning "cannot ssh $SSH_U@$SRV_N -- skip on" \
            && continue
            LogIt "ssh $SSH_U@$SRV_N \"ls -ld $FQFP\""
        
            R_FILE="$(ssh $SSH_U@$SRV_N "ls -ld $FQFP")" 
            [[ ! -n "$R_FILE" ]]  \
            && LogIt "File cannot be read by $SSH_U@$SRV_N or does not exist on $SRV_N" \
            && continue
    
            LogIt "File exists on $SRV_N: \"$R_FILE\""
            ssh $SSH_U@$SRV_N "test -w $FDIR" 2>/dev/null >/dev/null
            if [[ $? -eq 0 ]]
            then
                LogNDo "ssh $SSH_U@$SRV_N \"rm -f $FQFP\""
                R_FILE="$(ssh $SSH_U@$SRV_N "ls -ld $FQFP 2>/dev/null")"
                [[ ! -n "$R_FILE" ]] \
                && LogIt "deleted: \"$SSH_U@$SRV_N:$FQFP\"" \
                || LogWarning "resisted> \"$SSH_U@$SRV_N:$FQFP\""
            fi
         done
    }
 
  # ===========================
  # ==         Main          ==
  # ===========================

    VolSet 1

    typeset FLIST
    FLIST="$1" 
    CheckVar FLIST && shift 1 || Usage "Missing <file path|list>"

       [[ ! -f "$FLIST" ]] \
    && [[ "$FLIST" != "local/"* ]] \
    && [[ "$FLIST" != "stuff/"* ]] \
    && Usage "<file path> must be \"local/*\" or \"stuff/*\", or a file icontaining such paths"

    if [[ -f "$FLIST" ]] 
    then
        egrep "^ *local/.*|^ *stuff/.*" $FLIST || Usage "file list in \"$FLIST\" has none of expected items like \"local/*\" or \"stuff/*\""
    fi

    typeset TGT_FILTR="$(echo $@|sed 's/[${_SPACE_}][${_SPACE_}]*[^=][^=]*=[${_SPACE_}]*[^${_SPACE_}]*[^${_SPACE_}]*/ /')"
    
    LogCons "Target List:"
    OfaTabIter $TGT_FILTR | LogCartRidge
 
    Prompt GO "Target List OK ? [N]"
    [[ "$GO" != [Yy]* ]] && ExitGently "(User Canceled)"

    if [[ "$CROSS_GRAFT_BOUNDARIES" = "Y" ]]
    then
        VolSet 1
        cat <<-EOF | LogCartRidge

|       CROSS_GRAFT_BOUNDARIES is set to \"Y\"
|       This will disregard the original product in the path.
|
|           E.g:     local/oracle/.../<file>
|           becomes  local/<product>/.../<file>  # as per target

|                      ---------------------
|       IF YOU DO NOT INTEND TO DELETE FILES IN OTHER PRODUCTS
|                           BACK OUT NOW
|                      --------* * *--------

EOF
        VolPrv
        Prompt GO "REALLY CONTINUE ? [N] => "
        [[ "$GO" != [Yy]* ]] && ExitGently "(User Canceled)"
    fi

    if [[ -f "$FLIST" ]]
    then
        LogIt "Taking revocation candidates from file \"$(ls -l $FLIST)\""
        LogCons "File list contents"
        cat $FLIST | LogCartRidge
        Prompt GO "Process above file list ? [N] => "
        [[ "$GO" != [Yy]* ]] && ExitGently "(User Canceled)"
        for FTR in $(egrep "local/|stuff/" $FLIST | awk '{print $1}')
        do
            LongBanner "File is \"$FTR\"" | LogStdIn
            DoFile
        done
    else
        FTR="$FLIST"   
        echo "file path:  \"$FTR\"" | LogCartRidge
        Prompt GO "Process above file path ? [N] => "
        [[ "$GO" != [Yy]* ]] && ExitGently "(User Canceled)"
        DoFile
    fi
