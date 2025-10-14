## 2025-10-14
- Cluster API updated to image **acrintellioptics.azurecr.io/intellioptics-api:0.3.0-imagequeries**.
- Service Bus env moved to **Kubernetes Secret sb-conn**; API deployment reads SERVICE_BUS_CONN via alueFrom.secretKeyRef.
- Verified end-to-end via Service port-forward **18123**:
  - POST /v1/image-queries → queued ✅
  - GET /v1/image-queries/{id}/wait → result ✅ (1×1 test image)
- Smoke run: 3 requests → 3 results (all OK).
