FROM python:3.11-slim
WORKDIR /app

# Copy worker code from the Edge repo (we build from C:\Dev\IntelliOpticsDev)
COPY IntelliOptics-Edge/backend/worker/ /app/worker/

# Install SDK and then worker reqs
RUN pip install --no-cache-dir intellioptics==0.1.0 && \
    pip install --no-cache-dir -r /app/worker/requirements.txt

CMD ["python", "/app/worker/worker.py"]
