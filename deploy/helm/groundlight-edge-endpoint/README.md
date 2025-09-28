# Install IntelliOptics Edge Endpoint in your Cluster

This Helm chart deploys IntelliOptics Edge Endpoint on a Kubernetes cluster using the Helm package manager.

For details on the IntelliOptics Edge Endpoint, please visit the [GitHub project page](https://github.com/IntelliOptics/edge-endpoint).

## Container registry configuration

The chart retrieves short-lived credentials for the container registry and stores them in the
`registry-credentials` secret. Registry behaviour is controlled by the `registry` block in
`values.yaml`:

```yaml
registry:
  provider: aws
  server: "767397850842.dkr.ecr.us-west-2.amazonaws.com"
  azure:
    registryName: ""
```

* **AWS (default):** Leave the defaults in place to pull from the IntelliOptics Amazon ECR registry.
* **Azure Container Registry:** Set `registry.provider` to `azure` and populate
  `registry.azure.registryName` with the ACR name (for example, `myregistry`). Azure users can omit
  `registry.server`; when it is blank the Helm job derives the proper hostname (e.g.,
  `myregistry.azurecr.io`) from the `az acr login` response before generating the Kubernetes pull
  secret.

