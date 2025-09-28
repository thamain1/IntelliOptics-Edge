# Dockerfile for IntelliOptics API
FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps (keep minimal)
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git \
 && rm -rf /var/lib/apt/lists/*

# --- App code ---

# Copy the FastAPI sources from this repository into the image
COPY api/app /app/app
=======
# Your FastAPI package lives here in your repo:
#   Azure/intellioptics-oneclick/backend/app  --> copied to /app/app
COPY Azure/intellioptics-oneclick/backend/app /app/app

# --- IntelliOptics SDK ---
# Mirror the worker image by copying in the vendored SDK sources
COPY IntelliOptics-SDK/pyproject.toml /tmp/io-sdk/pyproject.toml
COPY IntelliOptics-SDK/README.md      /tmp/io-sdk/README.md
COPY IntelliOptics-SDK/intellioptics  /tmp/io-sdk/intellioptics


# --- Python deps ---
COPY api/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt \
      azure-identity azure-servicebus azure-storage-blob httpx \

      "intellioptics @ git+https://github.com/thamain1/IntelliOptics.git#subdirectory=python-sdk"
      /tmp/io-sdk


EXPOSE 8080

# EITHER (recommended)
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]

# OR, if you prefer the factory pattern, use this instead:
# CMD ["uvicorn","app.main:create_app","--factory","--host","0.0.0.0","--port","8080"]
