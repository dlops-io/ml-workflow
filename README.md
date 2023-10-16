# Mushroom App: ML Workflow Management

In this tutorial we will put all the components we built for our Mushroom App together. We will then apply workflow management methods to test, execute, monitor, and automate these components:
* Data Collector: Scraps image from the internet and stores them into a `raw` folder.
* Data Processor: Checks images for duplicates, validate image formats, converts images to TF Records
* Model Training: Submits training jobs to Vertex AI to train models
* Model Deploy: Updates trained models signature with preprocessing logic added to it. Upload model to Vertex AI Model Registry and Deploy model to Model Endpoints.
<img src="images/ml-workflow-managment.png"  width="800">

## Prerequisites
* Have Docker installed
* Cloned this repository to your local machine with a terminal up and running
* Check that your Docker is running with the following command

`docker run hello-world`

### Install Docker 
Install `Docker Desktop`

#### Ensure Docker Memory
- To make sure we can run multiple container go to Docker>Preferences>Resources and in "Memory" make sure you have selected > 4GB

### Install VSCode  
Follow the [instructions](https://code.visualstudio.com/download) for your operating system.  
If you already have a preferred text editor, skip this step.  

## Setup Environments
In this tutorial we will setup a container to manage packaging python code for training and creating jobs on Vertex AI (AI Platform) to run training tasks.

**In order to complete this tutorial you will need your GCP account setup and a WandB account setup.**

### Clone the github repository
- Clone or download from [here](https://github.com/dlops-io/ml-workflow)

### API's to enable in GCP for Project
Search for each of these in the GCP search bar and click enable to enable these API's
* Vertex AI API

### Setup GCP Credentials
Next step is to enable our container to have access to Storage buckets & Vertex AI(AI Platform) in  GCP. 

#### Create a local **secrets** folder

It is important to note that we do not want any secure information in Git. So we will manage these files outside of the git folder. At the same level as the `ml-workflow` folder create a folder called **secrets**

Your folder structure should look like this:
```
   |-ml-workflow
      |-images
        |-src
        |---data-collector
        |---data-processor
        |---model-deploy
        |---model-training
        |---workflow
   |-secrets
```

#### Setup GCP Service Account
- Here are the step to create a service account:
- To setup a service account you will need to go to [GCP Console](https://console.cloud.google.com/home/dashboard), search for  "Service accounts" from the top search box. or go to: "IAM & Admins" > "Service accounts" from the top-left menu and create a new service account called "ml-workflow". For "Service account permissions" select "Storage Admin", "AI Platform Admin", "Vertex AI Administrator", "Service Account User".
- This will create a service account
- On the right "Actions" column click the vertical ... and select "Manage keys". A prompt for Create private key for "ml-workflow" will appear select "JSON" and click create. This will download a Private key json file to your computer. Copy this json file into the **secrets** folder. Rename the json file to `ml-workflow.json`

### Create GCS Bucket

We need a bucket to store files that we will be used by Vertext AI Pipelines during the ML workflow.

- Go to `https://console.cloud.google.com/storage/browser`
- Create a bucket `mushroom-app-ml-workflow-demo` [REPLACE WITH YOUR BUCKET NAME]

## Data Collector Container

The data collector container does the following:
* Downloads images from Bing based on the search terms provided
* Organizes the label folders as the search terms
* Zip the images and uploads to GCS Bucket
* If you run `cli.py` with the appropriate arguments your output folder should look like:
```
|-raw
   |---amanita mushrooms
   |---crimini mushrooms
   |---oyster mushrooms

```

### Run Container & Test CLI
#### Run `docker-shell.sh` or `docker-shell.bat`
Based on your OS, run the startup script to make building & running the container easy

This is what your `docker-shell` file will look like:
```
export IMAGE_NAME="mushroom-app-data-collector"
export BASE_DIR=$(pwd)
export PERSISTENT_DIR=$(pwd)/../../../persistent-folder/
export SECRETS_DIR=$(pwd)/../../../secrets/
export GCP_PROJECT="ac215-project" [REPLACE WITH YOUR PROJECT]
export GCS_BUCKET_NAME="mushroom-app-ml-workflow-demo" [REPLACE WITH YOUR BUCKET NAME]

# Build the image based on the Dockerfile
#docker build -t $IMAGE_NAME -f Dockerfile .
# M1/2 chip macs use this line
docker build -t $IMAGE_NAME --platform=linux/arm64/v8 -f Dockerfile .

# Run Container
docker run --rm --name $IMAGE_NAME -ti \
-v "$BASE_DIR":/app \
-v "$SECRETS_DIR":/secrets \
-v "$PERSISTENT_DIR":/persistent \
-e GOOGLE_APPLICATION_CREDENTIALS=/secrets/data-service-account.json \
-e GCP_PROJECT=$GCP_PROJECT \
-e GCS_BUCKET_NAME=$GCS_BUCKET_NAME \
$IMAGE_NAME
```

- Make sure you are inside the `data-collector` folder and open a terminal at this location
- Run `sh docker-shell.sh` or `docker-shell.bat` for windows

#### Test Data Collector

* Run `python cli.py --search --nums 10 --query "oyster mushrooms" "crimini mushrooms" "amanita mushrooms"`
* Go and check your GCS bucket to see if `raw.zip` was uploaded. 

## OPTIONAL: Build & Push Data Collector Image
This step has already been done for this tutorial. For this tutorial in order to make the docker images public we pushed them to docker hub. 

### Pushing Docker Image to Docker Hub
* Sign up in Docker Hub and create an [Access Token](https://hub.docker.com/settings/security)
* Login to the Hub: `docker login -u <USER NAME> -p <ACCESS TOKEN>`
* Build and Tag the Docker Image: `docker build -t <USER NAME>/mushroom-app-data-collector -f Dockerfile .`
* If you are on M1/2 Macs: Build and Tag the Docker Image: `docker build -t <USER NAME>/mushroom-app-data-collector --platform=linux/amd64/v2 -f Dockerfile .`
* Push to Docker Hub: `docker push <USER NAME>/mushroom-app-data-collector`

## Automate Running Data Collector Container

In this section we will use Vertex AI Pipelines to automate running the task in our data collector container

### In the folder `workflow` Run `docker-shell.sh` or `docker-shell.bat`
Based on your OS, run the startup script to make building & running the container easy

This is what your `docker-shell` file will look like:
```
export IMAGE_NAME="mushroom-app-workflow"
export BASE_DIR=$(pwd)
export SECRETS_DIR=$(pwd)/../../../secrets/
export GCP_PROJECT="ac215-project" [REPLACE WITH YOUR PROJECT]
export GCS_BUCKET_NAME="mushroom-app-ml-workflow-demo" [REPLACE WITH YOUR BUCKET NAME]
export GCS_SERVICE_ACCOUNT="ml-workflow@ac215-project.iam.gserviceaccount.com" [REPLACE WITH YOUR SERVICE ACCOUNT]

# Build the image based on the Dockerfile
#docker build -t $IMAGE_NAME -f Dockerfile .
docker build -t $IMAGE_NAME --platform=linux/amd64 -f Dockerfile .


# Run Container
docker run --rm --name $IMAGE_NAME -ti \
-v /var/run/docker.sock:/var/run/docker.sock \
-v "$BASE_DIR":/app \
-v "$SECRETS_DIR":/secrets \
-v "$BASE_DIR/../data-collector":/data-collector \
-v "$BASE_DIR/../data-processor":/data-processor \
-e GOOGLE_APPLICATION_CREDENTIALS=/secrets/ml-workflow.json \
-e GCP_PROJECT=$GCP_PROJECT \
-e GCS_BUCKET_NAME=$GCS_BUCKET_NAME \
-e GCS_SERVICE_ACCOUNT=$GCS_SERVICE_ACCOUNT \
$IMAGE_NAME
```

- Make sure you are inside the `workflow` folder and open a terminal at this location
- Run `sh docker-shell.sh` or `docker-shell.bat` for windows

### Run Data Collector in Vertex AI
In this step we will run the data collector container as a serverless task in Vertex AI Pipelines.

* Run `python cli.py --data_collector`, this will package the data collector docker image as a Vertex AI Pipeline job and create a definition file called `data_collector.yaml`. This step also creates an `PipelineJob` to run on Vertex AI
* Inspect `data_collector.yaml`
* Go to [Vertex AI Pipeline](https://console.cloud.google.com/vertex-ai/pipelines) to inspect the status of the job



