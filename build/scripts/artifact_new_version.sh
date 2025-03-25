#!/bin/bash
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  artifact_new_version.sh
#
# DESCRIPTION
#  Calculate next semantic version for artifact
#
# OPTION
#
#  -V|--version               : output version information and exit
#  -h|--help                  : display this help and exit
#  -s|--start <selStartVer>   : starting version
#  -l|--latest <selLatestVer> : latest version
#
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Variables
#
set +o xtrace
progName="artifact_new_version.sh"
progPath="$0"; export progPath
progDir=$(dirname ${progPath}); export progDir
libDir="${SCRIPTS_DIR:-${progDir}}"

# ------------------------------------------------------------------------------
# Libraries
#
. $libDir/lib_utils.sh

# ------------------------------------------------------------------------------
# Options
#

[[ $# -lt 1 ]] && f_Fatal "Missing arguments"

while [ -n "$1" ] ; do
    case $1 in
      -s|--start)
          startOpt=true
          selStartVer=$2
          shift
          ;;
      -l|--latest)
          latestOpt=true
          selLatestVer=$2
          shift
          ;;
      *)
          f_Fatal "Error: unknown option/parameter '$1'"
          ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Main
#

f_ProgHeader "${progName}"

# Check mandatory arguments
#
[[ -z "$selStartVer" || -z "$selLatestVer" ]] && {
  f_Fatal "Missing mandatory arguments, see usage"
}

# Validate start version
#
f_Debug "Validate start version  : ${selStartVer}"
validateStartVer=$(semver validate "${selStartVer}")
if [[ "${validateStartVer}" == "invalid" ]]; then
  f_Fatal "Start version argument '${selStartVer}' is invalid, expected semantic version format"
fi

# Validate latest version
#
f_Debug "Validate latest version : ${selLatestVer}"
validateLatestVer=$(semver validate "${selLatestVer}")
if [[ "${validateLatestVer}" == "invalid" ]]; then
  f_Fatal "Latest version argument '${selLatestVer}' is invalid, expected semantic version format"
fi

# Compare start with latest version to determine current version
#
cmpVer=$(semver compare "${selStartVer}" "${selLatestVer}")
if [[ "${cmpVer}" -eq 1 ]]; then
  f_Debug "Start version is greater than latest : ${cmpVer}"
  curVer="${selStartVer}"
else
  curVer="${selLatestVer}"
fi
f_Debug "Current version full    : ${curVer}"

curVerShort=$(semver get release ${curVer})
f_Debug "Current version short   : ${curVerShort}"

# Next version short
#
if [[ "${curVer}" == "${curVerShort}" ]]; then
  nextVer=$(semver bump patch ${curVer})
else
  nextVer="${curVerShort}"
fi
f_Debug "Next version short      : ${nextVer}"

# New version
#
f_Debug "Branch name    : ${BUILD_SOURCEBRANCHNAME}"
f_Debug "Build reason   : ${BUILD_REASON}"

curPrerel=$(semver get prerel ${curVer})
f_Debug "Current prerel : ${curPrerel}"

if [[ "${BUILD_SOURCEBRANCHNAME}" == "master" ]]; then
  cmpVer=$(semver compare "${curVerShort}" "${curVer}")
  if [[ "${cmpVer}" -eq 1 ]]; then
    preVer="${curVerShort}"
  else
    preVer="${nextVer}"
  fi
else
  if [[ "${BUILD_REASON}" == "PullRequest" ]]; then
    if [[ "${curPrerel}" == "RC"* ]]; then
      preVer=$(semver bump prerel ${curVer})
    else
      preVer=$(semver bump prerel RC ${nextVer})
    fi
  else
    if [[ "${curPrerel}" == "beta"* ]]; then
      preVer=$(semver bump prerel ${curVer})
    else
      preVer=$(semver bump prerel beta ${nextVer})
    fi
  fi
fi

f_Debug "New version is : ${preVer}"


# Build number
#
numBuild=$(date +"%Y%m%d.%H.%M.%S")
fullVer=$(semver bump build  "build.${numBuild}" "${preVer}")
f_Debug "Full version   : ${fullVer}"

# Resume
#
f_SetVariableIsOuput "OfaFullVersion" "${fullVer}"
f_SetVariableIsOuput "OfaBaseVersion" "${preVer}"
f_SetVariableIsOuput "OfaBuildNumber" "${numBuild}"

echo "##vso[build.updatebuildnumber]$preVer"

f_ProgFooter "${progName}"
# ------------------------------------------------------------------------------
# End
