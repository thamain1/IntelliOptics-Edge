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

# Copy lockfiles first for better build caching
COPY pyproject.toml poetry.lock ./

# Install Poetry and project dependencies (no venv, no dev/lint)
RUN set -eux; \
    python -m pip install --upgrade pip; \
    python -m pip install "poetry==${POETRY_VERSION}"; \
    poetry --version; \
    poetry lock --no-update; \
    poetry check --lock; \
    poetry install --no-interaction --no-root --without dev --without lint

# Now copy the rest of the source
COPY . .

# Default command (adjust if your app entry changes)
# For FastAPI API:
#   python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]