# Dockerfile (repo root)
FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps (keep minimal)
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# --- App code ---
# Your FastAPI package lives here in your repo:
#   Azure/intellioptics-oneclick/backend/app  --> copied to /app/app
COPY Azure/intellioptics-oneclick/backend/app /app/app

# --- IntelliOptics SDK ---
# Mirror the worker image by copying in the vendored SDK sources
COPY IntelliOptics-SDK/pyproject.toml /tmp/io-sdk/pyproject.toml
COPY IntelliOptics-SDK/README.md      /tmp/io-sdk/README.md
COPY IntelliOptics-SDK/intellioptics  /tmp/io-sdk/intellioptics

# --- Python deps ---
# If you don’t need Postgres in this image, you can drop "psycopg[binary]"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      fastapi "uvicorn[standard]" pydantic sqlalchemy python-multipart \
      azure-identity azure-servicebus azure-storage-blob httpx \
      /tmp/io-sdk

EXPOSE 8080

# EITHER (recommended)
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]

# OR, if you prefer the factory pattern, use this instead:
# CMD ["uvicorn","app.main:create_app","--factory","--host","0.0.0.0","--port","8080"]
