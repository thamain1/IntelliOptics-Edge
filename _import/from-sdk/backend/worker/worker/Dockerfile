FROM python:3.11-slim
WORKDIR /app

# Copy worker code (relative to build context root)
COPY Azure/intellioptics-oneclick/worker-shim/ /app/

# Bring in the IntelliOptics SDK wheel (built locally)
COPY intellioptics-python-sdk/dist/intellioptics-0.1.0-py3-none-any.whl /tmp/

# Sanity check
RUN ls -l /tmp

# Install deps + SDK from wheel
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir azure-identity azure-servicebus "psycopg[binary]" sqlalchemy pydantic httpx \
      /tmp/intellioptics-*.whl

CMD ["python","worker.py"]
