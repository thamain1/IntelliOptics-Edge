FROM python:3.11-slim



# Install SDK and then worker reqs
RUN pip install --no-cache-dir intellioptics==0.1.0 && \

# Copy worker code from the repo
COPY backend/worker/ /app/worker/



# Copy worker code from the repo
COPY backend/worker/ /app/worker/


# Install the IntelliOptics SDK and worker requirements
RUN pip install --no-cache-dir "git+https://github.com/thamain1/IntelliOptics.git#subdirectory=python-sdk" && \
    pip install --no-cache-dir -r /app/worker/requirements.txt

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . .


CMD ["python", "worker.py"]
