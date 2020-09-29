#!/bin/sh
VERSION=11.2.0.4
IMAGE_NAME="oracle/database:${VERSION}-ee"
ORACLE_SID=oradb
CONTAINER_NAME=""
ORACLE_PWD="password"
CREATE_PDB=1

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      echo "Usage: $0 -s ORACLE_SID [ -v version | -n name | -p password | -r ]"
   fi
   exit 1
}

while getopts "s:n:p:v:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      ;;
    n)
      CONTAINER_NAME=$OPTARG
      ;;
    p)
      ORACLE_PWD=$OPTARG
      ;;
    v)
      VERSION=$OPTARG
      IMAGE_NAME="oracle/database:${VERSION}-ee"
      ;;
    r)
      CREATE_PDB=0
      ;;
    \?)
      err_exit
      ;;
  esac
done

if [ -z "$CONTAINER_NAME" ]; then
   CONTAINER_NAME=$ORACLE_SID
fi

ORACLE_PDB=pdb_${ORACLE_SID}

docker run --privileged -d --name $CONTAINER_NAME \
	-p 1521:1521 -p 5500:5500 \
	-e ORACLE_SID=$ORACLE_SID \
	-e ORACLE_PWD=$ORACLE_PWD \
	-e ORACLE_PDB=$ORACLE_PDB \
	-e CREATE_PDB=$CREATE_PDB \
	-e ORACLE_EDITION=EE \
	-e ORACLE_CHARACTERSET=AL32UTF8 \
	-v /opt/oracle/oradata \
	--volume-driver netapp \
	$IMAGE_NAME
