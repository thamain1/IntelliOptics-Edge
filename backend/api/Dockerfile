FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1


RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git && \
    rm -rf /var/lib/apt/lists/*
=======
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


COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip && \

    pip install --no-cache-dir -r requirements.txt

    pip install --no-cache-dir \
      fastapi "uvicorn[standard]" pydantic sqlalchemy python-multipart \
      azure-identity azure-servicebus azure-storage-blob httpx \
      /tmp/io-sdk

COPY app ./app
COPY data ./data

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
