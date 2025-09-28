"""Synchronize edge stream configuration into the Kubernetes ConfigMap used by the edge pods."""

# NOTE: The Helm chart ships a byte-for-byte copy of this script at
# deploy/helm/groundlight-edge-endpoint/files/edge-config-sync.py. Update both copies when
# making changes.

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass
class HTTPResult:
    status: int
    body: bytes


class SyncError(RuntimeError):
    pass


def _http_request(method: str, url: str, *, headers: Optional[dict] = None, data: Optional[bytes] = None, context: Optional[ssl.SSLContext] = None, timeout: float = 10.0) -> HTTPResult:
    req = Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urlopen(req, context=context, timeout=timeout) as resp:
            return HTTPResult(status=resp.getcode(), body=resp.read())
    except HTTPError as err:
        return HTTPResult(status=err.code, body=err.read())
    except URLError as err:  # pragma: no cover - network failure path
        raise SyncError(f"Failed to reach {url}: {err}") from err


def fetch_config(api_base: str, api_key: Optional[str], timeout: float = 10.0) -> dict:
    headers = {"Accept": "application/json"}
    if api_key:
        headers["X-IntelliOptics-Key"] = api_key
    result = _http_request("GET", api_base.rstrip("/") + "/config/export", headers=headers, timeout=timeout)
    if result.status != 200:
        raise SyncError(f"Cloud API returned {result.status}: {result.body!r}")
    try:
        return json.loads(result.body.decode("utf-8"))
    except json.JSONDecodeError as exc:  # pragma: no cover - unexpected
        raise SyncError("Unable to parse cloud API response") from exc


def _service_account_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }


def _kube_base_url(host: str, port: str) -> str:
    return f"https://{host}:{port}/api/v1"


def update_configmap(*, namespace: str, name: str, yaml_text: str, token: str, host: str, port: str, context: ssl.SSLContext, timeout: float = 10.0) -> None:
    base = _kube_base_url(host, port)
    patch_url = f"{base}/namespaces/{namespace}/configmaps/{name}"
    headers = _service_account_headers(token)
    headers["Content-Type"] = "application/merge-patch+json"
    payload = json.dumps({"data": {"edge-config.yaml": yaml_text}}).encode("utf-8")

    result = _http_request("PATCH", patch_url, headers=headers, data=payload, context=context, timeout=timeout)
    if result.status == 404:
        create_url = f"{base}/namespaces/{namespace}/configmaps"
        create_headers = _service_account_headers(token)
        create_headers["Content-Type"] = "application/json"
        manifest = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {"name": name, "namespace": namespace},
            "data": {"edge-config.yaml": yaml_text},
        }
        result = _http_request(
            "POST",
            create_url,
            headers=create_headers,
            data=json.dumps(manifest).encode("utf-8"),
            context=context,
            timeout=timeout,
        )
        if result.status not in {200, 201}:
            raise SyncError(f"Failed to create ConfigMap {name}: {result.status} {result.body!r}")
        return

    if result.status >= 400:
        raise SyncError(f"Failed to patch ConfigMap {name}: {result.status} {result.body!r}")


def restart_deployment(*, namespace: str, name: str, token: str, host: str, port: str, context: ssl.SSLContext, timeout: float = 10.0) -> None:
    base = f"https://{host}:{port}/apis/apps/v1"
    url = f"{base}/namespaces/{namespace}/deployments/{name}"
    headers = _service_account_headers(token)
    headers["Content-Type"] = "application/merge-patch+json"
    payload = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "intellioptics.com/edge-config-sync": str(int(time.time()))
                    }
                }
            }
        }
    }
    result = _http_request(
        "PATCH",
        url,
        headers=headers,
        data=json.dumps(payload).encode("utf-8"),
        context=context,
        timeout=timeout,
    )
    if result.status >= 400:
        raise SyncError(f"Failed to restart deployment {name}: {result.status} {result.body!r}")


def load_service_account_token(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except FileNotFoundError as exc:  # pragma: no cover - environment failure
        raise SyncError(f"Service account token missing at {path}") from exc


def build_ssl_context(ca_path: str | None, insecure: bool) -> ssl.SSLContext:
    if insecure:
        context = ssl._create_unverified_context()  # pragma: no cover - best-effort fallback
        return context
    context = ssl.create_default_context(cafile=ca_path)
    return context


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Synchronize edge stream configuration into Kubernetes")
    parser.add_argument("--api-base", required=True, help="Base URL for the config API, e.g. https://api.example.com/v1")
    parser.add_argument("--api-key", default=os.getenv("INTELLIOPTICS_API_KEY"), help="API key used to authenticate with the cloud backend")
    parser.add_argument("--namespace", default=os.getenv("KUBE_NAMESPACE", "intellioptics-edge"), help="Kubernetes namespace for the edge deployment")
    parser.add_argument("--configmap", default=os.getenv("EDGE_CONFIG_CONFIGMAP", "edge-config"), help="Name of the ConfigMap to update")
    parser.add_argument("--deployment", default=os.getenv("EDGE_DEPLOYMENT_NAME", "edge-endpoint"), help="Deployment to restart after syncing")
    parser.add_argument("--restart", action="store_true", help="Trigger a rolling restart of the edge deployment after updating the ConfigMap")
    parser.add_argument("--service-host", default=os.getenv("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc"), help="Kubernetes API host")
    parser.add_argument("--service-port", default=os.getenv("KUBERNETES_SERVICE_PORT", "443"), help="Kubernetes API port")
    parser.add_argument("--token-path", default=os.getenv("KUBE_TOKEN_PATH", "/var/run/secrets/kubernetes.io/serviceaccount/token"), help="Path to the service account token")
    parser.add_argument("--ca-path", default=os.getenv("KUBE_CA_PATH", "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"), help="Path to the Kubernetes CA certificate")
    parser.add_argument("--insecure-skip-tls-verify", action="store_true", help="Disable TLS verification when talking to the Kubernetes API (not recommended)")
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout in seconds")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    config = fetch_config(args.api_base, args.api_key, timeout=args.timeout)
    yaml_text = config.get("yaml")
    if not yaml_text:
        raise SyncError("Cloud API did not return any configuration payload")

    token = load_service_account_token(args.token_path)
    context = build_ssl_context(args.ca_path, args.insecure_skip_tls_verify)

    update_configmap(
        namespace=args.namespace,
        name=args.configmap,
        yaml_text=yaml_text,
        token=token,
        host=args.service_host,
        port=args.service_port,
        context=context,
        timeout=args.timeout,
    )

    if args.restart:
        restart_deployment(
            namespace=args.namespace,
            name=args.deployment,
            token=token,
            host=args.service_host,
            port=args.service_port,
            context=context,
            timeout=args.timeout,
        )

    print(f"Synced {config.get('stream_count', 0)} stream(s) to ConfigMap '{args.configmap}' in namespace '{args.namespace}'.")
    if args.restart:
        print(f"Triggered rollout restart for deployment '{args.deployment}'.")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entrypoint
    try:
        raise SystemExit(main())
    except SyncError as exc:
        print(f"edge-config-sync failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
