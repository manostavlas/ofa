#!/bin/ksh
#
## Name: memreport.sh
##
## In:  Unix env. & DB connections
## Out: multiline to stdout
## Ret: 0/1
##
## Synopsis: produces a memory report host & instances
##
## Usage: memreport.sh "<DBLIST>"
##
## Description:
##
##  - Quick report on DB vs. host memory to stdout.
##  - all values in MB
##  - by default, includes all DBs on server.
##  - pass in DB names for a subset
#
# Workings:
#
#
#  ------------------------------------------------------------------------------
  #
  # load lib
  #
    . ~/*/local/$(id | sed 's/[()]/ /g' | awk '{print $2'})/etc/ofa/0fa_load.rc || exit 22

    ImaSysDba || BailOut "must be sysdba"

    echo "Oracle DBs on $HOSTNAME" | CartRidge
    ShowOraDbs

    echo "DB memory (All values in Mb.)" | CartRidge

  # -----------------------------------
  # DB's
  # -----------------------------------


    DBLIST="${DBLIST:-"$@"}"
    [[ ! -n "$DBLIST" ]] && DBLIST="$(ListOraDbs)"

    typeset SKIPPED=0
    typeset TOTAL_SGA=0
    typeset TOTAL_PGA_INUSE=0
    typeset TOTAL_PGA_ALLOCATED=0
    typeset TOTAL_PGA_MAX=0

    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 
    printf "%20s %20s %20s %20s %20s\n" "Instance" "SGA" "PGA used" "PGA alloc." "PGA max"
    printf "%20s %20s %20s %20s %20s\n" "--------" "---" "--------" "----------"  "------" 

    for SID in $DBLIST
    do
        ! OraEnv $SID && LogWarning "Failed OraEnv on \"$SID\"" && continue
        OFA_ORA_DB_STATUS="$(OraDbStatus)"
        if [[ "$OFA_ORA_DB_STATUS" != "OPEN" ]]  \
        && [[ "$OFA_ORA_DB_STATUS" != "MOUNTED" ]]
        then
            LogWarning "Instance \"$ORACLE_SID\" not accesible: status is \"$OFA_ORA_DB_STATUS\""
            let SKIPPED+=1
            continue
        fi

        SGA=$(GetSGA)                     ; IsInteger $SGA && let TOTAL_SGA+=$SGA || LogWarning "$ORACLE_SID: cound't get SGA"
        PGA_INUSE=$(GetPGA_Inuse)         ; IsInteger $PGA_INUSE && let TOTAL_PGA_INUSE+=$PGA_INUSE || LogWarning "$ORACLE_SID: cound't get PGA_INUSE"
        PGA_ALLOCATED=$(GetPGA_Allocated); IsInteger $PGA_ALLOCATED && let TOTAL_PGA_ALLOCATED+=$PGA_ALLOCATED || LogWarning "$ORACLE_SID: cound't get PGA_ALLOCATED"
        PGA_MAX=$(GetPGA_Max)             ; IsInteger $PGA_MAX && let TOTAL_PGA_MAX+=$PGA_MAX || LogWarning "$ORACLE_SID: cound't get PGA_MAX"

        printf "%20s %20d %20d %20d %20d\n" "$ORACLE_SID" "$SGA" "$PGA_INUSE" "$PGA_ALLOCATED" "$PGA_MAX"

    done
    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 
    printf "%20s %20d %20d %20d %20d\n" "Totals" "$TOTAL_SGA" "$TOTAL_PGA_INUSE" "$TOTAL_PGA_ALLOCATED" "$TOTAL_PGA_MAX"

    let TOTAL_INUSE=$TOTAL_SGA+$TOTAL_PGA_INUSE
    let TOTAL_ALLOCATED=$TOTAL_SGA+$TOTAL_PGA_ALLOCATED
    let TOTAL_MAX=$TOTAL_SGA+$TOTAL_PGA_MAX

    printf "%20s %20s %20d %20d %20d\n" "Totals with SGA" "-->" "$TOTAL_INUSE" "$TOTAL_ALLOCATED" "$TOTAL_MAX"
    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 

    LogIt "Instances skipped: $SKIPPED"

  # -----------------------------------
  # Server
  # -----------------------------------

    echo "Host memory vs. DBs above" | CartRidge

    TOTAL_HOSTMEM=$(GetHostMemTotal)
    let TOTAL_HOSTMEM_BY_INUSE=$TOTAL_HOSTMEM-$TOTAL_INUSE
    let TOTAL_HOSTMEM_BY_ALLOCATED=$TOTAL_HOSTMEM-$TOTAL_ALLOCATED
    let TOTAL_HOSTMEM_BY_MAX=$TOTAL_HOSTMEM-$TOTAL_MAX
    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 
    printf "%20s %20s %20s %20s %20s\n" "$HOSTNAME" "Host mem." "delta DB used" "delta DB alloc." "delta DB max" 
    printf "%20s %20s %20s %20s %20s\n" "---------" "---------" "-------------" "---------------"  "-----------" 
    printf "%20s %20d %20d %20d %20d\n" "Raw delta:" "$TOTAL_HOSTMEM" "$TOTAL_HOSTMEM_BY_INUSE" "$TOTAL_HOSTMEM_BY_ALLOCATED" "$TOTAL_HOSTMEM_BY_MAX"
    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 

    AVAIL_HOSTMEM=$(expr $TOTAL_HOSTMEM - $TOTAL_HOSTMEM / 5)
    let AVAIL_HOSTMEM_BY_INUSE=$AVAIL_HOSTMEM-$TOTAL_INUSE
    let AVAIL_HOSTMEM_BY_ALLOCATED=$AVAIL_HOSTMEM-$TOTAL_ALLOCATED
    let AVAIL_HOSTMEM_BY_MAX=$AVAIL_HOSTMEM-$TOTAL_MAX
    printf "%20s %20d %20d %20d %20d\n" "Avail. (20% margin):" "$AVAIL_HOSTMEM" "$AVAIL_HOSTMEM_BY_INUSE" "$AVAIL_HOSTMEM_BY_ALLOCATED" "$AVAIL_HOSTMEM_BY_MAX"
    printf "%20s-%20s-%20s-%20s-%20s\n" "--------------------" "--------------------" "--------------------" "--------------------"  "--------------------" 
    [[ $SKIPPED -gt 0 ]] && echo "Caution: $SKIPPED DBs skipped"
    echo "end report"

    OFA_TRAP_XIT=""
