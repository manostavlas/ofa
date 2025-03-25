#!/bin/ksh
# ============================================================================
# Environnement             : axvgvaoradev01p
# Date de creation          : 10-06-2015
# Nom du script             : mapDir2Svn.ksh
# Localisation              : map dir
#                             /home/dba/oracle/local/dba/script/mep/DEVXX on
#                             svn-atlas
# Auteur                    : cek - UBP
#
# ============================================================================
# Modifications
# ============================================================================
#  Rev.   # Date       # Author # Comments
# ============================================================================
#  v1.0   # 10.06.2015 # cek    # Initial version
# -----------------------------------------------------------------------------
#
##########################################################
#            définition des variables locales
##########################################################

DEBUG=0
#DEBUG=1

#set -x
NB_PARMS=$#
OK=0
NOK=1
#rootDir=/users/svntest3
rootDir=/home/dba/oracle/local/dba/script/mep

ARCHIVE_ORIGIN_PATH=http://svn-atlas.corp.ubp.ch/atlas/NewHostMigration/

##########################################################
#            fonction donnant la syntaxe
##########################################################
function f_syntaxe
{
    [[ -t 1 ]]  && tput bel
    echo
    echo "## ======================================================================"
    echo "##    Syntaxe : mapDir2Svn.ksh <branche> <db>"
    echo "##"
    echo "##    Exemple : mapDir2Svn.ksh BJR2015 DEV30"
    echo "##"
    echo "##    Option : -h ou -help pour afficher cette aide"
    echo "## ======================================================================"
    echo
}


##########################################################
#            DEBUT DE LA PROCEDURE
##########################################################

  #######################
  # - Affichage de l'aide
  #######################
  if [ $NB_PARMS -eq 1 ]
  then
      if [[ $1 == "-h" || $1 == "-help" ]]
      then
        f_syntaxe
        exit $OK
      fi
  fi

  ########################################
  # - Vérification du nombre de paramètres
  ########################################
  if [ $NB_PARMS -eq 2 ]
  then
      BRANCHE=$1
      DB=$2
  else
      f_syntaxe
      exit $NOK
  fi

if [ `svn ls ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE} 2>/dev/null|wc -l` -ne 0 ]
then
  echo "The branche ${BRANCHE} exist"

  svn ls ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE}/db/${BRANCHE} 2>/dev/null
  if [ $? -ne 0 ]
  then
    svn mkdir ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE}/db/${BRANCHE} -m "create db directory db/${BRANCHE} automaticaly"
  fi

  svn ls ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE}/db/${BRANCHE} 2>/dev/null
  if [ $? -eq 0 ]
  then
    if [ -d ${rootDir}/${DB} ]
    then
      echo "${rootDir}/${DB} exist"
      cd ${rootDir}/${DB}

      svn info >/dev/null 2>&1
      if [ $? -eq 1 ]
      then
        svn co ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE}/db/${BRANCHE} .
      else
        CurrentBranches=`svn info|grep ^URL|awk '{print $NF}'| sed -e 's/.*\/branches\///'|awk -F / '{print $1}'`
        if [[ ${CurrentBranches} != ${BRANCHE} && `svn status|wc -l` -eq 0 ]]
        then
          echo "Not the same branches but everything saved -> switch"
          rm -fr .svn *
          svn co ${ARCHIVE_ORIGIN_PATH}branches/${BRANCHE}/db/${BRANCHE} .
        else
          if [ `svn status|wc -l` -ne 0 ]
          then
            echo "Warning there is file not saved in svn : \n`svn status`"
          fi
          echo "${rootDir}/${DB} already link to `svn info|grep ^URL|awk '{print $NF}'`"
        fi
      fi
    else
      echo "${rootDir}/${DB} doesn't exist"
    fi
  else
    echo "Problem to create db directory db/${BRANCHE} automaticaly"
  fi
else
  echo "The branche ${BRANCHE} doesn't exist"
fi

exit $OK

