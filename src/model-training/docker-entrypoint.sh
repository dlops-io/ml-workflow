#!/bin/bash
# This image is only used interactively (via docker-shell.sh), never as a pipeline
# step, so it always opens a shell and ignores any arguments.

echo "Container is running!!!"
echo "Architecture: $(uname -m)"
echo "Environment ready! Virtual environment activated."
echo "Python version: $(python --version)"
echo "UV version: $(uv --version)"

args="$@"
echo $args

# Activate virtual environment
echo "Activating virtual environment..."
source /.venv/bin/activate

# Authenticate gcloud using service account
gcloud auth activate-service-account --key-file $GOOGLE_APPLICATION_CREDENTIALS
# Set GCP Project Details
gcloud config set project $GCP_PROJECT
# Keep a shell open
exec /bin/bash
