# Pulumi automation

Pulumi automation to build an EE from scratch in EC2 and run basic integration tests.

## Azure Key Vault configuration for Fabric tasks

The Fabric helper tasks now read the EEUT SSH private key directly from Azure Key Vault.
Set the following environment variables before running `fab` commands so the tasks can
authenticate and locate the secret:

* `AZURE_KEY_VAULT_URL` &mdash; Base URL of the vault, for example `https://my-vault.vault.azure.net`.
* `AZURE_KEY_VAULT_BEARER_TOKEN` &mdash; Bearer token that grants `get` access to secrets
  in the vault. You can obtain one with `az account get-access-token --resource https://vault.azure.net`.
* `AZURE_EEUT_PRIVATE_KEY_SECRET_NAME` &mdash; Name of the secret containing the EEUT SSH
  private key. Defaults to `eeut-ssh-private-key` if unset.
* `AZURE_KEY_VAULT_API_VERSION` *(optional)* &mdash; Overrides the API version used when
  calling Key Vault. Defaults to `7.4`.

Ensure the bearer token has permission to read the configured secret and refresh it when it
expires. Automation should inject these environment variables so Fabric can retrieve the key
material during deployment verification.


