# Installing on an NVIDIA Jetson.

1) Install ubuntu, following NVIDIA's instructions.  Then update the OS.

```
sudo apt-get update
sudo apt-get dist-upgrade
```

2) Clone this repo onto the machine.

```
git clone https://github.com/groundlight/edge-endpoint
```

3) Install k3s

```
./deploy/bin/install-k3s.sh cpu
```

or run `~/edge-endpoint/deploy/bin/install-k3s.sh cpu`

4) Azure credentials

Provision the shared Azure resources (ACR + Blob Storage) and load the credentials into your shell. The quickest path is to run the scripts in [`infra/azure-oneclick`](infra/azure-oneclick), copy `.env.example` to `.env`, fill in your subscription/region/resource names, and execute `deploy/install.sh`. Then source the resulting `.env` file to export values such as `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD`, `AZ_BLOB_ACCOUNT`, `AZ_BLOB_CONTAINER`, and `AZURE_BLOB_SAS`.


5) Setup the edge endpoint.

```
./deploy/bin/setup-ee.sh
```

6) Figure out the URL of the edge endpoint.

```
kubectl get service edge-endpoint-service
```

This IP address and port are your URL for `INTELLIOPTICS_ENDPOINT`
