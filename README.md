# Cheese App: ML Workflow Management

🌐 → 🧹 → 🏋️ → 🚀 &nbsp;&nbsp;(automated with ⛓️ Vertex AI Pipelines)

The goal of this tutorial is to take the pieces of the Cheese App we have built separately (collecting images, cleaning them, training a model, deploying it) and **connect them into one automated ML pipeline** that runs in the cloud with a single command.

So far we ran each step by hand: start a container, run a command, check the bucket, start the next container. That works once, but it is slow, easy to get wrong and hard to repeat. A **workflow manager** runs the steps for us, in the right order, on cloud machines, and records what happened in each run. Here we use **Vertex AI Pipelines** (built on Kubeflow Pipelines, `kfp`).

> **Note on names:** In 2026 Google renamed Vertex AI to **Gemini Enterprise Agent Platform**. The console now says "Agent Platform", but the API (`aiplatform.googleapis.com`), the Python SDKs (`google-cloud-aiplatform`, `kfp`), Pipelines, Training, Model Registry and Endpoints work exactly as before. In this tutorial, "Vertex AI" and "Agent Platform" mean the same thing.

Here is the story, step by step:

1. **Data Collector** downloads cheese images from Bing image search for each label (brie, gouda, gruyere, parmigiano), zips them and uploads `raw.zip` to our bucket.
2. **Data Processor** downloads `raw.zip`, removes duplicate and invalid images, and uploads `clean.zip`.
3. **Model Training** submits a training job to Vertex AI. The trained model, with a serving function attached, is saved to `gs://<bucket>/model`.
4. **Model Deploy** uploads that model to the **Model Registry** and deploys it to an **Endpoint**.
5. First we run each step **on its own**, inside its own container, to make sure it works.
6. Then we **publish** the steps where Google can reach them: the data images go to Docker Hub, the training code to a bucket.
7. Finally we let **Vertex AI Pipelines** run all four steps in order, on Google's machines, with one command.

<img src="images/ml-pipeline.png" width="400">

---

## Prerequisites

Complete **[Tutorial 0 - Setup & Installs](https://github.com/dlops-io/ac215-setup)** first. It covers a GCP account and project, VS Code, Git, Docker Desktop and `uv`. This tutorial also builds on the **model training** and **model deployment** tutorials.

> You will create **your own** service account and buckets in **your own** GCP project. Training jobs and endpoints run on machines billed to that project, so do the **Clean Up** step at the end.

---

## Clone this Repository

```bash
git clone https://github.com/dlops-io/ml-workflow.git
cd ml-workflow
```

Each component lives in its own folder under `src/`, with its own container:

```
ml-workflow/src/
├── data-collector/    # Step 1
├── data-processor/    # Step 2
├── model-training/    # Step 3 (training job + trainer package)
└── workflow/          # Runs the pipeline; also defines the Model Deploy step (model.py)
```

---

## What You'll Learn
By completing this tutorial, you'll gain experience with:
- **Breaking an ML system into components**, each in its own container.
- **Pipelines as code**: describing steps and their order in Python with `kfp`, and compiling them to a pipeline definition (`.yaml`).
- **Running pipelines on Vertex AI**: serverless execution, where Google provides the machines for each step.
- **Monitoring runs** in the console: which step ran, how long it took, and where it failed.
- **Container images for pipelines**: why each step's image has to be published to a registry that Vertex AI can pull from.

---

## Key Ideas Before You Start

### Component, pipeline, run
- A **component** is one step: a container image plus the command to run in it (for example the data collector image running `cli.py --search ...`).
- A **pipeline** is a set of components and the order they run in (`.after(...)` in `workflow/cli.py`).
- A **run** (a `PipelineJob`) is one execution of a pipeline. Each run shows up in the console with its own graph, logs and status.

### How the steps talk to each other
As in the mega-pipeline tutorial, the steps do not call each other. Each step reads its input from the **GCS bucket** and writes its output back there (`raw.zip` → `clean.zip` → `model/`). The pipeline only decides **when** each step starts.

### Why the images must be in a registry
On your laptop, `docker-shell.sh` builds an image locally. Vertex AI Pipelines runs on Google's machines, which cannot see your laptop, so the data collector and processor images are **published to Docker Hub** (`dlops/cheese-app-data-collector`, `dlops/cheese-app-data-processor`) and the pipeline pulls them from there. We have already published them for this tutorial; see **Build & Push Images** in the Appendix if you want to publish your own.

### Two kinds of steps
- **Container components** (data collector, data processor) run one of our images.
  The same image works two ways, and `docker-entrypoint.sh` picks one: started by `docker-shell.sh` with **no arguments**, it opens a shell for you; started by the pipeline **with arguments** (for example `cli.py --search --nums 10 ...`, set in `src/workflow/cli.py`), it runs that command and exits.
- **Python components** (model training, model deploy in `workflow/model.py`) are small Python functions that `kfp` runs in a standard Python image; they call the Vertex AI SDK to start a training job or deploy a model.

---

## GCP Setup

### APIs to enable in GCP for your project
Search for each of these in the GCP search bar and click **Enable**:
* Agent Platform API (formerly "Vertex AI API"; service name `aiplatform.googleapis.com`)
* Cloud Storage API (usually already enabled)

Or from a terminal with gcloud: `gcloud services enable aiplatform.googleapis.com storage.googleapis.com`

### Create local **secrets** and **persistent-folder** folders
We do not want any secrets in Git, so we keep them **outside** the repository. At the same level as the `ml-workflow` folder, create two folders:
```
   |-ml-workflow
   |-persistent-folder     # scratch space the containers can keep between runs
   |-secrets
```

### Create a GCP service account

| | |
|---|---|
| **Name** | `ml-workflow` |
| **Key file** | `secrets/ml-workflow.json` |

**Roles**

| Role | ID | Why |
|---|---|---|
| Storage Admin | `roles/storage.admin` | Read and write the bucket |
| Vertex AI Administrator | `roles/aiplatform.admin` | Upload models, create endpoints, run jobs |
| Service Account User | `roles/iam.serviceAccountUser` | Lets pipeline steps run as this account |

**Steps**
1. Open **IAM & Admin > Service accounts** ([direct link](https://console.cloud.google.com/iam-admin/serviceaccounts)) and click **Create service account**.
2. Enter the name `ml-workflow` and click **Create and continue**.
3. Add each role from the table above, then click **Done**.
4. Click the new account's ⋮ (Actions) > **Manage keys** > **Add key** > **Create new key** > **JSON** > **Create**. A key file downloads.
5. Move the file into your **secrets** folder and rename it to `ml-workflow.json`.

> The console may list "Vertex AI Administrator" under the new Agent Platform name; search for `aiplatform.admin` if you cannot find it.
>
> If **Create new key** is greyed out or fails with a policy error, your organization blocks key creation (the default for new Google Cloud organizations). Use a personal project, or ask your organization admin to allow it.

### Create two GCS buckets
- Go to `https://console.cloud.google.com/storage/browser` and create, in region `us-central1`:
  - a **data/model bucket**, for example `cheese-app-ml-workflow-<your-name>`: holds `raw.zip`, `clean.zip`, the trained `model/` and the pipeline's working files (`pipeline_root/`).
  - a **trainer-code bucket**, for example `cheese-app-trainer-code-<your-name>`: holds the packaged training code and the training job outputs.
- Bucket names are global, so make them unique.

### Point the scripts at your project
Every `docker-shell.sh` under `src/` sets the same few variables at the top. Edit them in **all four** files:
```bash
export GCP_PROJECT="<your-project-id>"
export GCS_BUCKET_NAME="<your-data-bucket>"
export GCS_PACKAGE_URI="gs://<your-trainer-code-bucket>"                          # model-training, workflow
export GCS_SERVICE_ACCOUNT="ml-workflow@<your-project-id>.iam.gserviceaccount.com"  # workflow
```

---

## 🚀 Time to Build

### Part 1: Run each component on its own

Each component has its own container. For each one, `cd` into its folder and run `sh docker-shell.sh`; this builds the image and drops you into a shell inside it.

#### 1. Data Collector
```bash
cd src/data-collector
sh docker-shell.sh
python cli.py --search --nums 10 --query "brie cheese" "gouda cheese" "gruyere cheese" "parmigiano cheese"
```
This downloads up to 10 images per label into folders named after each query:
```
raw/
├── brie cheese/
├── gouda cheese/
├── gruyere cheese/
└── parmigiano cheese/
```
and uploads them as `raw.zip` to your data bucket. Check the bucket to confirm.

#### 2. Data Processor
```bash
cd src/data-processor
sh docker-shell.sh
python cli.py --clean
```
This downloads `raw.zip`, removes duplicates and invalid images, and uploads `clean.zip` to your bucket. (`python cli.py --prepare` additionally converts the clean images to TFRecords and uploads `tfrecords.zip`.)

#### 3. Model Training (as in the model training tutorial)
```bash
cd src/model-training
sh docker-shell.sh
sh package-trainer.sh
python cli.py --train
```
- `package-trainer.sh` packages the training code in `package/` as `cheese-app-trainer.tar.gz` and uploads it to your trainer-code bucket.
- `python cli.py --train` starts a **custom training job** on Vertex AI that runs that package. Follow it under **Agent Platform > Training** in the console.
- When it finishes, the trained model (with its serving function) is saved to `gs://<your-data-bucket>/model`.

> To keep training reproducible, the trainer downloads a fixed, already-cleaned dataset from GitHub (`dlops-io/datasets`, `cheese_4_labels.zip`) rather than the `clean.zip` produced in step 2.

### Part 2: Publish the components

The pipeline runs on Google's machines, which cannot see anything on your laptop. Before it can run a step, that step's code must be somewhere Google can fetch it:

| Pipeline step | What gets published | Where to | How |
|---|---|---|---|
| Data Collector | the container image | Docker Hub (`dlops/cheese-app-data-collector`) | `sh docker-build-push.sh` in `src/data-collector` |
| Data Processor | the container image | Docker Hub (`dlops/cheese-app-data-processor`) | `sh docker-build-push.sh` in `src/data-processor` |
| Model Training | the training code (`cheese-app-trainer.tar.gz`) | your trainer-code bucket | `sh package-trainer.sh`, already done in Part 1 |
| Model Deploy | nothing | n/a | it is a small Python function inside `src/workflow` |

- **You can skip the Docker Hub push.** The `dlops` images are already published, and the pipeline uses them by default. Push your own only if you change the data-collector or data-processor code; see [Build & Push Images](#build--push-images) in the Appendix.
- **The pipeline only pulls, never builds.** If you change a component's code and do not push again, the pipeline keeps running the old version.
- **The same image runs in both places.** Started by `docker-shell.sh` with no arguments, it opens a shell. Started by the pipeline with arguments (e.g. `cli.py --search ...`), it runs that command and exits. `docker-entrypoint.sh` decides which.

### Part 3: Automate with Vertex AI Pipelines

All pipeline commands run from the **workflow** container:
```bash
cd src/workflow
sh docker-shell.sh
```

#### Start small: one step as a pipeline
```bash
python cli.py --data_collector
```
This wraps the data collector image as a pipeline component, compiles it to `data_collector.yaml` and submits a `PipelineJob`. Open `data_collector.yaml` to see what was generated, then watch the run under **Agent Platform > Pipelines** ([direct link](https://console.cloud.google.com/vertex-ai/pipelines)).

#### The whole pipeline
```bash
python cli.py --pipeline
```
This chains all four steps (Data Collector → Data Processor → Model Training → Model Deploy), compiles them to `pipeline.yaml` and submits one run. Each step starts only after the previous one succeeds. In the console you should see a graph like this:

<img src="images/vertex-ai-pipeline-1.png" width="300">
<br>
<img src="images/vertex-ai-pipeline-2.png" width="300">

A full run takes a while: training alone is several minutes, and deploying an endpoint often takes 10–20 minutes.

#### Run one step of the pipeline at a time
Useful when a step fails and you want to rerun just that one:
```bash
python cli.py --data_collector
python cli.py --data_processor
python cli.py --model_training
python cli.py --model_deploy
```

#### A toy pipeline
```bash
python cli.py --sample
```
A small pipeline of Python components (square, add, square root) that shows how values pass from one step to the next, with no containers of our own.

<img src="images/vertex-ai-simeple-pipeline-1.png" width="500">

### Part 4: Clean up (important)
The Model Deploy step creates an endpoint on an `n1-standard-4` machine that **bills your project every hour**, even when nobody calls it. When you are done:

**In the console**
1. Go to **Agent Platform > Models > Endpoints**, or open [https://console.cloud.google.com/vertex-ai/online-prediction/endpoints](https://console.cloud.google.com/vertex-ai/online-prediction/endpoints).
2. Click your endpoint's name. On the row for your model, click **Actions** (⋮) > **Undeploy model from endpoint**, then **Undeploy**.
3. Back on the Endpoints list, select the endpoint, click **Actions** (⋮) > **Delete endpoint**.

**Or from the workflow container**
```bash
gcloud ai endpoints list --region=us-central1
gcloud ai endpoints describe <ENDPOINT_ID> --region=us-central1      # deployedModels: id
gcloud ai endpoints undeploy-model <ENDPOINT_ID> --region=us-central1 --deployed-model-id=<DEPLOYED_MODEL_ID>
gcloud ai endpoints delete <ENDPOINT_ID> --region=us-central1
```
Pipeline runs, training jobs and registered models do not keep running, so they do not need cleaning up. Your model in the registry is at [https://console.cloud.google.com/vertex-ai/models](https://console.cloud.google.com/vertex-ai/models).

---

## Quick Reference

| Where | Command | What it does |
|---|---|---|
| `src/data-collector` | `python cli.py --search --nums 10 --query "brie cheese" ...` | Download images, upload `raw.zip` |
| `src/data-processor` | `python cli.py --clean` | Clean images, upload `clean.zip` |
| `src/model-training` | `sh package-trainer.sh` then `python cli.py --train` | Package trainer code, start a training job |
| `src/data-collector`, `src/data-processor` | `sh docker-build-push.sh` (optional) | Publish your own image to Docker Hub |
| `src/workflow` | `python cli.py --pipeline` | Run the whole pipeline on Vertex AI |
| `src/workflow` | `python cli.py --data_collector` (or `--data_processor`, `--model_training`, `--model_deploy`) | Run one step as a pipeline |
| `src/workflow` | `python cli.py --sample` | Toy pipeline |

Then **undeploy and delete the endpoint** when you are done.

---

## Appendix

### Build & Push Images
This has already been done for this tutorial: the pipeline uses `dlops/cheese-app-data-collector` and `dlops/cheese-app-data-processor` from Docker Hub. To publish your own versions:
* Sign up on Docker Hub and create an [Access Token](https://hub.docker.com/settings/security).
* Log in: `docker login -u <USER NAME>` and paste the token when asked for a password.
* In `src/data-collector` (and `src/data-processor`), set `DOCKER_USERNAME` in `docker-build-push.sh` and run `sh docker-build-push.sh`. It builds the image for `linux/amd64` (what Vertex AI runs) and pushes it to Docker Hub. On Apple-silicon Macs the build is emulated, so it is slower than `docker-shell.sh`.
* Update `DATA_COLLECTOR_IMAGE` and `DATA_PROCESSOR_IMAGE` at the top of `src/workflow/cli.py` to your image names.

> The pipeline never builds or pushes images; it only pulls them from Docker Hub. If you change the code in `src/data-collector` or `src/data-processor`, the pipeline keeps running the old version until you run `sh docker-build-push.sh` again.

### Notes for running on Windows
* Run Docker commands from **Git BASH**.
* **Always quote `$(pwd)`**: Windows paths often contain spaces.
* If you see `the input device is not a TTY`, prefix the `docker run` command in `docker-shell.sh` with `winpty`.

### Learn more
- [Vertex AI Pipelines introduction](https://cloud.google.com/vertex-ai/docs/pipelines/introduction)
- [Kubeflow Pipelines (kfp) documentation](https://www.kubeflow.org/docs/components/pipelines/)
