# Setting up the Edge Endpoint

The edge endpoint runs under Kubernetes, typically on a single-node cluster, which could be just a raspberry pi, or a powerful GPU server.  If you have a lot of detectors, it will scale out to a large multi-node cluster as well with zero changes except to the Kubernetes cluster setup. 

The instructions below are fairly opinionated, optimized for single-node cluster setup, using k3s, on an Ubuntu/Debian-based system.  If you want to set it up with a different flavor of kubernetes, that should work. Take the instructions below as a starting point and adjust as needed.

## Instructions for setting up a single-node Edge Endpoint

These are the steps to set up a single-node Edge Endpoint:

1. [Set up a local Kubernetes cluster with k3s](#setting-up-single-node-kubernetes-with-k3s).
2. [Set your IntelliOptics API token](#set-the-IntelliOptics-api-token).
3. [Set up to use the Helm package manager](#setting-up-for-helm).
4. [Install the Edge Endpoint with Helm](#installing-the-edge-endpoint-with-helm).
5. [Confirm that the Edge Endpoint is running](#verifying-the-installation).

If you follow these instructions and something isn't working, please check the [troubleshooting section](#troubleshooting-deployments) for help.

## Cloud and Container Registry Prerequisites

The Edge Endpoint containers are published to both AWS Elastic Container Registry (ECR) and Azure Container Registry (ACR). You
only need to configure the cloud provider that matches the infrastructure you are running on, but it is helpful to understand
what each provider requires before you start the Helm install. This section collects the environment variables, CLI tooling, and
registry authentication steps that are referenced throughout the rest of the document.

### Azure requirements (ACR and AKS/AKS Edge Essentials)

1. Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) on the host where you will run the Helm
   commands.
2. Sign in and select the subscription that owns your container registry and cluster:

   ```bash
   az login
   az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
   ```

3. Define the basic Azure environment variables that will be reused later:

   ```bash
   export AZURE_SUBSCRIPTION_ID="<subscription-guid>"
   export AZURE_RESOURCE_GROUP="<resource-group-for-aks>"
   export ACR_NAME="<your-acr-name>"
   export ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
   export ACR_PULL_SECRET_NAME="registry-credentials"
   ```

4. Authenticate to your container registry. For long-lived clusters we recommend using the
   [token-based login](https://learn.microsoft.com/azure/container-registry/container-registry-authentication) so that AKS can
   refresh the credentials without storing your personal Azure password.

   ```bash
   # Option A: use an admin-enabled account (good for quick tests)
   az acr login --name "$ACR_NAME"

   # Option B: generate a token for kubernetes secrets (preferred for production)
   export ACR_PULL_USERNAME="00000000-0000-0000-0000-000000000000"
   export ACR_PULL_PASSWORD="$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)"
   ```

5. Make the credentials available to Kubernetes. You can create a pull secret directly or reference the rendered YAML that ships
   with this repository.

   ```bash
   kubectl create secret docker-registry "$ACR_PULL_SECRET_NAME" \
     --namespace edge \
     --docker-server="$ACR_LOGIN_SERVER" \
     --docker-username="$ACR_PULL_USERNAME" \
     --docker-password="$ACR_PULL_PASSWORD"
   ```

   If you prefer to template the secret as part of a GitOps workflow, see the sample manifest in
   [`deploy/aci/edge-endpoint.yaml`](aci/edge-endpoint.yaml) for how `imageRegistryCredentials` are provided to Azure Container
   Instances and adapt it for your AKS cluster.

6. (Optional) Connect kubectl to an AKS cluster or to an Azure Kubernetes Service Edge Essentials node:

   ```bash
   az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "<aks-cluster-name>"
   ```

With those steps complete, Helm will be able to pull images from ACR using the default repositories embedded in the chart
templates at [`helm/groundlight-edge-endpoint/templates`](helm/groundlight-edge-endpoint/templates). If you maintain your
own ACR image tags, override the `edgeEndpointTag` and `inferenceTag` values in
[`helm/groundlight-edge-endpoint/values.yaml`](helm/groundlight-edge-endpoint/values.yaml) when you run Helm.

### AWS requirements (ECR and EKS/other Kubernetes distributions)

The legacy scripts and several troubleshooting steps still reference AWS because that was the first production environment.
Install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and configure credentials
that can pull from ECR:

### TL;DR - No fluff, just bash commands

This is the quick version of the instructions above.  On a fresh system with no other customization, you can run the following commands to set up the Edge Endpoint.

Before starting, get a IntelliOptics API token from the IntelliOptics web app and set it as an environment variable:

```shell
export INTELLIOPTICS_API_TOKEN="api_xxxxxx"
```

Then, run the following commands to set up the Edge Endpoint:

For GPU-based systems:

```shell
curl -fsSL https://raw.githubusercontent.com/IntelliOptics/edge-endpoint/refs/heads/main/deploy/bin/install-k3s.sh | bash -s gpu
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}"
```

For CPU-based systems:

```shell
curl -fsSL https://raw.githubusercontent.com/IntelliOptics/edge-endpoint/refs/heads/main/deploy/bin/install-k3s.sh | bash -s cpu
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" \
  --set inferenceFlavor=cpu
```

For Jetson Orin-based systems (experimental):

```shell
curl -fsSL https://raw.githubusercontent.com/IntelliOptics/edge-endpoint/refs/heads/main/deploy/bin/install-k3s.sh | bash -s jetson
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" \
  --set inferenceTag="jetson"
```

You're done. You can skip down to [Verifying the Installation](#verifying-the-installation) to confirm that the Edge Endpoint is running.

### Azure prerequisites and registry setup

If you're deploying the Edge Endpoint into Azure Kubernetes Service (AKS) or another Kubernetes cluster that only has access to Azure Container Registry (ACR), complete the following steps before running Helm:

1. **Install the Azure CLI.** Follow the [official installation guide](https://learn.microsoft.com/cli/azure/install-azure-cli) for your platform. The commands below assume the `az` CLI is available on your `PATH`.
2. **Authenticate with Azure.**
   ```shell
   az login                      # Opens browser or device code auth
   az account set --subscription "<your-subscription-id>"
   ```
3. **Configure registry environment variables.** The sample [`.env.example`](../.env.example) lists the commonly used values.
   ```shell
   export ACR_LOGIN_SERVER="acrintellioptics.azurecr.io"  # or your registry FQDN
   export ACR_NAME="acrintellioptics"                     # registry name without domain
   ```
   When you need admin credentials for scripting (for example, to create the Kubernetes pull secret), capture them with:
   ```shell
   export ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv)
   export ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)
   ```
4. **Log Docker into ACR so you can push images.**
   ```shell
   az acr login --name "$ACR_NAME"
   ```
5. **Create or refresh the Kubernetes image pull secret.** If you're running in AKS, first merge credentials with your local kubeconfig (`az aks get-credentials`). Then create the secret that the Helm chart expects (`registry-credentials`):
   ```shell
   kubectl create secret docker-registry registry-credentials \
     --namespace edge \
     --docker-server "$ACR_LOGIN_SERVER" \
     --docker-username "$ACR_USERNAME" \
     --docker-password "$ACR_PASSWORD"
   ```
   The same secret is referenced by [deploy/aci/edge-endpoint.yaml](aci/edge-endpoint.yaml) when running the Edge Endpoint in Azure Container Instances, and by the Helm chart values in [deploy/helm/groundlight-edge-endpoint/values.yaml](helm/groundlight-edge-endpoint/values.yaml).

#### Smoke check: verify the Azure pull secret

After the Helm jobs run (or after you manually refresh the credentials), confirm that the generated `registry-credentials` secret points at your Azure Container Registry. The following commands print the registry server and username embedded in the secret; the server should end with `.azurecr.io`, and the username should match the value returned by `az acr login --expose-token`:

```shell
NAMESPACE=edge   # replace with the namespace used by the chart
kubectl get secret registry-credentials \
  --namespace "$NAMESPACE" \
  --output jsonpath='{.data.\.dockerconfigjson}' | \
  base64 --decode | jq '.auths | to_entries[] | {server: .key, username: .value.username}'
```

If the server is not your Azure registry or the username is missing, rerun the credential job (`kubectl create job --from=cronjob/refresh-acr-creds manual-refresh`), check the logs for the `init-aws-access-retrieve` container, and ensure the `az acr login --expose-token` call is succeeding with the expected service principal.
6. **Push updated images to ACR (optional).** When you need to publish a local image build directly to your registry, tag it with the fully-qualified login server and push:
   ```shell
   docker build -t "$ACR_LOGIN_SERVER/intellioptics/edge-endpoint:local" .
   docker push "$ACR_LOGIN_SERVER/intellioptics/edge-endpoint:local"
   ```
   The Azure one-click provisioning scripts in [infra/azure-oneclick/deploy](../infra/azure-oneclick/deploy) show complete examples of using `az acr login` before pushing and of injecting the resulting tag into downstream workloads.

After these prerequisites are in place you can follow the Helm instructions below without needing any AWS credentials. If your cluster also needs to pull from AWS Elastic Container Registry (ECR), continue to manage those credentials alongside the Azure secret.

## Configuring RTSP streaming ingest

The edge endpoint now supports continuously sampling RTSP or GStreamer camera feeds and piping those frames through the existing `/device-api/v1/image-queries` pipeline. The ingest workers run inside the main `edge-endpoint` container so that the same detector configuration, escalation rules, and metrics tracking are reused.

1. **Describe streams in `edge-config.yaml`.** Add a `streams` section that identifies the detector, RTSP URL, sampling cadence, and any credentials. The example below demonstrates capturing a frame every two seconds and submitting it directly to the edge inference stack.

   ```yaml
   streams:
     - name: packaging_line_cam
       detector_id: "det_123456"
       url: "rtsp://192.0.2.10/stream1"
       sampling_interval_seconds: 2.0
       reconnect_delay_seconds: 5.0
       backend: "auto"          # or "gstreamer" when providing a pipeline string
       encoding: "jpeg"         # or "png" when lossless captures are required
       submission_method: "edge"  # use "api" to POST through /device-api/v1/image-queries
       api_token_env: "INTELLIOPTICS_API_TOKEN"  # only needed when submission_method=api
       credentials:
         username_env: "CAM1_USERNAME"
         password_env: "CAM1_PASSWORD"
   ```

   Credentials can be provided inline for quick tests, but we recommend referencing environment variables so Kubernetes secrets can be injected without editing the config file.

2. **Expose credentials and multimedia libraries via Helm values.** Enable the helper stanza in `values.yaml` so that the deployment renders the required environment variables or host-mounted libraries. The following snippet injects RTSP credentials from a secret and mounts a host path that contains GStreamer plugins:

   ```yaml
   streaming:
     enabled: true
     secretEnvs:
       - name: CAM1_USERNAME
         secretName: camera1-rtsp
         secretKey: username
       - name: CAM1_PASSWORD
         secretName: camera1-rtsp
         secretKey: password
         optional: false
     extraVolumes:
       gstreamer-libs:
         hostPath:
           path: /usr/lib/aarch64-linux-gnu/gstreamer-1.0
     extraVolumeMounts:
       - name: gstreamer-libs
         mountPath: /usr/lib/aarch64-linux-gnu/gstreamer-1.0
   ```

   When the `streaming.enabled` flag is set, the chart automatically expands the environment variables and volume mounts for the main container so OpenCV can authenticate to cameras and locate the required multimedia codecs. Additional variables can be surfaced through `streaming.extraEnv` for non-secret configuration (for example, custom RTSP options or alternate `/image-queries` endpoints).

3. **Verify ingest at runtime.** Once the pod restarts, the application log should include messages such as `Starting RTSP ingest for stream 'packaging_line_cam' targeting detector 'det_123456'`. Any reconnect attempts or inference failures are logged with the stream name, making it easier to monitor camera health alongside the existing detector metrics.

If RTSP ingest is not required, omit the `streams` section—the worker is idle by default. Multiple streams can be defined, and each one runs in its own asyncio task so a slow or disconnected camera does not block the others.

### Managing streams from the cloud console

The edge endpoint can now source its RTSP configuration from the cloud backend. The FastAPI service exposes authenticated endpoints at `/v1/config/...` that allow operators to list detectors, add or update stream definitions, and export an updated `edge-config.yaml`. A lightweight web console is available at `/config/streams` that layers validation on top of the `StreamConfig` model—use it to enter stream URLs, credentials, cadence, and detector bindings without editing YAML by hand.

1. Sign in to the cloud API and open `/config/streams`. Use the “Add Stream” form to create or edit stream definitions. All changes are persisted in the backend database and can also be retrieved programmatically via `GET /v1/config/streams` or `GET /v1/config/streams/{name}`.
2. Deploy the optional `configSync` CronJob (see [Helm values](#helm-chart) below) so that cloud updates are written back into the edge cluster’s `edge-config` ConfigMap. The job runs the shared `edge_config_sync.py` client, which calls `/v1/config/export` to obtain the current YAML, patches the ConfigMap, and optionally restarts the edge deployment so the new settings take effect.
3. When `AppState.load_edge_config` notices the ConfigMap change, the ingest worker will hot-reload the new stream definitions (or restart if required by your deployment strategy).

Refer to [docs/cloud-stream-workflow.md](../docs/cloud-stream-workflow.md) for a deeper dive into the end-to-end workflow and automation hooks.

This workflow keeps the canonical configuration in the cloud service while ensuring that edge pods stay in sync.

### Setting up Single-Node Kubernetes with k3s

If you don't have [k3s](https://docs.k3s.io/) installed, there is a script which can install it depending on whether you have a NVidia GPU or not.  If you don't set up a GPU, the models will run on the CPU, but be somewhat slower.

```shell
# For GPU inference
curl -fsSL -O https://raw.githubusercontent.com/IntelliOptics/edge-endpoint/refs/heads/main/deploy/bin/install-k3s.sh 
bash ./install-k3s.sh gpu
```

```shell
# For CPU inference
curl -fsSL -O https://raw.githubusercontent.com/IntelliOptics/edge-endpoint/refs/heads/main/deploy/bin/install-k3s.sh 
bash ./install-k3s.sh cpu
```

This script will install the k3s Kubernetes distribution on your machine.  If you use the `gpu` argument, the script will also install the  NVIDIA GPU plugin for Kubernetes. It will also install the [Helm](https://helm.sh) package manager, which is used to deploy the edge-endpoint, and the Linux utilities `curl` and `jq`, if you don't already have them.

### Set the IntelliOptics API Token

To enable the Edge Endpoint to communicate with the IntelliOptics service, you need to get an
IntelliOptics API token. Visit [the Azure-hosted API token portal](https://intelliopticsweb37558.z13.web.core.windows.net/reef/my-account/api-tokens) to create a token and set it as an environment variable. The token management experience now lives on Azure, so update any saved bookmarks accordingly.

```shell
export INTELLIOPTICS_API_TOKEN="api_xxxxxx"
```

> [!NOTE]
> Your IntelliOptics account needs to be enabled to support the Edge Endpoint. If you don't have 
> access to the Edge Endpoint, please contact IntelliOptics support (support@IntelliOptics.ai).

### Setting up for Helm

[Helm](https://helm.sh/) is a package manager for Kubernetes. IntelliOptics distributes the edge endpoint via a "Helm Chart."

If you've just installed k3s with the setup script above, you should have Helm installed and the edge-endpoint chart repository added. In this case, you can skip to step 3.  

If you're setting up Helm on a machine that already has k3s (or another Kubernetes environment) installed, do all three steps to get started.

####  Step 1: Install Helm

Run the Helm install script (as described [here](https://helm.sh/docs/intro/install/)):

```shell
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
bash /tmp/get_helm.sh
```


#### Step 2: Add the IntelliOptics Helm repository
```
helm repo add edge-endpoint https://code.IntelliOptics.ai/edge-endpoint/
helm repo update
```

#### Step 3: Point Helm to the k3s cluster

If you installed k3s with the script above, it should have created a kubeconfig file in `/etc/rancher/k3s/k3s.yaml`.  This is the file that Helm will use to connect to your k3s cluster.

If you're running with k3s and you haven't created a kubeconfig file in your home directory, you need to tell Helm to use the one that k3s created.  You can do this by setting the `KUBECONFIG` environment variable:

```shell 
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

You probably want to set this in your `.bashrc` or `.zshrc` file so you don't have to set it every time you open a new terminal.


### Installing the Edge Endpoint with Helm

For a simple, default installation, you can run the following command:

```shell
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}"
```

This will install the Edge Endpoint doing GPU-based inference in the `intellioptics-edge` namespace in your k3s cluster and expose it on port 30101 on your local node. Helm will keep a history of the installation in the `default` namespace (signified by the `-n default` flag).

To change values that you've customized after you've installed the Edge Endpoint or to install an updated chart, use the `helm upgrade` command. For example, to change the `intelliopticsApiToken` value, you can run:

```shell
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="<new IntelliOptics api token>"
```

#### Variation: Custom Edge Endpoint Configuration

You might want to customize the edge config file to include the detector ID's you want to run. See [the guide to configuring detectors](/CONFIGURING-DETECTORS.md) for more information. Adding detector ID's to the config file will cause inference pods to be initialized automatically for each detector and provides you finer-grained control over each detector's behavior. Even if detectors aren't configured in the config file, edge inference will be set up for each detector ID for which the IntelliOptics service receives requests (note that it takes some time for each inference pod to become available for the first time).

You can find an example edge config file here: [edge-config.yaml](https://github.com/IntelliOptics/edge-endpoint/blob/clone-free-install/configs/edge-config.yaml). The easiest path is to download that file and modify it to your needs.

To use a custom edge config file, set the `configFile` Helm value to the path of the file:

```shell
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" --set-file configFile=/path/to/your/edge-config.yaml
```
#### Variation: CPU Mode Inference

If the system you're running on doesn't have a GPU, you can run the Edge Endpoint in CPU mode. To do this, set the `inferenceFlavor` Helm value to `cpu`:

```shell
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" \
  --set inferenceFlavor=cpu
```

#### Variation: Synchronize streams from the cloud API

Enable the `configSync` CronJob to keep the edge ConfigMap aligned with the stream definitions managed in the cloud console. The job mounts the `edge_config_sync.py` client and requires a service account with permission to patch ConfigMaps and (optionally) restart the edge deployment.

```shell
helm upgrade -i -n intellioptics-edge edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" \
  --set configSync.enabled=true \
  --set configSync.apiBase="https://your-cloud-api.example.com/v1" \
  --set configSync.apiKeySecretName="cloud-api-key" \
  --set configSync.configMapName="edge-config" \
  --set configSync.restartAfterSync=true
```

* `configSync.apiBase` must point to the `/v1` base path exposed by the cloud FastAPI deployment.
* `configSync.apiKeySecretName` and `configSync.apiKeySecretKey` identify the secret that stores the API key required by the `/v1/config` endpoints. If the cloud API is unsecured in your environment, omit these values.
* Use `configSync.deploymentName` when the edge deployment uses a non-default name.
* Additional environment variables can be passed to the job with `configSync.extraEnv`.

#### Variation: Further Customization

The Helm chart supports various configuration options which can be set using `--set` flags. For the full list, with default values and documentation, see the [values.yaml](helm/IntelliOptics-edge-endpoint/values.yaml) file.

If you want to customize a number of values, you can create a `values.yaml` file with your custom values and pass it to Helm:

```shell
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint -f /path/to/your/values.yaml
```

### Verifying the Installation

After installation, verify your pods are running:

```bash
kubectl get pods -n intellioptics-edge
```

You should see output similar to:

```
NAME                             READY   STATUS    RESTARTS   AGE
edge-endpoint-6d7b9c4b59-wdp8f   2/2     Running   0          2m
```

Now you can access the Edge Endpoint at `http://localhost:30101`. For use with the IntelliOptics SDK, you can set the `INTELLIOPTICS_ENDPOINT` environment variable to `http://localhost:30101`.

### Uninstalling Edge Endpoint

To remove the Edge Endpoint deployed with Helm:

```bash
helm uninstall -n default edge-endpoint
```

## Legacy Instructions

> [!NOTE]
> The older setup mechanism with `setup-ee.sh` is still available, but we recommend using Helm for
> new installations and converting existing installations to Helm when possible. See the section
> [Converting from setup-ee.sh to Helm](#converting-from-setup-eesh-to-helm) for instructions on
> how to do this.

If you haven't yet installed the k3s Kubernetes distribution, follow the steps in the [Setting up Single-Node Kubernetes with k3s](#setting-up-single-node-kubernetes-with-k3s) section.

You might want to customize the [edge config file](../configs/edge-config.yaml) to include the detector ID's you want to run. See [the guide to configuring detectors](/CONFIGURING-DETECTORS.md) for more information. Adding detector ID's to the config file will cause inference pods to be initialized automatically for each detector and provides you finer-grained control over each detector's behavior. Even if detectors aren't configured in the config file, edge inference will be set up for each detector ID for which the IntelliOptics service receives requests (note that it takes some time for each inference pod to become available for the first time).

Before installing the edge-endpoint, you need to create/specify the namespace for the deployment. If you're creating a new one, run:

```bash
kubectl create namespace "your-namespace-name"
```

Whether you created a new namespace or are using an existing one, set the DEPLOYMENT_NAMESPACE environment variable:
```bash
export DEPLOYMENT_NAMESPACE="your-namespace-name"
```

Some other environment variables should also be set. You'll need to have created
an IntelliOptics API token in the [Azure-hosted IntelliOptics portal](https://intelliopticsweb37558.z13.web.core.windows.net/reef/my-account/api-tokens). The token portal now lives on Azure, so double-check that any saved instructions reference the new location.
```bash
# Set your API token
export INTELLIOPTICS_API_TOKEN="api_xxxxxx"

# Choose an inference flavor, either CPU or (default) GPU.
# Note that appropriate setup for GPU will need to be done separately.
export INFERENCE_FLAVOR="CPU"
# OR
export INFERENCE_FLAVOR="GPU"
```
You'll also need to authenticate Docker with the container registry that hosts the edge-endpoint image. The helper scripts expect the registry host to be provided via `REGISTRY_SERVER` and, optionally, a namespace via `REGISTRY_NAMESPACE`. When using GitHub Container Registry, for example, you can create a Personal Access Token with the `write:packages` scope and run:

```bash
export REGISTRY_SERVER=ghcr.io
export REGISTRY_NAMESPACE=intellioptics
export REGISTRY_USERNAME=<your-github-username>
export REGISTRY_PASSWORD=<github-personal-access-token>
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_SERVER" --username "$REGISTRY_USERNAME" --password-stdin
```

If your registry is already configured locally (for example via a credential helper), you can omit `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` and simply ensure `docker login` has been run beforehand.


You'll also need to authenticate with Azure so Docker can pull images from the appropriate Azure Container Registry (ACR) location. Make sure the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) is installed and that you've run `az login` (and, if required, `az account set --subscription <subscription-id>`) prior to running the deployment scripts.

You must also provide Azure credentials with permission to query the IntelliOptics Azure Container Registry. Export the following variables for a service principal that can read the registry (and associated storage) before running the setup script:

```bash
export AZURE_CLIENT_ID="<service-principal-client-id>"
export AZURE_CLIENT_SECRET="<service-principal-secret>"
export AZURE_TENANT_ID="<azure-tenant-id>"
```

If your service principal should target a non-default registry, you can optionally set:

```bash
export ACR_NAME="customRegistryName"
export ACR_LOGIN_SERVER="customRegistryName.azurecr.io"
```




You'll also need Azure credentials with permission to pull images from your Azure Container Registry (ACR). Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) if it is not already available on the node. For interactive environments you can authenticate with:

```bash
az login
az acr login --name <your-acr-name>
```

For unattended clusters, create a service principal that has the `acrpull` role on the registry and store those credentials so Kubernetes can refresh them:

```bash
ACR_NAME=<your-acr-name>
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)
az ad sp create-for-rbac \
  --name edge-endpoint-pull \
  --role acrpull \
  --scopes "$ACR_ID"

# Capture the output values
export ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
export ACR_USERNAME=<service-principal-appId>
export ACR_PASSWORD=<service-principal-password>

kubectl create secret docker-registry registry-credentials \
  --docker-server="${ACR_LOGIN_SERVER}" \
  --docker-username="${ACR_USERNAME}" \
  --docker-password="${ACR_PASSWORD}"
```

If your deployment needs to upload artifacts to Azure Storage (for example, alert snapshots or detector logs), make sure `AZURE_STORAGE_CONNECTION_STRING` is set for the helm release or provided via a Kubernetes secret:

```bash
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=..."
```


You'll also need Azure credentials with permission to pull images from your Azure Container Registry (ACR). Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) if it is not already available on the node. For interactive environments you can authenticate with:

```bash
az login
az acr login --name <your-acr-name>
```

For unattended clusters, create a service principal that has the `acrpull` role on the registry and store those credentials so Kubernetes can refresh them:

```bash
ACR_NAME=<your-acr-name>
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)
az ad sp create-for-rbac \
  --name edge-endpoint-pull \
  --role acrpull \
  --scopes "$ACR_ID"

# Capture the output values
export ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
export ACR_USERNAME=<service-principal-appId>
export ACR_PASSWORD=<service-principal-password>

kubectl create secret docker-registry registry-credentials \
  --docker-server="${ACR_LOGIN_SERVER}" \
  --docker-username="${ACR_USERNAME}" \
  --docker-password="${ACR_PASSWORD}"
```

If your deployment needs to upload artifacts to Azure Storage (for example, alert snapshots or detector logs), make sure `AZURE_STORAGE_CONNECTION_STRING` is set for the helm release or provided via a Kubernetes secret:

```bash
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=..."
```


You'll also need to configure your AWS credentials using `aws configure` to include credentials that have permissions to pull from the appropriate ECR location (if you don't already have the AWS CLI installed, refer to the instructions [here](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)). For Azure-only installations, follow the authentication steps in [Azure requirements (ACR and AKS/AKS Edge Essentials)](#azure-requirements-acr-and-aksaks-edge-essentials) instead.


To install the edge-endpoint, run:
```shell
./deploy/bin/setup-ee.sh
```

This will create the edge-endpoint deployment, which is both the SDK proxy and coordination service. After a short while, you should be able to see something like this if you run `kubectl get pods -n "your-namespace-name"`:

```
NAME                                    READY   STATUS    RESTARTS   AGE
edge-endpoint-594d645588-5mf28          2/2     Running   0          4s
```

If you configured detectors in the [edge config file](/configs/edge-config.yaml), you should also see 2 pods for each of them (one for primary inference and one for out of domain detection), e.g.:

```
NAME                                                                        READY   STATUS    RESTARTS   AGE
edge-endpoint-594d645588-5mf28                                              2/2     Running   0          4s
inferencemodel-primary-det-3jemxiunjuekdjzbuxavuevw15k-5d8b454bcb-xqf8m     1/1     Running   0          2s
inferencemodel-oodd-det-3jemxiunjuekdjzbuxavuevw15k-5d8b454bcb-xqf8m        1/1     Running   0          2s
```


We currently have a hard-coded docker image from Azure Container Registry (ACR) in the [edge-endpoint](/edge-endpoint/deploy/k3s/edge_deployment.yaml)
deployment. If you want to make modifications to the edge endpoint code and push a different


We currently have a hard-coded docker image from Azure Container Registry (ACR) in the [edge-endpoint](/edge-endpoint/deploy/k3s/edge_deployment.yaml)

We currently have a hard-coded docker image from our container registry in the [edge-endpoint](/edge-endpoint/deploy/k3s/edge_deployment.yaml)
deployment. If you want to make modifications to the edge endpoint code and push a different
image to the registry see [Pushing/Pulling Images from the Container Registry](#pushingpulling-images-from-the-container-registry).


We currently have a hard-coded docker image from our container registry in the [edge-endpoint](/edge-endpoint/deploy/k3s/edge_deployment.yaml)
deployment. If you want to make modifications to the edge endpoint code and push a different
image to the registry see [Pushing/Pulling Images from the Container Registry](#pushingpulling-images-from-the-container-registry).

We currently have a hard-coded docker image from ACR in the [edge-endpoint](/edge-endpoint/deploy/k3s/edge_deployment.yaml)

deployment. If you want to make modifications to the edge endpoint code and push a different

image to ACR see [Pushing/Pulling Images from ACR](#pushingpulling-images-from-azure-container-registry-acr).

### Converting from `setup-ee.sh` to Helm

If you have an existing edge-endpoint deployment set up with `setup-ee.sh` and want to convert it to Helm, you can follow these steps:

1. Uninstall the existing edge-endpoint deployment:
```shell
DEPLOYMENT_NAMESPACE=<namespace-you-deployed-to> ./deploy/bin/delete-old-deployment.sh
```
2. Follow the instructions in the [Setting up for Helm](#setting-up-for-helm) section to set up Helm.
3. That's it

## Troubleshooting Deployments

Here are some common issues you might encounter when deploying the edge endpoint and how to resolve them. If you have an issue that's not listed here, please contact IntelliOptics support at [support@IntelliOptics.ai](mailto:support@IntelliOptics.ai) for more assistence.

### Helm deployment fails with `validate-api-token` error

If you see an error like this when running the Helm install command:
```
Error: failed pre-install: 1 error occurred:
        * job validate-api-token-intellioptics-edge failed: BackoffLimitExceeded
```
it means that the API token you provided is not giving access.

There are two possible reasons for this:
1. The API token is invalid. Check the value you're providing and make sure it maps to a valid API token in the IntelliOptics web app.
2. Your account does not have permission to use edge services. Not all plans enable edge inference. To find out more and get your account enabled, contact IntelliOptics support at [support@IntelliOptics.ai](mailto:support@IntelliOptics.ai).

To diagnose which of these is the issue (or if it's something else entirely), you can check the logs of the `validate-api-token-intellioptics-edge` job:

```shell
kubectl logs -n default job/validate-api-token-intellioptics-edge
```

(If you're installing into a different namespace, replace `intellioptics-edge` in the job name with the name of your namespace.)

This will show you the error returned by the IntelliOptics cloud service.

After resolving this issue, you need to reset the Helm release to get back to a clean state. You can do this by running:

```shell
helm uninstall -n default edge-endpoint --keep-history
```

Then, re-run the Helm install command.

### Helm deployment fails with `namespaces "intellioptics-edge" not found`.

This happens when there was an initial failure in the Helm install command and the namespace was not created. 

To fix this, reset the Helm release to get back to a clean state. You can do this by running:

```shell
helm uninstall -n default edge-endpoint --keep-history
```

Then, re-run the Helm install command.

### Pods with `ImagePullBackOff` Status


Check the `refresh_creds` cron job to see if it's running. If it's not, manually refresh the pull secret with the latest ACR credentials. You can do this by re-running the `kubectl create secret docker-registry registry-credentials ...` command above or by using `az acr login` to seed Docker before recreating the secret. If the cron job is running but failing, confirm that the stored Azure service principal (for example, in the `registry-credentials` secret) still has the `acrpull` role and that the password has not expired.


Check the `refresh_creds` cron job to see if it's running. If it's not, manually refresh the pull secret with the latest ACR credentials. You can do this by re-running the `kubectl create secret docker-registry registry-credentials ...` command above or by using `az acr login` to seed Docker before recreating the secret. If the cron job is running but failing, confirm that the stored Azure service principal (for example, in the `registry-credentials` secret) still has the `acrpull` role and that the password has not expired.


Check the `refresh_creds` cron job to see if it's running. If it's not, you may need to refresh the stored container registry credentials so docker/k3s can continue pulling images.  If the script is running but failing, update the secret that stores your registry credentials so that it has permission to pull the required images.

Check the `refresh_creds` cron job to see if it's running. If it's not, you may need to refresh the stored container registry credentials so docker/k3s can continue pulling images.  If the script is running but failing, update the secret that stores your registry credentials so that it has permission to pull the required images.

Check the `refresh-acr-creds` cron job to see if it's running. If it's not, you may need to re-run [refresh-ecr-login.sh](/deploy/bin/refresh-ecr-login.sh) to update the credentials used by docker/k3s to pull images from the Azure Container Registry.  If the script is running but failing, this indicates that the stored Azure credentials (in secret `azure-service-principal`) are invalid or not authorized to pull algorithm images from ACR.



For Azure-based clusters, an `ImagePullBackOff` usually means the service principal or token used for the pull secret expired. If
you created the secret with a temporary token, re-run the `az acr login --expose-token` command and recreate the
`registry-credentials` secret. When using AKS-managed identities, confirm that the node resource group has the `AcrPull` role
assignment on the registry and that the secret referenced by `imagePullSecrets` in your manifests matches the secret name in
your cluster.

```
kubectl logs -n <YOUR-NAMESPACE> -l app=refresh-acr-creds
```

For AKS clusters pulling exclusively from Azure Container Registry, the most common reason for `ImagePullBackOff` is an expired or deleted `registry-credentials` secret. Regenerate it after refreshing your ACR credentials:

```shell
az acr login --name "$ACR_NAME"
kubectl delete secret registry-credentials -n <YOUR-NAMESPACE>
kubectl create secret docker-registry registry-credentials \
  --namespace <YOUR-NAMESPACE> \
  --docker-server "$ACR_LOGIN_SERVER" \
  --docker-username "$(az acr credential show --name "$ACR_NAME" --query username -o tsv)" \
  --docker-password "$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' -o tsv)"
```

After recreating the secret, restart the affected pods or let Kubernetes retry the pulls automatically.

### Changing IP Address Causes DNS Failures and Other Problems
When the IP address of the machine you're using to run edge-endpoint changes, it creates an inconsistent environment for the
k3s system (which doesn't automatically update itself to reflect the change). The most obvious symptom of this is that DNS
address resolution stops working.

If this happens, there's a script to reset the address in k3s and restart the components that need restarting.

From the edge-endpoint directory, you can run:
```
deploy/bin/ip-changed.sh
```
If you're in another directory, adjust the path appropriately.

When the script is complete (it should take roughly 15 seconds), address resolution and other Kubernetes features should
be back online.

If you're running edge-endpoint on a transportable device, such as a laptop, you should run `ip-changed.sh` every time you switch
access points.

### Azure VM Networking Setup Creates a Rule That Causes DNS Failures and Other Problems

Another source of DNS/Kubernetes service problems is the netplan setup that some Azure virtual machines use. I don't know why this
happens on some nodes but not others, but it's easy to see if this is the problem. 

To check, run `ip rule`. If the output has an item with rule 1000 like the following, you have this issue:
```
0:      from 10.45.0.177 lookup 1000
```

to resolve this, simply run the script `deploy/bin/fix-g4-routing.sh`.

The issue should be permanently resolved at this point. You shouldn't need to run the script again on that node, 
even after rebooting.
## Pushing/Pulling Images from Container Registries

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to your container registry, retrieving the image ID and
then using that ID in the [edge_deployment](k3s/edge_deployment/edge_deployment.yaml) file.

The build/push scripts default to AWS Elastic Container Registry (ECR):

```shell
# Build and push image to ECR
./deploy/bin/build-push-edge-endpoint-image.sh
```

To target Azure Container Registry (ACR), provide the registry configuration before running the scripts:

```shell
export REGISTRY_PROVIDER=azure
export ACR_NAME=<your-acr-name>
export ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
export ACR_RESOURCE_GROUP=<resource-group-containing-acr>

# Requires Azure CLI login (interactive or via `az login`/`azure/login` in CI)
./deploy/bin/build-push-edge-endpoint-image.sh --registry-provider azure
```

When tagging existing images, the same flag/environment variables apply:

```shell
./deploy/bin/tag-edge-endpoint-image.sh --registry-provider azure latest
```

Both `build-push` and `tag` scripts share registry authentication helpers (`deploy/bin/registry.sh`) which
normalize login and manifest resolution for AWS (`aws ecr get-login-password`) and Azure (`az acr login`, `az acr repository show-manifests`).
## Container registry configuration

The Edge Endpoint images must live in a container registry that your Kubernetes
cluster can reach. When running the official Helm chart, you can override the
image location through the `image.registry`, `image.repository`, and
`image.tag` values, and reference a Kubernetes image pull secret via the
`imagePullSecrets` list. The instructions below focus on registries that are
currently supported and tested.

| Registry provider | Notes |
| --- | --- |
| Azure Container Registry (ACR) | Recommended for Azure-based deployments. Supports admin accounts and service principals for authentication. |
| Any OCI-compatible registry | Works as long as it issues Docker-compatible credentials that can be stored in a Kubernetes secret. |

### Azure Container Registry example

1. Sign in with the Azure CLI:
   ```bash
   az login
   ```
2. Create a registry (skip if you already have one):
   ```bash
   az acr create --name <REGISTRY_NAME> --resource-group <RESOURCE_GROUP> --sku Standard
   ```
3. Authenticate Docker with ACR. You can use the admin account or a service
   principal. For admin authentication:
   ```bash
   az acr login --name <REGISTRY_NAME>
   ```
   To use a service principal, first create credentials and then log in with
   the returned `appId` (username) and `password`:
   ```bash
   az ad sp create-for-rbac --name <SP_NAME> \
     --scopes $(az acr show --name <REGISTRY_NAME> --query id --output tsv) \
     --role acrpush
   docker login <REGISTRY_NAME>.azurecr.io --username <APP_ID> --password <PASSWORD>
   ```
4. Build and tag the image:
   ```bash
   docker build -t <REGISTRY_NAME>.azurecr.io/<REPOSITORY_NAME>:<TAG> .
   ```
5. Push the image:
   ```bash
   docker push <REGISTRY_NAME>.azurecr.io/<REPOSITORY_NAME>:<TAG>
   ```
6. Create or update the Kubernetes image pull secret so the cluster can pull
   from ACR. Replace the username and password with either the admin account
   credentials or the service principal ID and password:
   ```bash
   kubectl create secret docker-registry acr-credentials \
     --namespace edge \
     --docker-server=<REGISTRY_NAME>.azurecr.io \
     --docker-username=<USERNAME> \
     --docker-password='<PASSWORD>' \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
7. Reference the registry and secret when installing or upgrading the chart:
   ```bash
   helm upgrade -i -n edge edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
     --set image.registry=<REGISTRY_NAME>.azurecr.io \
     --set image.repository=<REPOSITORY_NAME> \
     --set image.tag=<TAG> \
     --set imagePullSecrets[0].name=acr-credentials
   ```

For other OCI-compatible registries, follow the same pattern: build and push
the image, create a Docker registry secret with appropriate credentials, and
configure Helm to use that registry and secret.

## Container registry configuration

The helper scripts in [`deploy/bin`](./bin) default to AWS Elastic Container Registry.
You can override the target provider and registry coordinates with the following
environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `REGISTRY_PROVIDER` | `aws` | Selects the registry backend (`aws` or `azure`). |
| `ECR_ACCOUNT` | `767397850842` | AWS account for Elastic Container Registry (used when `REGISTRY_PROVIDER=aws`). |
| `ECR_REGION` | `us-west-2` | AWS region for Elastic Container Registry. |
| `ACR_NAME` | _required for Azure_ | Azure Container Registry name (e.g. `myregistry`). |
| `ACR_LOGIN_SERVER` | derived from `ACR_NAME` | Fully-qualified Azure registry login server (e.g. `myregistry.azurecr.io`). |
| `ACR_RESOURCE_GROUP` | _(optional)_ | Resource group that hosts the Azure Container Registry. Useful for CI credentials and Azure CLI logins. |

When deploying from CI, set `REGISTRY_PROVIDER=azure` and supply the Azure CLI login
credentials in addition to `ACR_NAME`/`ACR_LOGIN_SERVER` (and optionally
`ACR_RESOURCE_GROUP`) before running the build/push or tagging scripts. For AWS-based
pipelines you do not need to change anything; the defaults remain backwards compatible.

## Pushing/Pulling Images from Container Registries

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to your registry, retrieving the
image ID and then using that ID in the
[edge_deployment](k3s/edge_deployment/edge_deployment.yaml) file.

## Pushing/Pulling Images from Azure Container Registry (ACR)

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to ACR, retrieving the image name and
then using that image reference in the [edge_deployment](k3s/edge_deployment/edge_deployment.yaml) file.


## Pushing/Pulling Images from Azure Container Registry (ACR)

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to ACR, retrieving the image name and
then using that image reference in the [edge_deployment](k3s/edge_deployment/edge_deployment.yaml) file.

## Pushing/Pulling Images from the Container Registry

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to the configured registry, retrieving the image ID and

## Pushing/Pulling Images from Azure Container Registry (ACR)

We currently have a hard-coded docker image in our k3s deployment, which is not ideal.
If you're testing things locally and want to use a different docker image, you can do so
by first creating a docker image locally, pushing it to ACR, retrieving the image ID and


then using that ID in the [edge_deployment](k3s/edge_deployment/edge_deployment.yaml) file.



Follow the following steps:

```shell

# Build and push image to the configured registry

# Build and push image to ACR
ACR_NAME=<your-acr-name>
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
az acr login --name "$ACR_NAME"

# Build for multiple platforms and push
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag ${ACR_LOGIN_SERVER}/intellioptics/edge-endpoint:$(./deploy/bin/git-tag-name.sh) \
  . --push

echo "Pushed ${ACR_LOGIN_SERVER}/intellioptics/edge-endpoint:$(./deploy/bin/git-tag-name.sh)"


# Build and push image to your configured registry
> REGISTRY_SERVER=ghcr.io REGISTRY_NAMESPACE=intellioptics \
>   REGISTRY_USERNAME=<user> REGISTRY_PASSWORD=<token> \
>   ./deploy/bin/build-push-edge-endpoint-image.sh

# Build and push image to ACR
> ./deploy/bin/build-push-edge-endpoint-image.sh


```

## Pushing/Pulling Images from Azure Container Registry (ACR)

If you are running entirely on Azure infrastructure, you can follow similar steps using the `az` CLI and the environment
variables set up in [Azure requirements (ACR and AKS/AKS Edge Essentials)](#azure-requirements-acr-and-aksaks-edge-essentials).
The defaults in [`helm/groundlight-edge-endpoint/values.yaml`](helm/groundlight-edge-endpoint/values.yaml) reference the
`acrintellioptics.azurecr.io/intellioptics/edge-endpoint:latest` image, but you can publish your own builds with:

```bash
az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az acr login --name "$ACR_NAME"

export IMAGE_TAG="$(git rev-parse --short HEAD)"
# Run from the repository root so Docker can locate the project files
cd "$(git rev-parse --show-toplevel)"
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag "${ACR_LOGIN_SERVER}/intellioptics/edge-endpoint:${IMAGE_TAG}" \
  . --push
```

After the push completes, override the Helm values when you deploy:

```bash
helm upgrade -i -n default edge-endpoint edge-endpoint/IntelliOptics-edge-endpoint \
  --set intelliopticsApiToken="${INTELLIOPTICS_API_TOKEN}" \
  --set edgeEndpointTag="${IMAGE_TAG}" \
  --set inferenceTag="${IMAGE_TAG}"
```

> [!TIP]
> The Helm chart expects the registry pull secret to be named `registry-credentials`. If you use a different
> name in your cluster, update the manifests under [`helm/groundlight-edge-endpoint/templates`](helm/groundlight-edge-endpoint/templates)
> or create a second secret with that name that reuses the same token.

If you prefer declarative secret management, the sample manifest at [`aci/edge-endpoint.yaml`](aci/edge-endpoint.yaml)
demonstrates how to embed `imageRegistryCredentials` in Azure-native YAML. You can convert it into a Kubernetes Secret using
`kubectl create secret docker-registry` or your GitOps tool of choice.

For Azure Container Registry builds, set the provider and registry name when invoking the
script:

```shell
REGISTRY_PROVIDER=azure ACR_NAME=myregistry ./deploy/bin/build-push-edge-endpoint-image.sh
```
> [!NOTE]
> The Docker build now pulls the Microsoft package repository to install the `azure-cli` tool inside the edge-endpoint image so
> the container can authenticate with Azure Blob Storage. Ensure the build host can reach `packages.microsoft.com` when running
> the build script.

