#!/bin/sh
#
OPTS="-d"
CMD=""
ORACLE_SID=oradb
DATA_MOUNT=""
ARCH_MOUNT=""
ORACLE_PWD="password"
VERSION=11.2.0.4
IMAGE_NAME="oracle/database:${VERSION}-ee"
CONTAINER_NAME=""

function err_exit {
    if [ -z "$1" ]; then
       echo "Usage: $0 -s ORACLE_SID -d /db/mount -l /arch/mount [ -m | -v version | -n name ]"
    else
       echo "$1"
    fi
    exit 1
}

while getopts "mv:s:d:l:p:n:" opt
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
    v)
      VERSION=$OPTARG
      IMAGE_NAME="oracle/database:${VERSION}-ee"
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

docker run --privileged $OPTS --name $CONTAINER_NAME \
	--shm-size=2192m \
	-p 1521:1521 -p 5500:5500 \
	-e ORACLE_SID=${ORACLE_SID} \
	-e ORACLE_PWD=${ORACLE_PWD} \
	-e ORACLE_EDITION=EE \
	-e ORACLE_CHARACTERSET=AL32UTF8 \
	-e IMPORT_DB=1 \
	-v ${DATA_MOUNT}:/opt/oracle/oradata \
	-v ${ARCH_MOUNT}:/opt/oracle/archivelog \
	$IMAGE_NAME $CMD
