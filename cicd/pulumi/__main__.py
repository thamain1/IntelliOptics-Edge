import base64
import subprocess

import pulumi
from pulumi import Output
from pulumi_azure_native import compute, network, resources

config = pulumi.Config("ee-cicd")
stackname = pulumi.get_stack()

location = config.get("location") or "westus2"
vm_size = config.require("vmSize")
admin_username = config.get("adminUsername") or "ubuntu"
ssh_public_key = config.require_secret("sshPublicKey")
resource_group_name = config.get("resourceGroupName") or f"eeut-{stackname}-rg"
address_space = config.get("addressSpace") or "10.30.0.0/16"
subnet_prefix = config.get("subnetPrefix") or "10.30.1.0/24"


def sanitize_name(name: str) -> str:
    return name.replace("_", "-")


resource_group = resources.ResourceGroup(
    "eeut-resource-group",
    resource_group_name=sanitize_name(resource_group_name),
    location=location,
)


def get_target_commit() -> str:
    target_commit = config.require("targetCommit")
    if target_commit == "main":
        target_commit = (
            subprocess.check_output(["git", "rev-parse", "HEAD"]).decode("utf-8").strip()
        )
    print(f"Using target commit {target_commit}")
    return target_commit


def load_user_data_script() -> Output[str]:
    with open("../bin/install-on-ubuntu.sh", "r", encoding="utf-8") as file:
        user_data_script0 = file.read()

    target_commit = get_target_commit()
    user_data_script1 = user_data_script0.replace("__EE_COMMIT_HASH__", target_commit)

    image_tag = config.get("eeImageTag") or "release"
    user_data_script2 = user_data_script1.replace("__EEIMAGETAG__", image_tag)

    api_token = config.require_secret("groundlightApiToken")

    return api_token.apply(
        lambda token: base64.b64encode(
            user_data_script2.replace("__GROUNDLIGHTAPITOKEN__", token).encode("utf-8")
        ).decode("utf-8")
    )


network_security_group = network.NetworkSecurityGroup(
    "eeut-nsg",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    security_rules=[
        network.SecurityRuleArgs(
            name="AllowSSH",
            access="Allow",
            direction="Inbound",
            priority=1001,
            protocol="Tcp",
            source_port_range="*",
            destination_port_range="22",
            source_address_prefix="*",
            destination_address_prefix="*",
        ),
    ],
)

virtual_network = network.VirtualNetwork(
    "eeut-vnet",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    address_space=network.AddressSpaceArgs(address_prefixes=[address_space]),
)

subnet = network.Subnet(
    "eeut-subnet",
    resource_group_name=resource_group.name,
    virtual_network_name=virtual_network.name,
    address_prefixes=[subnet_prefix],
    network_security_group=network.SubnetNetworkSecurityGroupArgs(id=network_security_group.id),
)

public_ip = network.PublicIPAddress(
    "eeut-public-ip",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    public_ip_allocation_method="Dynamic",
    sku=network.PublicIPAddressSkuArgs(name="Standard"),
)

network_interface = network.NetworkInterface(
    "eeut-nic",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    ip_configurations=[
        network.NetworkInterfaceIPConfigurationArgs(
            name="internal",
            subnet=network.SubnetArgs(id=subnet.id),
            private_ip_allocation_method="Dynamic",
            public_ip_address=network.PublicIPAddressArgs(id=public_ip.id),
        )
    ],
    network_security_group=network.SecurityGroupArgs(id=network_security_group.id),
)

custom_data = load_user_data_script()

ssh_public_keys = ssh_public_key.apply(
    lambda key: [
        compute.SshPublicKeyArgs(
            path=f"/home/{admin_username}/.ssh/authorized_keys",
            key_data=key,
        )
    ]
)

virtual_machine = compute.VirtualMachine(
    "eeut-vm",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    network_profile=compute.NetworkProfileArgs(
        network_interfaces=[
            compute.NetworkInterfaceReferenceArgs(
                id=network_interface.id,
                primary=True,
            )
        ]
    ),
    hardware_profile=compute.HardwareProfileArgs(vm_size=vm_size),
    storage_profile=compute.StorageProfileArgs(
        os_disk=compute.OSDiskArgs(
            name=f"eeut-{sanitize_name(stackname)}-osdisk",
            caching="ReadWrite",
            create_option="FromImage",
            disk_size_gb=100,
            managed_disk=compute.ManagedDiskParametersArgs(
                storage_account_type="Premium_LRS",
            ),
        ),
        image_reference=compute.ImageReferenceArgs(
            publisher="Canonical",
            offer="0001-com-ubuntu-server-jammy",
            sku="22_04-lts-gen2",
            version="latest",
        ),
    ),
    os_profile=compute.OSProfileArgs(
        computer_name=f"eeut-{sanitize_name(stackname)}",
        admin_username=admin_username,
        linux_configuration=compute.LinuxConfigurationArgs(
            disable_password_authentication=True,
            ssh=compute.SshConfigurationArgs(public_keys=ssh_public_keys),
        ),
        custom_data=custom_data,
    ),
    tags={
        "Name": f"eeut-{stackname}",
    },
)

pulumi.export("resource_group_name", resource_group.name)
pulumi.export("eeut_vm_id", virtual_machine.id)
pulumi.export(
    "eeut_private_ip",
    network_interface.ip_configurations.apply(lambda configs: configs[0].private_ip_address),
)
pulumi.export("eeut_public_ip", public_ip.ip_address)
