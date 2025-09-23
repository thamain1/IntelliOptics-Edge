FROM python:3.11-slim
WORKDIR /app

# Copy worker code from the repo
COPY backend/worker/ /app/worker/

# Install the IntelliOptics SDK and worker requirements
RUN pip install --no-cache-dir "git+https://github.com/thamain1/IntelliOptics.git#subdirectory=python-sdk" && \
    pip install --no-cache-dir -r /app/worker/requirements.txt

CMD ["python", "/app/worker/worker.py"]
