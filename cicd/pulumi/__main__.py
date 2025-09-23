import base64
import subprocess
import uuid

import pulumi
import pulumi_azure_native as azure_native
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

config = pulumi.Config("ee-cicd")
vm_size = config.require("instanceType")
stackname = pulumi.get_stack()

resource_group_name = config.require("resourceGroupName")
virtual_network_name = config.require("virtualNetworkName")
subnet_name = config.require("subnetName")
network_security_group_name = config.require("networkSecurityGroupName")
key_vault_name = config.require("keyVaultName")
intellioptics_secret_name = config.require("intelliOpticsSecretName")
admin_username = config.get("adminUsername") or "azureuser"
ssh_public_key = config.require("sshPublicKey")
image_publisher = config.get("imagePublisher") or "Canonical"
image_offer = config.get("imageOffer") or "0001-com-ubuntu-server-jammy"
image_sku = config.get("imageSku") or "22_04-lts"
image_version = config.get("imageVersion") or "latest"

client_config = azure_native.authorization.get_client_config()

def build_vault_uri(name: str) -> str:
    return f"https://{name}.vault.azure.net"

# We're creating an "edge endpoint under test" (eeut)

vault_uri = build_vault_uri(key_vault_name)

# Resolve the network resources we need.
subnet = azure_native.network.get_subnet_output(
    resource_group_name=resource_group_name,
    virtual_network_name=virtual_network_name,
    subnet_name=subnet_name,
)

network_security_group = azure_native.network.get_network_security_group_output(
    resource_group_name=resource_group_name,
    network_security_group_name=network_security_group_name,
)

def get_intellioptics_token() -> str:
    """Retrieve the IntelliOptics API token from Azure Key Vault."""
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_uri, credential=credential)
    secret = client.get_secret(intellioptics_secret_name)
    return secret.value

def get_target_commit() -> str:
    """Gets the target commit hash."""
    target_commit = config.require("targetCommit")
    if target_commit == "main":
        target_commit = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode("utf-8").strip()
    print(f"Using target commit {target_commit}")
    return target_commit

def load_user_data_script() -> str:
    """Loads and customizes the user data script for the instance, which is used to install 
    everything on the instance."""
    with open('../bin/install-on-ubuntu.sh', 'r') as file:
        user_data_script0 = file.read()
    
    # Do all synchronous replacements first
    target_commit = get_target_commit()
    user_data_script1 = user_data_script0.replace("__EE_COMMIT_HASH__", target_commit)

    # Apply image tag replacement (also synchronous)
    image_tag = config.get("eeImageTag") or "release"
    user_data_script2 = user_data_script1.replace("__EEIMAGETAG__", image_tag)

    # Apply API token replacement as the final async transformation
    api_token = pulumi.Output.secret(get_intellioptics_token())
    final_script = api_token.apply(
        lambda token: user_data_script2.replace("__GROUNDLIGHTAPITOKEN__", token)
    )

    return final_script

public_ip = azure_native.network.PublicIPAddress(
    "eeut-public-ip",
    resource_group_name=resource_group_name,
    public_ip_address_name=f"eeut-pip-{stackname}",
    sku=azure_native.network.PublicIPAddressSku(name="Standard", tier="Regional"),
    public_ip_allocation_method="Static",
    tags={"Name": f"eeut-{stackname}"},
)

network_interface = azure_native.network.NetworkInterface(
    "eeut-network-interface",
    resource_group_name=resource_group_name,
    network_interface_name=f"eeut-nic-{stackname}",
    ip_configurations=[
        azure_native.network.NetworkInterfaceIPConfigurationArgs(
            name="ipconfig1",
            subnet=azure_native.network.SubnetArgs(id=subnet.id),
            private_ip_allocation_method="Dynamic",
            public_ip_address=azure_native.network.PublicIPAddressArgs(id=public_ip.id),
        )
    ],
    network_security_group=azure_native.network.SubResourceArgs(id=network_security_group.id),
    tags={"Name": f"eeut-{stackname}"},
)

user_assigned_identity = azure_native.managedidentity.UserAssignedIdentity(
    "eeut-identity",
    resource_group_name=resource_group_name,
    resource_name=f"eeut-identity-{stackname}",
    tags={"Name": f"eeut-{stackname}"},
)

role_definition_id = (
    f"/subscriptions/{client_config.subscription_id}"
    "/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
)

key_vault = azure_native.keyvault.get_vault_output(
    resource_group_name=resource_group_name,
    vault_name=key_vault_name,
)

azure_native.authorization.RoleAssignment(
    "eeut-kv-access",
    role_assignment_name=str(uuid.uuid4()),
    principal_id=user_assigned_identity.principal_id,
    principal_type="ServicePrincipal",
    role_definition_id=role_definition_id,
    scope=key_vault.id,
)

custom_data = load_user_data_script().apply(
    lambda script: base64.b64encode(script.encode("utf-8")).decode("utf-8")
)

eeut_vm = azure_native.compute.VirtualMachine(
    "ee-cicd-vm",
    resource_group_name=resource_group_name,
    vm_name=f"eeut-{stackname}",
    hardware_profile=azure_native.compute.HardwareProfileArgs(vm_size=vm_size),
    network_profile=azure_native.compute.NetworkProfileArgs(
        network_interfaces=[azure_native.compute.NetworkInterfaceReferenceArgs(id=network_interface.id)]
    ),
    identity=azure_native.compute.VirtualMachineIdentityArgs(
        type="UserAssigned",
        user_assigned_identities={user_assigned_identity.id: {}},
    ),
    os_profile=azure_native.compute.OSProfileArgs(
        admin_username=admin_username,
        computer_name=f"eeut-{stackname}",
        custom_data=custom_data,
        linux_configuration=azure_native.compute.LinuxConfigurationArgs(
            disable_password_authentication=True,
            ssh=azure_native.compute.SshConfigurationArgs(
                public_keys=[
                    azure_native.compute.SshPublicKeyArgs(
                        path=f"/home/{admin_username}/.ssh/authorized_keys",
                        key_data=ssh_public_key,
                    )
                ]
            ),
        ),
    ),
    storage_profile=azure_native.compute.StorageProfileArgs(
        image_reference=azure_native.compute.ImageReferenceArgs(
            publisher=image_publisher,
            offer=image_offer,
            sku=image_sku,
            version=image_version,
        ),
        os_disk=azure_native.compute.OSDiskArgs(
            create_option="FromImage",
            managed_disk=azure_native.compute.ManagedDiskParametersArgs(storage_account_type="Premium_LRS"),
            disk_size_gb=128,
        ),
    ),
    tags={"Name": f"eeut-{stackname}"},
)

pulumi.export("eeut_vm_id", eeut_vm.id)
pulumi.export(
    "eeut_private_ip",
    network_interface.ip_configurations.apply(
        lambda configs: configs[0].private_ip_address if configs else None
    ),
)
pulumi.export("eeut_public_ip", public_ip.ip_address)
