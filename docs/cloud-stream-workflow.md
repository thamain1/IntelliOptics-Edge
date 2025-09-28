# Cloud-managed RTSP stream configuration

This guide explains how the IntelliOptics cloud backend, configuration API, and edge deployment work together so that edits made in the cloud console propagate to edge pods.

## Cloud API and UI

The `backend/api` service exposes a small configuration API under the `/v1/config` prefix:

- `GET /v1/config/detectors` – list detectors that are available for stream bindings.
- `GET /v1/config/streams` – list all stream definitions stored in the configuration document.
- `GET /v1/config/streams/{name}` – retrieve a single stream definition by name.
- `POST /v1/config/streams` – create a new stream definition.
- `PUT /v1/config/streams/{name}` – update an existing stream definition.
- `DELETE /v1/config/streams/{name}` – remove a stream definition.
- `GET /v1/config/export` – return the rendered `edge-config.yaml` along with metadata so downstream jobs can synchronise state.

These endpoints are protected by the `X-IntelliOptics-Key` header when the `INTELLIOPTICS_API_KEY` environment variable is present, allowing operators to require an API key in production while leaving local development unrestricted.

For convenience the FastAPI app serves a lightweight UI at `/config/streams`. The page provides a form that mirrors the validation rules defined by `StreamConfig`—operators can add RTSP URLs, credentials, sampling cadence, and submission settings without editing YAML by hand. The UI simply calls the API endpoints listed above, so any external tooling can do the same.

## Synchronising configuration to the edge

The cloud API stores its canonical configuration in the `edge_config_documents` table. To push those updates back to an edge deployment, use the `edge_config_sync.py` client found under `backend/api/app/clients/`. The same script is embedded in the Helm chart so that a CronJob can run it on a schedule.

When executed, the client:

1. Calls `GET /v1/config/export` to download the rendered YAML payload.
2. Patches (or creates) the target ConfigMap to update the `edge-config.yaml` key.
3. Optionally restarts the `edge-endpoint` deployment by adding an annotation that forces a rollout, ensuring new pods read the updated configuration file on startup.

The Helm values under `configSync` control the schedule, API base URL, and restart behaviour. If you are wiring the script into another automation system, set the `INTELLIOPTICS_API_KEY` environment variable or pass `--api-key` so the client can authenticate with the cloud backend.

## Edge pod behaviour

Inside the edge container the application loads `edge-config.yaml` via `AppState.load_edge_config()`. A ConfigMap refresh or pod restart causes the file contents to change, which in turn updates the stream definitions that the RTSP ingest manager sees. By combining the cloud API, sync client, and Helm CronJob, operators can manage RTSP streams centrally while ensuring edge pods automatically pick up the latest configuration.
