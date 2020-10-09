#!/bin/sh
VERSION=11.2.0.4
IMAGE_NAME="oracle/database:${VERSION}-ee"
DOCKERFILE="Dockerfile"

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      echo "Usage: $0 -s ORACLE_SID -d /backup/dir [ -t backup_tag | -n ]"
   fi
   exit 1
}

# ################## #
# BUILDING THE IMAGE #
# ################## #

while getopts "v:" opt
do
  case $opt in
    v)
      VERSION=$OPTARG
      IMAGE_NAME="oracle/database:${VERSION}-ee"
      DOCKERFILE="Dockerfile.${VERSION}"
      ;;
    \?)
      err_exit
      ;;
  esac
done

if [ ! -f "$DOCKERFILE" ]; then
   echo "ERROR: No dockerfile found for version $VERSION"
   exit
fi

echo "Building image '$IMAGE_NAME' ..."

# BUILD THE IMAGE (replace all environment variables)
BUILD_START=$(date '+%s')
docker build --force-rm=true --no-cache=true \
       -t $IMAGE_NAME -f $DOCKERFILE . || {
  echo ""
  echo "ERROR: Oracle Database Docker Image was NOT successfully created."
  echo "ERROR: Check the output and correct any reported problems with the docker build operation."
  exit 1
}

# Remove dangling images (intermitten images with tag <none>)
yes | docker image prune > /dev/null

BUILD_END=$(date '+%s')
BUILD_ELAPSED=`expr $BUILD_END - $BUILD_START`

echo ""
echo ""

cat << EOF
  Oracle Database Docker Image for version $VERSION is ready to be extended: 
    
    --> $IMAGE_NAME

  Build completed in $BUILD_ELAPSED seconds.
  
EOF

