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
#   backend/api/app  --> copied to /app/app
COPY backend/api/app /app/app

# --- Python deps ---
# Install the published IntelliOptics SDK from your package registry (e.g. PyPI).
# If you don’t need Postgres in this image, you can drop "psycopg[binary]"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      fastapi "uvicorn[standard]" pydantic sqlalchemy python-multipart \
      azure-identity azure-servicebus azure-storage-blob httpx \
      intellioptics-sdk

EXPOSE 8080

# EITHER (recommended)
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]

# OR, if you prefer the factory pattern, use this instead:
# CMD ["uvicorn","app.main:create_app","--factory","--host","0.0.0.0","--port","8080"]
