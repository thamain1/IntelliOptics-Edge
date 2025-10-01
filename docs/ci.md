# CI Guide

This repo uses GitHub Actions with three primary jobs:

- **CI Pipeline / Lint & Validate**  
  - Python + Poetry setup
  - `yamllint` on all workflow files (dynamic)
  - `pre-commit` (on pull requests only)

- **CI Pipeline / Unit & Integration Tests**
  - `poetry lock --no-update`
  - `poetry install`
  - `pytest`

- **Build & Push Docker image** (pushes only, not PRs)
  - Builds from `Dockerfile`
  - Tags: `ci-<sha>`, plus `:latest` on `main`, and `:vX.Y.Z` on tags if applicable
  - Auth via `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD` (optional)

## Required GitHub Secrets

Add these under **Settings → Secrets and variables → Actions**:

- `INTELLIOPTICS_API_TOKEN` – API token used by Helm dry-run (and optionally runtime).
- `INTELLIOPTICS_MODEL_URI` – Full SAS URL to the model blob used by Helm dry-run.
- (Optional) `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD` – To push images.

## Branch Protection (main)

Ruleset: **Protect main**
- Require status checks (pull_request):
  - `CI Pipeline / Lint & Validate (pull_request)`
  - `CI Pipeline / Unit & Integration Tests (pull_request)`
  - `format-lite / format (pull_request)` *(optional but recommended)*
- Require linear history (recommended)
- Require ≥1 approval (recommended)

## Running Helm checks (manual)

Action: **Test K3s & Helm (manual)** → **Run workflow ▾**  
Inputs:
- **What to do**: `lint` or `dry-run`
- **Path**: `deploy/helm/intellioptics-edge-endpoint/intellioptics-edge-endpoint`
- **Namespace**: `default` (or target namespace)
- **Values file**: optional path
- **blob_url**/**api_token**: optional overrides. If blank, the workflow falls back to secrets:
  - `INTELLIOPTICS_MODEL_URI` → `.Values.pinamodStorage.blobUrl`
  - `INTELLIOPTICS_API_TOKEN` → `.Values.intelliopticsApiToken`

## Formatting & Linting

Local tooling (matches CI):
- **Black**: line length 120, excludes `vendor/` and `cicd/pulumi/`
- **Ruff**: excludes `vendor/`, `cicd/pulumi/`
- **Pre-commit**: run all hooks locally via:
```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

## Line Endings

`.gitattributes` enforces **LF** for text files. If you edit on Windows, Git will normalize on commit.

## Troubleshooting

- **Poetry lock mismatch**: run `poetry lock --no-update` and commit `poetry.lock`.
- **Helm dry-run requires values**: provide `blob_url` / `api_token` inputs or set repo secrets.
- **Docker build fails on path dep**: ensure `vendor/intellioptics-sdk` is in the repo and copied before `poetry install` in `Dockerfile`.