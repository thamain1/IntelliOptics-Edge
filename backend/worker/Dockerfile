FROM python:3.11-slim
WORKDIR /app

# Copy worker code from the Edge repo (we build from C:\Dev\IntelliOpticsDev)
COPY IntelliOptics-Edge/backend/worker/ /app/worker/

# Build a minimal SDK context: pyproject + README + package only
COPY IntelliOptics-SDK/pyproject.toml /tmp/io-sdk/pyproject.toml
COPY IntelliOptics-SDK/README.md      /tmp/io-sdk/README.md
COPY IntelliOptics-SDK/intellioptics  /tmp/io-sdk/intellioptics

# Install SDK and then worker reqs
RUN pip install --no-cache-dir /tmp/io-sdk && \
    pip install --no-cache-dir -r /app/worker/requirements.txt

CMD ["python", "/app/worker/worker.py"]
