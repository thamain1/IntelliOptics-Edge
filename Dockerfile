# This Dockerfile is used to build the edge-endpoint container image.

# Build args
ARG NGINX_PORT=30101
ARG NGINX_PORT_OLD=6717
ARG UVICORN_PORT=6718
ARG APP_ROOT="/intellioptics-edge"
ARG POETRY_HOME="/opt/poetry"
ARG POETRY_VERSION=1.5.1

#############
# Build Stage
#############
FROM python:3.11-slim-bullseye AS production-dependencies-build-stage

# Args that are needed in this stage
ARG APP_ROOT
ARG POETRY_HOME
ARG POETRY_VERSION

# Install required dependencies and tools
# Combine the installations into a single RUN command
# Ensure that we have the bash shell since it doesn't seem to be included in the slim image.
# This is useful for exec'ing into the container for debugging purposes.
# We need to install libGL dependencies (`libglib2.0-0` and `libgl1-mesa-lgx`)
# since they are required by OpenCV
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \

        apt-transport-https \
        bash \
        ca-certificates \
        curl \
        gnupg \
        less \
        libgl1-mesa-glx \
        libglib2.0-0 \
        lsb-release \
        nginx \
        sqlite3 \
        unzip; \
    curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null; \
    AZ_REPO=$(lsb_release -cs); \
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | tee /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends azure-cli; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    POETRY_HOME=${POETRY_HOME} curl -sSL https://install.python-poetry.org | python -; \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \

    apt-transport-https \
    bash \
    ca-certificates \
    curl \
    gnupg \
    less \
    libglib2.0-0 \
    libgl1-mesa-glx \
    sqlite3 \
    ca-certificates \
    gnupg \
    lsb-release && \

    lsb-release \
    nginx \
    sqlite3 \
    unzip && \
    POETRY_HOME=${POETRY_HOME} curl -sSL https://install.python-poetry.org | python - && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends azure-cli && \
    rm -f /usr/share/keyrings/microsoft.gpg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

    nginx \
    sqlite3 \
    unzip && \
    mkdir -p /usr/share/keyrings && \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor -o /usr/share/keyrings/azure-cli-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/azure-cli-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ bullseye main" > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends azure-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    POETRY_HOME=${POETRY_HOME} curl -sSL https://install.python-poetry.org | python - && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \

    rm kubectl

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Set Python and Poetry ENV vars
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    POETRY_HOME=${POETRY_HOME} \
    POETRY_VERSION=${POETRY_VERSION} \
    PATH=${POETRY_HOME}/bin:$PATH

# Copy only required files first to leverage Docker caching
COPY ./pyproject.toml ./poetry.lock ${APP_ROOT}/

WORKDIR ${APP_ROOT}

# Install production dependencies only
RUN poetry install --no-interaction --no-root --without dev --without lint && \
    poetry cache clear --all pypi

# Create /etc/intellioptics directory where edge-config.yaml and inference_deployment.yaml will be mounted
RUN mkdir -p /etc/intellioptics/edge-config && \
    mkdir -p /etc/intellioptics/inference-deployment

# Adding this here for testing purposes. In production, this will be mounted as persistent
# volume in kubernetes
RUN mkdir -p /opt/intellioptics/edge/sqlite

# Copy configs
COPY configs ${APP_ROOT}/configs

COPY deploy/k3s/inference_deployment/inference_deployment_template.yaml \
    /etc/intellioptics/inference-deployment/


##################
# Production Stage
##################
FROM production-dependencies-build-stage AS production-image

ARG APP_ROOT
ARG NGINX_PORT
ARG UVICORN_PORT

ENV PATH=${POETRY_HOME}/bin:$PATH \
    APP_PORT=${UVICORN_PORT}

WORKDIR ${APP_ROOT}

# Copy the remaining files
COPY /app ${APP_ROOT}/app/
COPY /deploy ${APP_ROOT}/deploy/
COPY /licenses ${APP_ROOT}/licenses/
COPY /README.md ${APP_ROOT}/README.md

COPY --from=production-dependencies-build-stage ${APP_ROOT}/configs/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx config
RUN rm /etc/nginx/sites-enabled/default

# Ensure Nginx logs to stdout and stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

CMD ["/bin/bash", "-c", "./app/bin/launch-edge-logic-server.sh"]

# Document the exposed port, which is configured in nginx.conf
EXPOSE ${NGINX_PORT} ${NGINX_PORT_OLD}

