#!/bin/bash
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  artifact_latest_version.sh
#
# DESCRIPTION
#  Get the latest version of an artifact from Artifactory server
#
# OPTION
#
#  -V|--version                : output version information and exit
#  -h|--help                   : display this help and exit
#  -u|--url <selUrl>           : Artrifactory base URL
#  -r|--repo <selRepo>         : Artrifactory repo name
#  -g|--group <selGroup>       : artifact group id name
#  -a|--artifact <selArtifact> : artifact id name
#  -d|--default <selDefault>   : default version if no artifact found
#
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Variables
#
set +o xtrace
progName="artifact_latest_version.sh"
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

[[ $# -le 1 ]] && f_Fatal "Missing arguments"

while [ -n "$1" ] ; do
    case $1 in
      -u|--url)
          urlOpt=true
          selUrl=$2
          shift
          ;;
      -r|--repo)
          repoOpt=true
          selRepo=$2
          shift
          ;;
      -g|--group)
          groupOpt=true
          selGroup=$2
          shift
          ;;
      -a|--artifact)
          artifactOpt=true
          selArtifact=$2
          shift
          ;;
      -d|--default)
          defaultOpt=true
          selDefault=$2
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
[[ -z "$selUrl" || -z "$selRepo" || -z "$selGroup" || -z "$selArtifact" || -z "$selDefault" ]] && {
  f_Fatal "Missing mandatory arguments, see usage"
}

# Get latest version from Artifactory
#
aqlUrl="${selUrl}/artifactory/api/search/aql"
aqlData="items.find({\"repo\":\"${selRepo}\",\"path\": \"${selGroup}/${selArtifact}\",\"name\":{\"\$match\":\"${selArtifact}-*\"}}).sort({\"\$desc\":[\"created\"]}).limit(1)"


f_Debug "Post URL: ${aqlUrl}"
f_Debug "AQL filter: ${aqlData}"
urlOutput=$(curl -s --config <(echo "user=${ART_USER}:${ART_PASS}") -X POST "${aqlUrl}" -H "Content-Type: text/plain" -d "$aqlData")
if [ $? -ne 0 ]; then
  f_Fatal "Failed to get URL: '${aqlUrl}'"
fi

# Check if there is at least one version
#
urlError=$(echo "${urlOutput}" | grep -c '"errors"')
if [ $urlError -ne 0 ]; then
  f_Fatal "Error requesting Azure for artifact info !"
else
  f_Debug "Latest artifact is : ${urlOutput}"
  reArt="${selArtifact}-(.*)\.tar\.gz"

  if [[ "${urlOutput}" =~ '"total" : 0' ]]; then

    f_Warn "No version found in Artifactory, initialzing it..."
    f_Debug "Set latest version to : ${selDefault}"
    f_SetVariableIsOuput "ofaVersion" "${selDefault}"

  elif [[ "${urlOutput}" =~ '"total" : 1' ]]; then

    if [[ "${urlOutput}" =~ $reArt ]]; then
      latestVer="${BASH_REMATCH[1]}"

      f_Debug "Validate start version : ${latestVer}"
      validateVer=$(${progDir}/semver validate "${latestVer}")
      if [[ "${validateStartVer}" == "invalid" ]]; then
        f_Fatal "Version '${latestVer}' is invalid, expected semantic version format"
      fi

      f_SetVariableIsOuput "OfaVersion" "${latestVer}"
    else
      f_Fatal "Unable to extract version from artifact info !"
    fi
  else
    f_Fatal "Unable to found artifact presence !"
  fi

fi

f_ProgFooter "${progName}"
# ------------------------------------------------------------------------------
# End
