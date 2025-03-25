#
##
## Usage: SqlCl.sh <CONNECT_STRING>
##
## Start oracle oracle sqlcl
##
#

ConnPara=$*
export JAVA_HOME=${OFA_SQLCL}/$(uname)_java
export PATH=${JAVA_HOME}/bin:$PATH
export _JAVA_OPTIONS=-Djava.io.tmpdir=${TMPDIR}
$OFA_SQLCL/bin/sql $ConnPara

