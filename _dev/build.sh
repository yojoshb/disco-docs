#!/bin/bash

if [ -e Dockerfile ] || [ -e Containerfile ]; then
    docker build -t localhost/mkdocs-site . --network=host
  else
    echo "No Dockerfile or Containerfile found in $(pwd)"; exit
fi
