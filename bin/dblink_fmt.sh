  #
  # Formatting routine
  # Glues together quoted string over newlines
  # Note:
  # This does NOT manage two or more quoted strings, possibly spanning newlines. 
  # However, such a case is not expected, so we're good. 
  # ------------------------------------------------------------------------------
  #
FileName=$1
    typeset STMT=""
    typeset in=0
    typeset CR="
            " # i.e., newline with spacing

#    cat  dblink_xtr.out | while read LINE
    cat $FileName  | while read LINE
    do
        echo $LINE | egrep "^ *$" && continue

        if [[ $LINE = "CREATE"* ]]
        then
          #
          # create DROP statement
          #
            echo $LINE | sed 's/^CREATE /DROP /;s/\("[^ ][^ ]*"\).*/\1;/'
          #
          # Sent _previous_ (i.e. complete & formatted) statement to stdio
          # At the first iteration, $STMT is the empty string
          #
            echo "$STMT;"
          #
          # Initialize STMT
          #
            STMT="$LINE"
        else
          #
          # Append next chunk to statement.
          # $CR is either the empty string or newline
          #
            STMT="${STMT}${CR}${LINE}"
        fi

        if [[ $in -eq 0 ]] && [[ $LINE = *"VALUES '"* ]] 
        then 
          #
          # A quoted string starts on this line
          #
            CR=""  # glue (the null string)
            in=1
        fi
        if [[ "$LINE" = *"'" ]] || [[ "$LINE" = *"' "* ]] 
        then
          #
          # A quoted string _ends_ on this line
          #
            CR="
            " # i.e., newline with spacing
            in=0
        fi
    done
  #
  # last statement
  #
    echo "$STMT;"


