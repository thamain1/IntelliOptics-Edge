# Install IntelliOptics Edge Endpoint in your Cluster

This Helm chart deploys IntelliOptics Edge Endpoint on a Kubernetes cluster using the Helm package manager.

For details on the IntelliOptics Edge Endpoint, please visit the [GitHub project page](https://github.com/IntelliOptics/edge-endpoint).

## Prerequisites

* Create a docker-registry secret that Kubernetes can use to pull the edge endpoint images. By default the chart looks for a secret named `registry-credentials`, but you can override this via `registryCredentialsSecretName` in `values.yaml`.
* (Optional) Create a secret containing credentials for synchronising inference models. Set `modelSyncCredentialsSecretName` to the name of a secret with a key called `credentials`; its contents are mounted at `/root/.aws` for the inference bootstrap containers.

