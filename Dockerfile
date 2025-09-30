# IntelliOptics Edge Endpoint — production image

# ---------- Build Args ----------
ARG NGINX_PORT=30101
ARG NGINX_PORT_OLD=6717
ARG UVICORN_PORT=6718
ARG APP_ROOT="/intellioptics-edge"
ARG POETRY_HOME="/opt/poetry"
ARG POETRY_VERSION=1.8.3

# ---------- Base / Build Stage ----------
FROM python:3.11-slim-bullseye AS base-build

# Bring args into this stage
ARG APP_ROOT
ARG POETRY_HOME
ARG POETRY_VERSION


# System deps + Azure CLI (keyring) + Poetry (pip)

# System deps, Azure CLI (signed keyring), Poetry, kubectl
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash ca-certificates curl gnupg less lsb-release libgl1-mesa-glx libglib2.0-0 nginx sqlite3 unzip; \
    mkdir -p /usr/share/keyrings; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/azure-cli-archive-keyring.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/azure-cli-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ bullseye main" > /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends azure-cli; \

    python -m pip install --no-cache-dir "poetry==${POETRY_VERSION}"; \

    \
    # Poetry (pin via POETRY_VERSION)
    curl -fsSL https://install.python-poetry.org | POETRY_HOME=${POETRY_HOME} python -; \
    \
    # kubectl (latest stable)
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
    chmod 0755 /usr/local/bin/kubectl; \
    \
    # Clean

    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Global env (shared by both stages)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    POETRY_HOME=${POETRY_HOME} \
    POETRY_VERSION=${POETRY_VERSION} \
    PATH=${POETRY_HOME}/bin:$PATH \
    PYTHONPATH=${APP_ROOT}:${APP_ROOT}/app

# Leverage Docker cache: copy only dependency files first
WORKDIR ${APP_ROOT}
COPY ./pyproject.toml ./poetry.lock ${APP_ROOT}/

# Install prod dependencies into the system env (no venv)
RUN set -eux; \
    poetry --version; \
    poetry config virtualenvs.create false; \
    poetry check --lock; \
    poetry install --no-interaction --no-root --without dev --without lint; \
    poetry cache clear --all pypi || true

# Create expected directories used at runtime
RUN mkdir -p /etc/intellioptics/edge-config /etc/intellioptics/inference-deployment /opt/intellioptics/edge/sqlite

# Copy configs needed by final stage
COPY configs ${APP_ROOT}/configs
COPY deploy/k3s/inference_deployment/inference_deployment_template.yaml /etc/intellioptics/inference-deployment/

# ---------- Final / Production Image ----------
FROM base-build AS production-image

ARG APP_ROOT
ARG NGINX_PORT
ARG NGINX_PORT_OLD
ARG UVICORN_PORT
ARG POETRY_HOME

ENV PATH=${POETRY_HOME}/bin:$PATH \
    APP_PORT=${UVICORN_PORT} \
    PYTHONPATH=${APP_ROOT}:${APP_ROOT}/app

WORKDIR ${APP_ROOT}

# App code & artifacts
COPY /app ${APP_ROOT}/app/
COPY /deploy ${APP_ROOT}/deploy/
COPY /licenses ${APP_ROOT}/licenses/
COPY /README.md ${APP_ROOT}/README.md

# Normalize CRLF -> LF and ensure exec bit on shell scripts
RUN set -eux; \
    if [ -d "${APP_ROOT}/app/bin" ]; then \
      find ${APP_ROOT}/app/bin -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; ; \
      chmod +x ${APP_ROOT}/app/bin/*.sh || true; \
    fi

# Nginx config from the copied configs
COPY --from=base-build ${APP_ROOT}/configs/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx site and route logs to STDOUT/STDERR
RUN set -eux; \
    rm -f /etc/nginx/sites-enabled/default || true; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Entrypoint: launches your edge logic server (which should start nginx/uvicorn as needed)
CMD ["/bin/bash", "-c", "./app/bin/launch-edge-logic-server.sh"]

# Document the exposed ports
EXPOSE ${NGINX_PORT} ${NGINX_PORT_OLD}
