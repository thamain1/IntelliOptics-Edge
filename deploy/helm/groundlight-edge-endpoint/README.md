# Install IntelliOptics Edge Endpoint in your Cluster

This Helm chart deploys IntelliOptics Edge Endpoint on a Kubernetes cluster using the Helm package manager.

For details on the IntelliOptics Edge Endpoint, please visit the [GitHub project page](https://github.com/IntelliOptics/edge-endpoint).

## Container registry configuration

The chart now supports both AWS Elastic Container Registry (ECR) and Azure Container Registry (ACR) for pulling container images. The
`values.yaml` file exposes a new `registry` block that lets you choose the registry provider and supply any provider-specific settings.

```yaml
registry:
  provider: aws | azure
  server: <registry login server>
  username: <optional static username>
  passwordCommand: <optional command to emit a registry password/token>
  secretName: registry-credentials
  secretType: kubernetes.io/dockerconfigjson
  aws:
    region: us-west-2
  azure:
    registryName: myregistry
    loginMode: service-principal | managed-identity
    tenantId: <AAD tenant id>
    clientId: <service principal app id>
    clientSecret: <service principal secret>
    managedIdentityClientId: <optional user-assigned identity id>
```

When `provider` is set to `azure`, the registry refresh jobs will log in using the configured Azure credentials and continuously
refresh the Kubernetes pull secret. For AWS you can continue using the default behaviour (short-lived ECR credentials provided by the
IntelliOptics control plane) or override `passwordCommand` if you want to supply credentials from another source.

