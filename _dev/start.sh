#!/bin/bash

docker run --rm -d -it --name=mkdocs -p 8001:8000 -v ${PWD}:/docs localhost/mkdocs-site:latest

#podman run --rm -d -it --name=mkdocs -p 8001:8000 -v ${PWD}:/docs:Z localhost/mkdocs-site:latest