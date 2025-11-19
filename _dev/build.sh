#!/bin/bash

BUILD_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -e $BUILD_DIR/Dockerfile ] || [ -e $BUILD_DIR/Containerfile ]; then
    docker build -t localhost/mkdocs-site . --network=host
  else
    echo "No Dockerfile or Containerfile found in $BUILD_DIR"; exit
fi
