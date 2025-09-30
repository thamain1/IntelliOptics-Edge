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

# System deps + Azure CLI (keyring), Poetry, kubectl, AWS CLI v2
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      gnupg \
      less \
      lsb-release \
      libgl1-mesa-glx \
      libglib2.0-0 \
      nginx \
      sqlite3 \
      unzip; \
    \
    # Azure CLI via signed keyring
    mkdir -p /usr/share/keyrings; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/azure-cli-archive-keyring.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/azure-cli-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ bullseye main" \
      > /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends azure-cli; \
    \
    # Poetry
    curl -fsSL https://install.python-poetry.org | POETRY_HOME=${POETRY_HOME} python -; \
    \
    # kubectl
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
    chmod 0755 /usr/local/bin/kubectl; \
    \
    # AWS CLI v2
    cd /tmp; \
    curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
    unzip -q awscliv2.zip; \
    ./aws/install --update; \
    rm -rf aws awscliv2.zip; \
    \
    # cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

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

# Create expected directories
RUN mkdir -p /etc/intellioptics/edge-config \
             /etc/intellioptics/inference-deployment \
             /opt/intellioptics/edge/sqlite

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
ARG NGINX_PORT_OLD
ARG UVICORN_PORT
ARG POETRY_HOME

ENV PATH=${POETRY_HOME}/bin:$PATH \
    APP_PORT=${UVICORN_PORT}

WORKDIR ${APP_ROOT}

# Copy the remaining files
COPY /app ${APP_ROOT}/app/
COPY /deploy ${APP_ROOT}/deploy/
COPY /licenses ${APP_ROOT}/licenses/
COPY /README.md ${APP_ROOT}/README.md

# Nginx config
COPY --from=production-dependencies-build-stage ${APP_ROOT}/configs/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx site and route logs to STDOUT/STDERR
RUN rm -f /etc/nginx/sites-enabled/default && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Launch
CMD ["/bin/bash", "-c", "./app/bin/launch-edge-logic-server.sh"]

# Document the exposed ports
EXPOSE ${NGINX_PORT} ${NGINX_PORT_OLD}
