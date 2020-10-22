#!/bin/sh
#
OPTS="-d"
CMD=""
ORACLE_SID=oradb
DATA_MOUNT=""
ARCH_MOUNT=""
ORACLE_PWD="password"
VERSION=11.2.0.4
PORT=1521
SHM_SIZE=2192
IMAGE_NAME="oracle/database:${VERSION}-ee"
CONTAINER_NAME=""
VERSION_OPT=0

function err_exit {
    if [ -z "$1" ]; then
       echo "Usage: $0 -s ORACLE_SID -d /db/mount -l /arch/mount [ -m | -v version | -n name | -P port | -S shm_size ]"
    else
       echo "$1"
    fi
    exit 1
}

while getopts "mv:s:d:l:p:n:P:S:" opt
do
  case $opt in
    m)
      OPTS="-it"
      CMD="/bin/bash"
      ;;
    s)
      ORACLE_SID=$OPTARG
      ;;
    d)
      DATA_MOUNT=$OPTARG
      ;;
    l)
      ARCH_MOUNT=$OPTARG
      ;;
    p)
      ORACLE_PWD=$OPTARG
      ;;
    n)
      CONTAINER_NAME=$OPTARG
      ;;
    P)
      PORT=$OPTARG
      ;;
    S)
      SHM_SIZE=$OPTARG
      ;;
    v)
      VERSION=$OPTARG
      IMAGE_NAME="oracle/database:${VERSION}-ee"
      VERSION_OPT=1
      ;;
    \?)
      err_exit
      ;;
  esac
done

if [ -z "$CONTAINER_NAME" ]; then
   CONTAINER_NAME=$ORACLE_SID
fi

[ -z "$DATA_MOUNT" -o -z "$ARCH_MOUNT" -o -z "$ORACLE_SID" -o -z "$ORACLE_PWD" ] && err_exit
[ ! -d "$DATA_MOUNT" ] && err_exit "$DATA_MOUNT does not exist."
[ ! -d "$ARCH_MOUNT" ] && err_exit "$ARCH_MOUNT does not exist."
[ $(stat -c "%m" "$DATA_MOUNT") = "/" ] && err_exit "$DATA_MOUNT is not a mount point."
[ $(stat -c "%m" "$ARCH_MOUNT") = "/" ] && err_exit "$ARCH_MOUNT is not a mount point."

if [ -f $ARCH_MOUNT/dbconfig/*.dbconfig ]; then
   . $ARCH_MOUNT/dbconfig/*.dbconfig
   if [ -n "$DBVERSION" -a "$VERSION_OPT" -eq 0 ]; then
      echo "Found DB $DBVERSION configuration on $ARCH_MOUNT ..."
      VERSION=$(echo $DBVERSION | sed -n -e 's/^\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/p')
      case $VERSION in
          "18.0.0.0")
	    VERSION="18.3.0"
	    ;;
	  "19.0.0.0")
	    VERSION="19.3.0"
	    ;;
      esac
      IMAGE_NAME="oracle/database:${VERSION}-ee"
   elif [ "$VERSION_OPT" -eq 1 ]; then
	echo "WARNING: command line version $VERSION overriding config version ..."
   fi
fi

echo "Running:"
echo "VERSION: $VERSION"
echo "IMAGE  : $IMAGE_NAME"

docker run --privileged $OPTS --name $CONTAINER_NAME \
	--shm-size=${SHM_SIZE}m \
	-p ${PORT}:1521 \
	-e ORACLE_SID=${ORACLE_SID} \
	-e ORACLE_PWD=${ORACLE_PWD} \
	-e ORACLE_EDITION=EE \
	-e ORACLE_CHARACTERSET=AL32UTF8 \
	-e IMPORT_DB=1 \
	-v ${DATA_MOUNT}:/opt/oracle/oradata \
	-v ${ARCH_MOUNT}:/opt/oracle/archivelog \
	$IMAGE_NAME $CMD
