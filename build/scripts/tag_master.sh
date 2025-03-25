#!/bin/bash
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  tag_master.sh
#
# DESCRIPTION
#  Tag master branch with new version product name
#
# OPTION
#
#  -v|--version <selVersion> : version number
#  -p|--product <selProduct> : product name
#
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Variables
#
set +o xtrace
progName="tag_master.sh"
progPath="$0"; export progPath
progDir=$(dirname ${progPath}); export progDir
libDir="${SCRIPTS_DIR:-${progDir}/lib}"


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
      -v|--version)
          versionOpt=true
          selVersion=$2
          shift
          ;;
      -p|--product)
          productOpt=true
          selProduct=$2
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
[[ -z "$selVersion" || -z "$selProduct" ]] && {
  f_Fatal "Missing mandatory arguments, see usage"
}

tagName="${selProduct}-${selVersion}"
tagDesc="OFA for ${selProduct} - Version ${selVersion}"
f_Debug "Create tag '${tagName}' for branch '${BUILD_SOURCEBRANCHNAME}'"

f_Debug "Set git user name and mail"
git config --global user.email "${BUILD_REQUESTEDFOREMAIL}"
[ $? -ne 0 ] && f_Fatal "Git config : unable to set user.email"
git config --global user.name "${BUILD_SOURCEVERSIONAUTHOR}"
[ $? -ne 0 ] && f_Fatal "Git config : unable to set user.name"

f_Debug "Checkout ${BUILD_SOURCEBRANCHNAME} "
git checkout $BUILD_SOURCEBRANCHNAME
[ $? -ne 0 ] && f_Fatal "Git unable to checkout branch"
git branch --set-upstream-to=origin/$BUILD_SOURCEBRANCHNAME $BUILD_SOURCEBRANCHNAME
[ $? -ne 0 ] && f_Fatal "Git unable to set upstream branch from origin"

git tag -a $tagName -m "${tagDesc}"
[ $? -ne 0 ] && f_Fatal "Git unable to tag"
git push origin --tags
[ $? -ne 0 ] && f_Fatal "Git unable to push tag to origin"


f_ProgFooter "${progName}"
# ------------------------------------------------------------------------------
# End
