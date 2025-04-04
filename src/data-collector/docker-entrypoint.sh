#!/bin/bash

echo "Container is running!!!"

args="$@"
echo $args

if [[ -z ${args} ]]; 
then
    # Authenticate gcloud using service account
    gcloud auth activate-service-account --key-file $GOOGLE_APPLICATION_CREDENTIALS
    # Set GCP Project Details
    gcloud config set project $GCP_PROJECT
    #/bin/bash
    pipenv shell
else
  pipenv run python $args
fi
