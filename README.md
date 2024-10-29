# Cheese App: ML Workflow Management

In this tutorial we will put all the components we built for our Cheese App together. We will then apply workflow management methods to test, execute, monitor, and automate these components:
* Data Collector: Gathers images from the internet and stores them into a `raw` folder.
* Data Processor:  Removes duplicate images, validates formats, and converts images into TFRecord format.
* Model Training: Submits training jobs to Vertex AI to train the models.
* Model Deploy: Updates the model signature with preprocessing logic, then uploads the model to the Vertex AI Model Registry and deploys it to Model Endpoints.
<img src="images/ml-pipeline.png"  width="400">

## Setup Environments
In this tutorial we will setup a container to manage packaging python code for training and creating jobs on Vertex AI (AI Platform) to run training tasks.


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
- Create a bucket `cheese-app-ml-workflow-demo` [REPLACE WITH YOUR BUCKET NAME]

<hr> 

<hr> 


## Data Collector Container

The data collector container does the following:
* Downloads images from Bing based on the search terms provided
* Organizes the label folders as the search terms
* Zip the images and uploads to GCS Bucket
* If you run `cli.py` with the appropriate arguments your output folder should look like:
```
|-raw
   |---brie cheese
   |---gouda cheese
   |---gruyere cheese
   |---parmigiano cheese

```


## Run Data Collector Container & Test CLI  & Test CLI
#### Run `docker-shell.sh`
The startup script is to make building & running the container easy



- Make sure you are inside the `data-collector` folder and open a terminal at this location
- Run `sh docker-shell.sh`

#### Test Data Collector

* Run `python cli.py --search --nums 10 --query "brie cheese" "gouda cheese" "gruyere cheese" "parmigiano cheese"`
* Go and check your GCS bucket to see if `raw.zip` was uploaded. 


<hr> 

<hr> 

##  Run Data Processor Container & Test CLI
#### Run `docker-shell.sh`
The startup script is to make building & running the container easy


- Make sure you are inside the `data-processor` folder and open a terminal at this location
- Run `sh docker-shell.sh`

#### Test Data Processor

* Run `python cli.py --clean`
* Go and check your GCS bucket to see if `clean.zip` was uploaded. 
* Run `python cli.py --prepare`
* Go and check your GCS bucket to see if `tfrecords.zip` was uploaded. 

<hr> 

<hr> 

## Run Model Training Container & Test CLI
#### Run `docker-shell.sh`
The startup script is to make building & running the container easy

- Make sure you are inside the `model-training` folder and open a terminal at this location
- Run `sh docker-shell.sh`

#### Test Model Training

##### Local Training
* Run `python -m package.trainer.task --epochs=1 --batch_size=4 --bucket_name=cheese-app-ml-workflow-demo`
##### Remote Training
* Run `sh package-trainer.sh`, this will package the trainer code and upload into a bucket
* Run `python cli.py --train`, this will invoke a Vertex AI training job


<hr> 

<hr> 

## Build & Push Images
This step has already been done for this tutorial. But for completeness here are the steps. 

### Pushing Docker Image to Docker Hub
* Sign up in Docker Hub and create an [Access Token](https://hub.docker.com/settings/security)
* Login to the Hub: `docker login -u <USER NAME> -p <ACCESS TOKEN>`
* Build and Tag the Docker Image: `docker build -t <USER NAME>/<IMAGE_NAME> -f Dockerfile .`
* If you are on M1/2 Macs: Build and Tag the Docker Image: `docker build -t <USER NAME>/<IMAGE_NAME> --platform=linux/amd64/v2 -f Dockerfile .`
* Push to Docker Hub: `docker push <USER NAME>/<IMAGE_NAME>`

<hr> 

<hr> 


## Automate Running Data Collector Container

In this section we will use Vertex AI Pipelines to automate running the task in our data collector container

### In the folder `workflow` Run `docker-shell.sh`
The startup script is to make building & running the container easy

- Make sure you are inside the `workflow` folder and open a terminal at this location
- Run `sh docker-shell.sh`

### Run Data Collector in Vertex AI
In this step, we’ll run the data collector container as a serverless task within Vertex AI Pipelines. This demonstration will focus on the first part of the pipeline, and in the following steps, we’ll proceed to run the complete pipeline.


* Run `python cli.py --data_collector`, this will package the data collector docker image as a Vertex AI Pipeline job and create a definition file called `data_collector.yaml`. This step also creates an `PipelineJob` to run on Vertex AI
* Inspect `data_collector.yaml`
* Go to [Vertex AI Pipeline](https://console.cloud.google.com/vertex-ai/pipelines) to inspect the status of the job

## Cheese App: Vertex AI Pipelines
In this section we will use Vertex AI Pipelines to automate running of all the tasks in the cheese app

### Run Workflow Pipeline in Vertex AI
In this step we will run the workflow as serverless tasks in Vertex AI Pipelines.

#### Entire Pipeline
* Run `python cli.py --pipeline`, this will orchestrate all the tasks for the workflow and create a definition file called `pipeline.yaml`.
* Inspect `pipeline.yaml`
* Go to [Vertex AI Pipeline](https://console.cloud.google.com/vertex-ai/pipelines) to inspect the status of the job

You should be able to see the status of the pipeline in Vertex AI similar to this:

<img src="images/vertex-ai-pipeline-1.png"  width="300">
<br>
<img src="images/vertex-ai-pipeline-2.png"  width="300">


#### Test Specific Components

* For Data Collector: Run `python cli.py --data_collector`
* For Data Processor: Run `python cli.py --data_processor`
* For Model Training: Run `python cli.py --model_training`
* For Model Deploy: Run `python cli.py --model_deploy`


## Vertex AI Pipelines: Samples

In this section we will simple pipelines and run it on Vertex AI

### In the folder `workflow` Run `docker-shell.sh`
- Make sure you are inside the `workflow` folder and open a terminal at this location
- Run `sh docker-shell.sh`

#### Run Simple Pipelines

* Sample Pipeline 1: Run `python cli.py --sample`
<img src="images/vertex-ai-simeple-pipeline-1.png"  width="500">
<br>
