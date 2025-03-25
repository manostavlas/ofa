#!/usr/bin/env bash
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  lib_utils.sh
#
# DESCRIPTION
#  Function for display in shell scripts
#
# FUNCTION LIST
#
#   f_Timestamp Display     : Display formated timestamp
#   f_ProgHeader {progName} : Display program header
#   f_ProgFooter {progName} : Display program footer
#   f_ProgHeader1 {text}    : Display title H1
#   f_ProgHeader2 {text}    : Display title H2
#   f_ProgHeader3 {text}    : Display title H3
#   f_Success		    : Display [  OK  ] in green if terminal support
#   f_Failure		    : Display [FAILED] in red if terminal support
#   f_Passed		    : Display [PASSED] in orange if terminal support
#
# REVISION
#
#  $Revision: 2271 $
#  $Author: cfs $
#  $Date: 2015-10-15 09:58:14 +0200 (Thu, 15 Oct 2015) $
#
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Variables
#
_dashes='------------------------------------------------------------------------------'
_blanks='                                                                              '


# ------------------------------------------------------------------------------
# Functions
#

#
#  f_Timestamp
#
#  Display formated timestamp, ex : 2007-05-18 15:36:03
#
#  Usage : f_Timestamp
#
f_Timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

#
#  f_ProgHeader
#
#  Display program header
#
#  The calculation is based on dashes length
#   77:  total lenght
#   22:  date lenght
#    x:  prefix lenght : 6=start, 4=end, 0=other
#
#  Usage : f_ProgHeader $progName
#
f_ProgHeader() {
  echo "##[section]******************************************************************************"
  _dispSlen=`echo "$1" | wc -c`
  _dispLen=`expr 77 - 22 - 6 - $_dispSlen`
  [ $_dispLen -lt 0 ] && _dispLen=5
  _dispDash=`echo $_dashes|cut -c1-$_dispLen`
  echo "##[section]"`f_Timestamp`" ${_dispDash} [Start ${1}]"
  unset _dispLen
  unset _dispSlen
  unset _dispDash
}

#
#  f_ProgFooter
#
#  Display program footer
#
#  The calculation is based on dashes length
#   77:  total lenght
#   22:  date lenght
#    x:  prefix lenght : 6=start, 4=end, 0=other
#
#  Usage : f_ProgFooter $progName
#
f_ProgFooter() {
  _dispSlen=`echo "$1" | wc -c`
  _dispLen=`expr 77 - 22 - 4 - $_dispSlen`
  [ $_dispLen -lt 0 ] && _dispLen=5
  _dispDash=`echo $_dashes|cut -c1-$_dispLen`
  echo "##[section]"`f_Timestamp`" ${_dispDash} [End ${1}]"
  echo "##[section]******************************************************************************"
  unset _dispLen
  unset _dispSlen
  unset _dispDash
}

#
#  f_EchoNoNL
#
#  Same as echo but no new line
#
#  Usage : f_EchoNoNL "my message"
#
function f_EchoNoNL {
  printf "$*"
}

#
#  f_Debug
#
#  Display debug message
#
#  Usage : f_Debug "my message"
#
f_Debug () {
  f_EchoNoNL "##[debug]" 1>&2
  printf "$@" 1>&2
  echo 1>&2
}

#
#  f_Warn
#
#  Display warning message
#
#  Usage : f_Warn "my message"
#
f_Warn () {
  f_EchoNoNL "##vso[task.logissue type=warning]" 1>&2
  printf "$@" 1>&2
  echo 1>&2
}


#
#  f_Error
#
#  Display error message
#
#  Usage : f_Error "my message"
#
f_Error () {
  f_EchoNoNL "##vso[task.logissue type=error]" 1>&2
  printf "$@" 1>&2
  echo 1>&2
}

#
#  f_Fatal
#
#  Display error message and quit
#
#  Usage : f_Fatal "my message"
#
f_Fatal () {
  f_EchoNoNL "##vso[task.logissue type=error]" 1>&2
  printf "$@" 1>&2
  echo 1>&2
  exit 1
}

#
#  f_SetVariable
#
#  Set variable for further use in tasks
#
#  Usage : f_SetVariable "variable name" "variable value" "isoutpur" "issecret" "isread"
#
f_SetVariableIsOuput () {
  f_Debug "Set variable name '${1}' to value '${2}'"
  f_EchoNoNL "##vso[task.setvariable variable=${1};isOutput=true]${2}" 1>&2
  echo 1>&2
}

# ------------------------------------------------------------------------------
# End

