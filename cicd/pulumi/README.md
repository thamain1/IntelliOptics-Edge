# Pulumi automation

Pulumi automation to build an EE from scratch in Azure and run basic integration tests.

## Configuration

Set the following stack configuration values before running `pulumi up`:

* `ee-cicd:instanceType` – Azure VM size (defaults to `Standard_NC6s_v3`).
* `ee-cicd:targetCommit` – Git commit to deploy.
* `ee-cicd:resourceGroupName` – Resource group containing the network and Key Vault resources.
* `ee-cicd:virtualNetworkName` – Virtual network hosting the EEUT subnet.
* `ee-cicd:subnetName` – Subnet for the EEUT VM.
* `ee-cicd:networkSecurityGroupName` – Network security group to associate with the NIC.
* `ee-cicd:keyVaultName` – Key Vault that stores the IntelliOptics API token.
* `ee-cicd:intelliOpticsSecretName` – Name of the Key Vault secret with the IntelliOptics API token.
* `ee-cicd:sshPublicKey` – SSH public key injected into the VM.
* `ee-cicd:adminUsername` – (Optional) admin username for the VM (defaults to `azureuser`).
* `ee-cicd:imagePublisher`, `ee-cicd:imageOffer`, `ee-cicd:imageSku`, `ee-cicd:imageVersion` – (Optional) image reference overrides for the VM.

The deploying identity must have permission to read secrets from the specified Key Vault.

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


