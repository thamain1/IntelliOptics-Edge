#!/bin/bash
# This is an odd script.  It will only work from the GHA runner.
# and it expects to have access to the pulumi stack here.  Which means
# to use it you'd have to log into the runner and clone the EE repo.
# But if that's what you need to do, this will help.

# Alternately, you can use this from a workstation that has pulumi access,
# but not network access, and define the proxy host in the EEUT_PROXY_HOST
# variable.  Or you might set the EEUT_PROXY_HOST with an IP address and an SSH key like 
# export EEUT_PROXY_HOST="1.2.3.4 -i ~/.ssh/runner-admin.pem"

set -x

if [ ! -f ~/.ssh/ghar2eeut.pem ]; then
  SECRET_NAME=${EEUT_SSH_KEY_SECRET_NAME:-ghar2eeut-private-key}
  if [ -n "$AZURE_KEY_VAULT_URL" ]; then
    SECRET_ID="${AZURE_KEY_VAULT_URL%/}/secrets/$SECRET_NAME"
    az keyvault secret show --id "$SECRET_ID" --query value -o tsv > ~/.ssh/ghar2eeut.pem
  elif [ -n "$AZURE_KEY_VAULT_NAME" ]; then
    az keyvault secret show --vault-name "$AZURE_KEY_VAULT_NAME" --name "$SECRET_NAME" --query value -o tsv > ~/.ssh/ghar2eeut.pem
  else
    echo "AZURE_KEY_VAULT_URL or AZURE_KEY_VAULT_NAME must be set to retrieve the EEUT SSH key." >&2
    exit 1
  fi
  chmod 600 ~/.ssh/ghar2eeut.pem
fi

if [ -n "$EEUT_SSH_HOST" ]; then
  EEUT_IP="$EEUT_SSH_HOST"
else
  for OUTPUT in ${EEUT_PULUMI_IP_OUTPUTS:-"eeut_private_ip eeut_public_ip eeut_ip"}; do
    if EEUT_IP=$(pulumi stack output "$OUTPUT" 2>/dev/null); then
      if [ -n "$EEUT_IP" ]; then
        break
      fi
    fi
  done
fi

if [ -z "$EEUT_IP" ]; then
  echo "Unable to determine EEUT IP address. Set EEUT_SSH_HOST or ensure Pulumi exports one of: ${EEUT_PULUMI_IP_OUTPUTS:-eeut_private_ip eeut_public_ip eeut_ip}" >&2
  exit 1
fi

if [ -n "$EEUT_PROXY_HOST" ]; then
    PROXY_USER=${EEUT_PROXY_USER:-ubuntu}
    PROXY_COMMAND=(-o ProxyCommand="ssh -W %h:%p $PROXY_USER@$EEUT_PROXY_HOST")
else
    PROXY_COMMAND=()
fi

SSH_USER=${EEUT_SSH_USER:-ubuntu}

ssh -i ~/.ssh/ghar2eeut.pem "${PROXY_COMMAND[@]}" "$SSH_USER"@$EEUT_IP

