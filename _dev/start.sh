#!/bin/bash

docker run --rm -d -it --name=mkdocs -p 8001:8000 -v ${PWD}:/docs localhost/mkdocs-site:latest
