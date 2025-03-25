#!/usr/bin/python3
# ------------------------------------------------------------------------------
#
# SYNOPSIS
#  bmc_discovery.py -q <query> [ -h | -i ]
#
# DESCRIPTION
#
#
# OPTION
#
#  -q|--query <selQuery> : BMC discovery query
#  -h|--noheader         : Do not display column headers
#  -i|--insecure         : Do not check certificates
#
# EXAMPLE
#
# bmc_discovery.py -q "search Host" 2>/dev/null
#
# REVISION
#
#  $Revision: 2614 $
#  $Author: aie $
#  $Date: 2018-09-25 08:23:44 +0200 (Tue, 25 Sep 2018) $
#
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Variables
#

discoServer = "addm.corp.ubp.ch"
discoApiToken = "NDpkYmE6OjptdmNTdUU0bTJVRU0zME9GT1JwSnJEd05lZ0xYNHZSaFFrVVVSZ0Q3MGhiSmpta0U2N2Qwc1E6MC1hMzNlOTcwYmIyOGYzYmJlNmM4MWFhOGNkZGU3ZWE5YzBhZDVkNGU1NTZjZjU4NzY5NjM5OWUyZTIzMmJkNjNl"
discoLimit = 1000

# ------------------------------------------------------------------------------
# Librairies
#
import sys
import requests
import json
import getopt

# ------------------------------------------------------------------------------
# Logging
#
import logging
logger = logging.getLogger('discovery')
logger.setLevel(logging.DEBUG)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
console.setFormatter(formatter)
logger.addHandler(console)



# ------------------------------------------------------------------------------
# Functions
#

def f_DiscoAPI( url, query, a_Result ):

  logger.debug( "f_DiscoAPI: " + url )


  headers = {
      'authorization': "Bearer " + discoApiToken,
      'content-type': "application/json"
      }

  body = "{{\n\t\"query\": \"{0}\"\n}}".format( query )

  try:
    response = requests.request("POST", url, data=body, headers=headers, verify=selInsecure)
    response.raise_for_status()
  except requests.exceptions.HTTPError as responseError:
    logger.critical(responseError)
    sys.exit(1)

  jsonRes = json.loads(response.text)

  # Store all results
  a_Result.append( jsonRes[0]["results"])


  if 'next' in jsonRes[0]:
    f_DiscoAPI( jsonRes[0]["next"] , query, a_Result )

  else:
    logger.info( "Query found " + str( jsonRes[0]["count"] ) + " results" )


  return jsonRes[0]["headings"], a_Result


# ------------------------------------------------------------------------------
# Options
#

options, remainder = getopt.getopt(sys.argv[1:],'q:h:i',['query=','noheader','insecure'])


selQuery = 0
selHeader = True
selInsecure = True


for opt, arg in options:
  if opt in ('-q','--query'):
    selQuery = arg
  elif opt in ('-h','--noheader'):
    selHeader = False
  elif opt in ('-i','--insecure'):
    selInsecure = False

# ------------------------------------------------------------------------------
# Main
#
logger.info( "START PROGRAM : BMC Discovery request" )


# Check for query argument
#
if selQuery:
  logger.info( selQuery )
else:
  logger.error( "Please specify query with -q or --query argument" )
  sys.exit(1)

baseUrl = "https://" + discoServer + "/api/v1.0/data/search?limit=" + str(discoLimit)

a_Header, a_Data = f_DiscoAPI( baseUrl, selQuery, [] )

if selHeader:
  print( ';'.join( str(item) for item in a_Header) )

for a_DataPart in a_Data:
  for a_Line in a_DataPart:
    a_SanitizeLine = []
    for cell in a_Line:
      if cell is None:
        a_SanitizeLine.append( str(cell) )
      else:
        try:
           a_SanitizeLine.append( str(cell) )
        except UnicodeError:
           a_SanitizeLine.append( cell.encode('utf-8') )

    print( ';'.join( a_SanitizeLine ) )


logger.info( "END PROGRAM : BMC Discovery request" )
# ------------------------------------------------------------------------------
# End
