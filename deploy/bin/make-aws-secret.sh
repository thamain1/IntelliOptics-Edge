#!/bin/bash

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

VALUES_FILE=${VALUES_FILE:-../helm/groundlight-edge-endpoint/values.yaml}
if [ -z "${REGISTRY_SECRET_NAME:-}" ] && command -v python3 >/dev/null 2>&1; then
    REGISTRY_SECRET_NAME=$(python3 - "$VALUES_FILE" <<'PY'
import sys
from pathlib import Path

def parse_simple_yaml(path: Path):
    root = {}
    stack = [root]
    indents = [-1]
    for raw_line in path.read_text().splitlines():
        line = raw_line.split('#', 1)[0].rstrip('\n')
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(' '))
        while len(stack) > 1 and indent <= indents[-1]:
            stack.pop()
            indents.pop()
        if ':' not in line:
            continue
        key, value = line.strip().split(':', 1)
        value = value.strip()
        current = stack[-1]
        if not value:
            new_dict = {}
            current[key] = new_dict
            stack.append(new_dict)
            indents.append(indent)
        else:
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            current[key] = value
    return root

data = parse_simple_yaml(Path(sys.argv[1]))
registry = data.get('registry', {})
secret_name = registry.get('secretName') or 'registry-credentials'
print(secret_name)
PY
)
fi
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}

# Run the refresh-ecr-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-ecr-login.sh

# Now we try to find the AWS credentials.  Let's look in the CLI
if command -v aws >/dev/null 2>&1; then
    # Try to retrieve AWS credentials from aws configure
    AWS_ACCESS_KEY_ID_CMD=$(aws configure get aws_access_key_id 2>/dev/null)
    AWS_SECRET_ACCESS_KEY_CMD=$(aws configure get aws_secret_access_key 2>/dev/null)
fi
# Use the CLI credentials if available, otherwise use environment variables
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_CMD:-$AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_CMD:-$AWS_SECRET_ACCESS_KEY}

# Check that we have credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    fail "No AWS credentials found"
fi

# Create the secret with either retrieved or environment values
$K delete --ignore-not-found secret aws-credentials
$K create secret generic aws-credentials \
    --from-literal=aws_access_key_id=$AWS_ACCESS_KEY_ID \
    --from-literal=aws_secret_access_key=$AWS_SECRET_ACCESS_KEY

# Verify secrets have been properly created
if ! $K get secret "$REGISTRY_SECRET_NAME"; then
    # These should have been created in refresh-ecr-login.sh
    fail "${REGISTRY_SECRET_NAME} secret not found"
fi

if ! $K get secret aws-credentials; then
    echo "aws-credentials secret not found"
fi

