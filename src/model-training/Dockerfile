# Use the official Ubuntu image as the base
FROM ubuntu:20.04

# Set the environment variable for non-interactive installations
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV PYENV_SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1

# Install required dependencies
RUN apt-get update && \
    apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release openssh-client

# Add the Google Cloud SDK repository
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

# Install packages
RUN apt-get update && \
    apt-get install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin jq

# Python
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3.9 python3-pip && \
    pip install pipenv

RUN useradd -ms /bin/bash app -d /home/app -u 1000 -p "$(openssl passwd -1 Passw0rd)" && \
    mkdir -p /app && \
    mkdir -p /persistent && \
    chown app:app /persistent && \
    chown app:app /app

# Switch to the new user
USER app
WORKDIR /app

# Install python packages
ADD --chown=app:app Pipfile Pipfile.lock /app/

RUN pipenv sync

# Add the rest of the source code. This is done last so we don't invalidate all
# layers when we change a line of code.
ADD --chown=app:app . /app

# Entry point
ENTRYPOINT ["/bin/bash","./docker-entrypoint.sh"]