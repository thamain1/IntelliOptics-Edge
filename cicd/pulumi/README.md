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


