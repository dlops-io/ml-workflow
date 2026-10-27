# Use the official Python image as the base with Python 3.13
FROM python:3.13-slim-bookworm

# Prevent apt from showing prompts
ENV DEBIAN_FRONTEND=noninteractive

# Python wants UTF-8 locale
ENV LANG=C.UTF-8

# Tell Python to disable buffering so we don't lose any logs.
ENV PYTHONUNBUFFERED=1

# Tell uv to copy packages from the wheel into the site-packages
ENV UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/.venv

# Use https for the Debian mirrors (some public Wi-Fi blocks plain-http apt)
# and install the basics
RUN find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) \
        -exec sed -i 's|http://deb.debian.org|https://deb.debian.org|g' {} + && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg jq && \
    rm -rf /var/lib/apt/lists/*

# Install the Google Cloud CLI (gcloud)
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
        gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt-get update && \
    apt-get install -y --no-install-recommends google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package installer)
RUN pip install --no-cache-dir uv

# Create a non-root user
RUN useradd -ms /bin/bash app -d /home/app -u 1000 && \
    mkdir -p /app /.venv && \
    chown app:app /app /.venv

WORKDIR /app

# Copy dependency files first for better layer caching
COPY --chown=app:app pyproject.toml uv.lock* ./

# Install dependencies in a separate layer for better caching
RUN uv sync --frozen

# Copy the rest of the source code
COPY --chown=app:app . ./

# Entry point
ENTRYPOINT ["/bin/bash","docker-entrypoint.sh"]
