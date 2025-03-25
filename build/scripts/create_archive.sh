#!/bin/bash
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  create_archive.sh
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
progName="create_archive.sh"
progPath="$0"; export progPath
progDir=$(dirname ${progPath}); export progDir
libDir="${SCRIPTS_DIR:-${progDir}/lib}"

# Repo directories
#
ofaStuff="ofa/stuff"
ofaBase="ofa/local/base"

# Archive directories
#
tmpDir="tmp"
archOfaDir="${tmpDir}/ofa"
archStuffDir="${archOfaDir}/stuff"
archLocalDir="${archOfaDir}/local"

# ------------------------------------------------------------------------------
# Libraries
#
. $libDir/lib_utils.sh

# ------------------------------------------------------------------------------
# Functions
#

#
#  f_PrepArchive
#
#  Prepare files for archiving
#
#  Usage : f_PrepArchive "product name" "source dir" "arhcive dir"
#
f_PrepArchive () {

  product="${1}"
  srcDir="${2}"
  archDir="${3}"

  f_Debug "Prepare archive for ${product^^} from '${srcDir}' to '${archDir}'"

  # List files
  #
  listFile="${tmpDir}/ofa_${product}_files.txt"
  f_Debug "${product^^} - list files $srcDir :"
  filesPath=$(find "${srcDir}" -type f -printf "%P\n")
  echo "$filesPath" > $listFile
  echo "$filesPath"

  # Prepare files for archiving
  #
  mkdir -p "${archDir}" || f_Fatal "Unable to create '${archDir}' directory"
  tar -cf - -C "${srcDir}" -T "${listFile}" | tar -xf - -C "${archDir}"
  if [ $? -ne 0 ]; then
    f_Fatal "Failed to create archive in : '${archDir}'"
  else
    f_Debug "Files temporary put into : '${archDir}'"
  fi
}


f_Symlink () {
  obj="${1}"
  link="${2}"

  ln -s "${obj}" "${link}"
  if [ $? -ne 0 ]; then
    f_Fatal "Failed to create symlink : '${link}' -> '${obj}'"
  else
    f_Debug "Symlink created : '${link}' -> '${obj}'"
  fi
}
# ------------------------------------------------------------------------------
# Options
#

[[ $# -lt 1 ]] && f_Fatal "Missing arguments"

while [ -n "$1" ] ; do
    case $1 in
      -t|--type)
          typeOpt=true
          selType=$2
          shift
          ;;
      -v|--version)
          versionOpt=true
          selversion=$2
          shift
          ;;
      -b|--build)
          buildOpt=true
          selBuild=$2
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
[[ -z "$selType" || -z "$selversion" || -z "$selBuild" ]] && {
  f_Fatal "Missing mandatory arguments, see usage"
}

f_Debug "Create archive for product : $selType"

# OFA versionning
#
f_Debug "OFAADM - set VERSION information : $selversion build $selBuild"
verDir="$ofaStuff/doc/ofa/VERSION"
mkdir -p $verDir || f_Fatal "Unable to create '$verDir' directory"
touch $verDir/OFA.changed_files
date > $verDir/OFA.lastchck
echo "$selversion" > $verDir/OFA.version.tag
touch $verDir/OFA.md5.stamp
touch $verDir/OFA.changed_files.log
hostname > $verDir/OFA.hostname
echo "$selBuild" > $verDir/OFA.version


# Ofaadm files
#
mkdir -p "${tmpDir}" || f_Fatal "Unable to create '${tmpDir}' directory"
f_PrepArchive "ofaadm" "${ofaStuff}" "${archStuffDir}"

# Ofa DB files
#
archTypeDir="${archLocalDir}/${selType}"
f_PrepArchive "base" "${ofaBase}" "${archTypeDir}"
ofaType="ofa/local/${selType}"
f_PrepArchive "${selType}" "${ofaType}" "${archTypeDir}"


# Create logs directory
#
logsDir="${archTypeDir}/logs"
f_Debug "Create logs directory : ${logsDir}"
mkdir -p "${logsDir}" || f_Fatal "Unable to create '${logsDir}' directory"


# Create ofa symlinks
#
wkDir=$(pwd)
cd "${archLocalDir}" || f_Fatal "Unable to go to '${archLocalDir}' directory"
f_Symlink "${selType}" "dba"
f_Symlink "../stuff" "ofa"
cd "${wkDir}" || f_Fatal "Unable to go to '${wkDir}' directory"
for ofaTgtDir in etc doc fct sql
do
  f_Symlink "../../ofa/${ofaTgtDir}/ofa" "${archTypeDir}/${ofaTgtDir}/ofa"
done


# Set permissions
#
find "${archOfaDir}" -type d -exec chmod 0770 {} \;
if [ $? -ne 0 ]; then
  f_Fatal "Failed to set permission 0770 set on directories under ${archOfaDir}"
else
  f_Debug "Permission 0770 set on directories under ${archOfaDir}"
fi

find "${archOfaDir}" -type f -exec chmod 0660 {} \;
if [ $? -ne 0 ]; then
  f_Fatal "Failed to set permission 0660 set on files under ${archOfaDir}"
else
  f_Debug "Permission 0660 set on files under ${archOfaDir}"
fi

find "${archOfaDir}" -type f \( -path \*/script/\* -or -path \*/bin/\* \) -exec chmod 0770 {} \;
if [ $? -ne 0 ]; then
  f_Fatal "Failed to set permission 0770 set on files under ${archOfaDir}/*/script/* or ${archOfaDir}/*/bin/*"
else
  f_Debug "Permission 0770 set on files under ${archOfaDir}/*/script/* or ${archOfaDir}/*/bin/*"
fi
f_Debug "List permissions :"
find "${archOfaDir}" -printf "%Y %m %p"\\n

# Create the artefact
#
ofaArtefact="ofa_${selType}-${selversion}.tar.gz"
cd "${archOfaDir}" || f_Fatal "Unable to go to '${archOfaDir}' directory"
tar -czf "../${ofaArtefact}" .
if [ $? -ne 0 ]; then
  f_Fatal "Failed to create artefact ${ofaArtefact}"
else
  f_Debug "Artefact ${ofaArtefact} created successfully"
fi
f_SetVariableIsOuput "OfaArtifactName" "${ofaArtefact}"
f_ProgFooter "${progName}"
# ------------------------------------------------------------------------------
# End
