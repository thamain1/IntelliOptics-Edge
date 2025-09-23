"""
Fabric tools to connect to the EEUT and see how it's doing.
"""
from functools import lru_cache
from typing import Callable, Iterable
import os
import time
import io

from fabric import task, Connection
from invoke import run as local
from invoke.exceptions import UnexpectedExit
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import paramiko


@lru_cache(maxsize=None)
def get_secret_client() -> SecretClient:
    """Create an Azure Key Vault client using the default credential chain."""
    vault_url = os.environ.get("AZURE_KEY_VAULT_URL")
    if not vault_url:
        vault_name = os.environ.get("AZURE_KEY_VAULT_NAME")
        if not vault_name:
            raise RuntimeError(
                "Either AZURE_KEY_VAULT_URL or AZURE_KEY_VAULT_NAME must be set to access the EEUT SSH key."
            )
        vault_url = f"https://{vault_name}.vault.azure.net"
    credential = DefaultAzureCredential()
    return SecretClient(vault_url=vault_url, credential=credential)


def fetch_secret(secret_name: str) -> str:
    """Fetch a secret value from Azure Key Vault."""
    client = get_secret_client()
    secret = client.get_secret(secret_name)
    return secret.value


def _load_private_key(private_key: str) -> paramiko.PKey:
    """Attempt to deserialize the SSH private key using supported algorithms."""
    key_buffer = io.StringIO(private_key)
    for key_cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        key_buffer.seek(0)
        try:
            return key_cls.from_private_key(key_buffer)
        except paramiko.ssh_exception.SSHException:
            continue
    raise RuntimeError("Unable to parse SSH private key retrieved from Azure Key Vault.")


def _pulumi_outputs_to_try() -> Iterable[str]:
    """Return the Pulumi output names that might contain the EEUT IP address."""
    env_override = os.environ.get("EEUT_PULUMI_IP_OUTPUTS")
    if env_override:
        for name in env_override.split(","):
            cleaned = name.strip()
            if cleaned:
                yield cleaned
        return
    # Default order: prefer explicit overrides and fall back to historical names.
    yield from ("eeut_private_ip", "eeut_public_ip", "eeut_ip")

def get_eeut_ip() -> str:
    """Gets the EEUT's IP address from Pulumi or the environment."""
    ip_override = os.environ.get("EEUT_SSH_HOST")
    if ip_override:
        return ip_override

    for output_name in _pulumi_outputs_to_try():
        try:
            result = local(
                f"pulumi stack output {output_name}",
                hide=True,
                warn=True,
            )
        except UnexpectedExit:
            continue
        if result.ok and result.stdout.strip():
            return result.stdout.strip()
    raise RuntimeError(
        "Unable to determine EEUT IP address. Provide EEUT_SSH_HOST or ensure Pulumi exports one of: "
        + ", ".join(_pulumi_outputs_to_try())
    )

def connect_server() -> Connection:
    """Connects to the EEUT using the private key stored in Azure Key Vault."""
    ip = get_eeut_ip()
    secret_name = os.environ.get("EEUT_SSH_KEY_SECRET_NAME", "ghar2eeut-private-key")
    private_key = fetch_secret(secret_name)
    key = _load_private_key(private_key)
    user = os.environ.get("EEUT_SSH_USER", "ubuntu")
    conn = Connection(
        ip,
        user=user,
        connect_kwargs={"pkey": key},
    )
    conn.run(f"echo 'Successfully logged in to {ip}'")
    return conn


class InfrequentUpdater:
    """Displays messages as they happen, but don't repeat the same message too often."""

    def __init__(self, how_often: float = 30):
        self.how_often = how_often
        self.last_update = 0
        self.last_msg = ""

    def maybe_update(self, msg: str):
        """Displays a message if it's been long enough since the last message, and the same.
        New messages are always displayed."""
        if msg == self.last_msg:
            if time.time() - self.last_update < self.how_often:
                return
        print(msg)
        self.last_msg = msg
        self.last_update = time.time()

@task
def connect(c, patience: int = 30):
    """Just connect to a server to validate connection is working.

    Args:
        patience (int): Number of seconds to keep retrying for.
    """
    print("Fab/fabric is working.  Connecting to server...")
    updater = InfrequentUpdater()
    start_time = time.time()
    while time.time() - start_time < patience:
        try:
            connect_server()
            print("Successfully connected to server.")
            return
        except Exception as e:
            updater.maybe_update(f"Failed to connect to server: {e}")
            time.sleep(3)
    raise RuntimeError(f"Failed to connect to server after {patience} seconds.")


class StatusFileChecker(InfrequentUpdater):
    """Encapsulates all the logic for checking status files."""

    def __init__(self, conn: Connection, path: str):
        super().__init__()
        self.conn = conn
        self.path = path
        self.last_update = 0
        self.last_msg = ""

    def check_for_file(self, name: str) -> bool:
        """Checks if a file is present in the EEUT's install status directory."""
        with self.conn.cd(self.path):
            result = self.conn.run(f"test -f {name}", warn=True)
            return result.ok
    
    def which_status_file(self) -> str:
        """Returns the name of the status file if it exists, or None if it doesn't."""
        with self.conn.cd(self.path):
            if self.check_for_file("installing"):
                return "installing"
            if self.check_for_file("success"):
                return "success"
            if self.check_for_file("failed"):
                return "failed"
        return None

    def wait_for_any_status(self, wait_minutes: int = 10) -> str:
        """Waits for the EEUT to begin setup.  This is a brand new sleepy server
        rubbing its eyes and waking up.  Give it a bit to start doing something.
        """
        start_time = time.time()
        while time.time() - start_time < 60 * wait_minutes:
            try:
                status_file = self.which_status_file()
                self.maybe_update(f"Found status file: {status_file}")
                if status_file:
                    return status_file
            except Exception as e:
                self.maybe_update(f"Unable to check status file: {e}")
            time.sleep(2)
        raise RuntimeError(f"No status file found after {wait_minutes} minutes.")

    def wait_for_success(self, wait_minutes: int = 10) -> bool:
        """Waits for the EEUT to finish setup.  If it fails, prints the log."""
        start_time = time.time()
        while time.time() - start_time < 60 * wait_minutes:
            if self.check_for_file("success"):
                return True
            if self.check_for_file("failed"):
                print("EE installation failed.  Printing complete log...")
                self.conn.run("cat /var/log/cloud-init-output.log")
                raise RuntimeError("EE installation failed.")
            self.maybe_update(f"Waiting for success or failed status file to appear...")
            time.sleep(2)
        raise RuntimeError(f"EE installation check timed out after {wait_minutes} minutes.")

@task
def wait_for_ee_setup(c, wait_minutes: int = 10):
    """Waits for the EEUT to finish setup.  If it fails, prints the log."""
    conn = connect_server()
    checker = StatusFileChecker(conn, "/opt/intellioptics/ee-install-status")
    print("Waiting for any status file to appear...")
    checker.wait_for_any_status(wait_minutes=wait_minutes/2)
    print("Waiting for success status file to appear...")
    checker.wait_for_success(wait_minutes=wait_minutes)
    print("EE installation complete.")


def wait_for_condition(conn: Connection, condition: Callable[[Connection], bool], wait_minutes: int = 10) -> bool:
    """Waits for a condition to be true.  Returns True if the condition is true, False otherwise."""
    updater = InfrequentUpdater()
    start_time = time.time()
    name = condition.__name__
    while time.time() - start_time < 60 * wait_minutes:
        try:
            if condition(conn):
                print(f"Condition {name} is true.  Moving on.")
                return True
            else:
                updater.maybe_update(f"Condition {name} is false.  Still waiting...")
        except Exception as e:
            updater.maybe_update(f"Condition {name} failed: {e}.  Will retry...")
        time.sleep(2)
    print(f"Condition {name} timed out after {wait_minutes} minutes.")
    return False

@task
def check_k8_deployments(c):
    """Checks that the edge-endpoint deployment goes online.
    """
    conn = connect_server()
    def can_run_kubectl(conn: Connection) -> bool:  
        conn.run("kubectl get pods")  # If this works at all, we're happy
        return True
    if not wait_for_condition(conn, can_run_kubectl):
        raise RuntimeError("Failed to run kubectl.")
    def see_deployments(conn: Connection) -> bool:
        out = conn.run("kubectl get deployments", hide=True)
        # Need to see the edge-endpoint deployment  
        return "edge-endpoint" in out.stdout
    if not wait_for_condition(conn, see_deployments):
        conn.run("kubectl get all -A", hide=True)
        raise RuntimeError("Failed to see edge-endpoint deployment.")
    def edge_endpoint_ready(conn: Connection) -> bool:
        out = conn.run("kubectl get deployments edge-endpoint", hide=True)
        return "1/1" in out.stdout
    if not wait_for_condition(conn, edge_endpoint_ready):
        conn.run("kubectl get deployments edge-endpoint -o yaml")
        conn.run("kubectl describe deployments edge-endpoint")
        conn.run("kubectl logs deployment/edge-endpoint")
        raise RuntimeError("Failed to see edge-endpoint deployment ready.")

@task 
def check_server_port(c):
    """Checks that the server is listening on the service port."""
    # First check that it's visible from the EEUT's localhost
    conn = connect_server()
    print(f"Checking that the server is listening on port 30101 from the EEUT's localhost...")
    conn.run("nc -zv localhost 30101")

    print(f"Checking that the server is reachable from here...")
    eeut_ip = get_eeut_ip()
    local(f"nc -zv {eeut_ip} 30101")

    print("Server port check complete.")


@task
def full_check(c):
    """Runs all the checks in order."""
    connect(c)
    wait_for_ee_setup(c)
    check_k8_deployments(c)
    check_server_port(c)


@task
def shutdown_instance(c):
    """Shuts down the EEUT instance."""
    conn = connect_server()
    # Tell it to shutdown in 2 minutes, so it doesn't die while we're still connected.
    conn.run("sudo shutdown +2")
    print("Instance will shutdown in 2 minutes.  Disconnecting...")
