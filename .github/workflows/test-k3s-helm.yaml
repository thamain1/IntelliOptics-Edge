# IntelliOptics Edge — production image (Python 3.11)
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_VERSION=1.8.3 \
    POETRY_VIRTUALENVS_CREATE=false

# System deps (adjust as needed)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ffmpeg \
        libgl1 \
    ; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy lockfiles first for better cache behavior
COPY pyproject.toml poetry.lock ./

# Install Poetry and prod dependencies (no venv, no dev/lint) — no config writes
RUN set -eux; \
    python -m pip install --upgrade pip; \
    python -m pip install "poetry==${POETRY_VERSION}"; \
    poetry --version; \
    poetry lock --no-update; \
    poetry check --lock; \
    poetry install --no-interaction --no-root --without dev --without lint

# Copy the rest of the source
COPY . .

# Default command (FastAPI API)
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]