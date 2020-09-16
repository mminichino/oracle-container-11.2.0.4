#!/bin/sh

# ################## #
# BUILDING THE IMAGE #
# ################## #

VERSION=11.2.0.4
IMAGE_NAME="oracle/database:11.2.0.4-ee"
DOCKERFILE="Dockerfile"
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

