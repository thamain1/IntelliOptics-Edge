#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

ACR_NAME=${ACR_NAME:-""}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-""}
ACR_USERNAME=${ACR_USERNAME:-""}
ACR_PASSWORD=${ACR_PASSWORD:-""}

if [ -z "$ACR_LOGIN_SERVER" ]; then
    if [ -z "$ACR_NAME" ]; then
        echo "Either ACR_LOGIN_SERVER or ACR_NAME must be set"
        exit 1
    fi
    ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
fi

if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
    if [ -z "$ACR_NAME" ]; then
        echo "ACR_NAME must be set when ACR credentials are not provided"
        exit 1
    fi
    ACR_USERNAME=${ACR_USERNAME:-$(az acr credential show --name "$ACR_NAME" --query username -o tsv)}
    ACR_PASSWORD=${ACR_PASSWORD:-$(az acr credential show --name "$ACR_NAME" --query passwords[0].value -o tsv)}
fi

echo "Fetched ACR credentials for $ACR_LOGIN_SERVER"

if command -v docker >/dev/null 2>&1; then
    echo "$ACR_PASSWORD" | docker login \
        --username "$ACR_USERNAME" \
        --password-stdin \
        "$ACR_LOGIN_SERVER"
else
    echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD"

echo "Stored ACR credentials in secret registry-credentials"

