# IntelliOptics One‑and‑Done Stack

This repo installs a production‑ready IntelliOptics backend (FastAPI) and a queue‑driven worker (ACI by default), complete with Human‑in‑the‑Loop endpoints. Flip to AKS + Managed Identity + Key Vault later without code changes.

## Quickstart
1. Copy `.env.example` to `.env` and fill values (do **not** commit `.env`).
2. Run `bash deploy/install.sh`.
3. The script provisions core Azure resources, builds/pushes images to ACR, deploys the API to **App Service for Containers** and the worker to **Azure Container Instances**.

## Flip to secure (later)
- Replace Service Bus connection strings with **Managed Identity**.
- Move to **AKS** or **Container Apps**.
- Mount secrets from **Key Vault** (CSI or App Service references).
- Enable Application Insights.
