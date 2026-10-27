#!/bin/bash
# Build the image for Google's machines (linux/amd64) and push it to Docker Hub.
# The Vertex AI pipeline pulls it from there by name (see the image names in
# src/workflow/cli.py), so rerun this script after every code change you want
# the pipeline to use.

# exit immediately if a command exits with a non-zero status
set -e

export IMAGE_NAME="cheese-app-data-processor"
DOCKER_USERNAME="dlops"   # change to your Docker Hub username

# amd64 only: Vertex AI runs on amd64 machines. On Apple-silicon Macs this
# build is emulated, so it is slower than docker-shell.sh.
docker build --platform linux/amd64 -t $DOCKER_USERNAME/$IMAGE_NAME --push -f Dockerfile .

echo "Pushed $DOCKER_USERNAME/$IMAGE_NAME"
