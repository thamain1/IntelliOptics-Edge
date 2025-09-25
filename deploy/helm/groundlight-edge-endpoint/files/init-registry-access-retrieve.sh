#!/bin/bash

# Part one of getting registry and artifact credentials set up.
# This script runs in a lightweight container and retrieves the credentials from the
# IntelliOptics control plane.
#
# It saves three files to the shared volume for use by part two:
# 1. /shared/credentials: The artifact storage credentials that can be mounted into pods.
# 2. /shared/token.txt: The container registry password that can be used to pull images. This will
#    be used to create a registry secret in k8s.
# 3. /shared/done: A marker file to indicate that the script has completed successfully.

# Note: This script is also used to validate the INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT
# settings. If you run it with the first argument being "validate", it will only run through the 
# check of the curl results and exit with 0 if they are valid or 1 if they are not. In the latter 
# case, it will also log the results.

if [ "$1" == "validate" ]; then
  echo "Validating INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT..."
  if [ -z "$INTELLIOPTICS_API_TOKEN" ]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting."
    exit 1
  fi

  if [ -z "$INTELLIOPTICS_ENDPOINT" ]; then
    echo "INTELLIOPTICS_ENDPOINT is not set. Exiting."
    exit 1
  fi
  validate="yes"
fi

# This function replicates the IntelliOptics SDK's logic to clean up user-supplied endpoint URLs 
sanitize_endpoint_url() {
    local endpoint="${1:-$INTELLIOPTICS_ENDPOINT}"

    # If empty, set default
    if [[ -z "$endpoint" ]]; then
        endpoint="https://intellioptics-api-37558.azurewebsites.net/"
    fi

    # Parse URL scheme and the rest
    if [[ "$endpoint" =~ ^(https?)://([^/]+)(/.*)?$ ]]; then
        scheme="${BASH_REMATCH[1]}"
        netloc="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
    else
        echo "Invalid API endpoint: $endpoint. Must be a valid URL with http or https scheme." >&2
        exit 1
    fi

    # Ensure path is properly initialized
    if [[ -z "$path" ]]; then
        path="/"
    fi

    # Ensure path ends with "/"
    if [[ "${path: -1}" != "/" ]]; then
        path="$path/"
    fi

    # Set default path if just "/"
    if [[ "$path" == "/" ]]; then
        path="/device-api/"
    fi

    # Allow only specific paths
    case "$path" in
        "/device-api/"|"/v1/"|"/v2/"|"/v3/")
            ;;
        *)
            echo "Warning: Configured endpoint $endpoint does not look right - path '$path' seems wrong." >&2
            ;;
    esac

    # Remove trailing slash for output
    sanitized_endpoint="${scheme}://${netloc}${path%/}"
    echo "$sanitized_endpoint"
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT}")
echo "Sanitized URL: $sanitized_url"

echo "Fetching temporary credentials from the IntelliOptics cloud service..."
HTTP_STATUS=$(curl -s -L -o /tmp/credentials.json -w "%{http_code}" --fail-with-body --header "x-api-token: ${INTELLIOPTICS_API_TOKEN}" ${sanitized_url}/reader-credentials)

if [ $? -ne 0 ]; then
  echo "Failed to fetch credentials from the IntelliOptics cloud service"
  if [ -n "$HTTP_STATUS" ]; then
    echo "HTTP Status: $HTTP_STATUS"
  fi
  echo -n "Response: "
  cat /tmp/credentials.json; echo
  exit 1
fi

if [ "$validate" == "yes" ]; then

  echo "API token validation successful. Exiting."
  exit 0
fi

REGISTRY_USERNAME=$(sed 's/^.*"registry_username":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
REGISTRY_PASSWORD=$(sed 's/^.*"registry_password":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
ARTIFACT_ACCESS_KEY=$(sed 's/^.*"artifact_access_key":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
ARTIFACT_SECRET_KEY=$(sed 's/^.*"artifact_secret_key":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
ARTIFACT_ENDPOINT=$(sed 's/^.*"artifact_endpoint":"\([^"]*\)".*$/\1/' /tmp/credentials.json)

cat <<EOF > /shared/credentials
access_key = ${ARTIFACT_ACCESS_KEY}
secret_key = ${ARTIFACT_SECRET_KEY}
endpoint = ${ARTIFACT_ENDPOINT}
EOF

echo "Credentials fetched and saved to /shared/credentials"
cat /shared/credentials; echo

printf '%s' "${REGISTRY_USERNAME}" > /shared/registry_username
printf '%s' "${REGISTRY_PASSWORD}" > /shared/registry_password

echo "Registry login saved to /shared/registry_username and registry_password"

printf '%s' "${ARTIFACT_ENDPOINT}" > /shared/artifact_endpoint

touch /shared/done


