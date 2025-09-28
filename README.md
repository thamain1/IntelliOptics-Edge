# IntelliOptics Edge Endpoint

(For instructions on running on Balena, see [here](./deploy/balena-k3s/README.md))

Run your IntelliOptics models on-prem by hosting an Edge Endpoint on your own hardware.  The Edge Endpoint exposes the exact same API as the IntelliOptics cloud service, so any IntelliOptics application can point to the Edge Endpoint simply by configuring the `INTELLIOPTICS_ENDPOINT` environment variable as follows:

```bash
export INTELLIOPTICS_ENDPOINT=http://localhost:30101
# This assumes your IntelliOptics SDK application is running on the same host as the Edge Endpoint.
```

The Edge Endpoint will attempt to answer image queries using local models for your detectors.  If it can do so confidently, you get faster and cheaper responses. If it can't, it will escalate the image queries to the cloud for further analysis.

## Running the Edge Endpoint

To set up the Edge Endpoint, please refer to the [deploy README](deploy/README.md).

### Configuring detectors for the Edge Endpoint

While not required, configuring detectors provides fine-grained control over the behavior of specific detectors on the edge. Please refer to [the guide to configuring detectors](/CONFIGURING-DETECTORS.md) for more information.

### Using the Edge Endpoint with your IntelliOptics application.

Any application written with the [IntelliOptics SDK](https://intelliopticsweb37558.z13.web.core.windows.net/python-sdk/api-reference-docs/index.html) can work with an Edge Endpoint without any code changes.  Simply set an environment variable with the URL of your Edge Endpoint like:

```bash
export INTELLIOPTICS_ENDPOINT=http://localhost:30101
```

To find the correct port, run `kubectl get services` and you should see an entry like this:
```
NAME                                                        TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                         AGE
service/edge-endpoint-service                               NodePort   10.43.141.253   <none>        30101:30101/TCP                 23m
```

The port is the second number listed under ports for the `edge-endpoint-service` (in this case, 30101).

If you'd like more control, you can also initialize the `IntelliOptics` SDK object with the endpoint explicitly like this:

```python
from intellioptics import IntelliOptics

io = IntelliOptics(endpoint="http://localhost:30101")

det = io.get_or_create_detector(name="doorway", query="Is the doorway open?")
img = "./docs/static/img/doorway.jpg"
with open(img, "rb") as img_file:
    byte_stream = img_file.read()

image_query = io.submit_image_query(detector=det, image=byte_stream)
print(f"The answer is {image_query.result}")
```

See the [SDK's getting started guide](https://intelliopticsweb37558.z13.web.core.windows.net/python-sdk/api-reference-docs/models.html#intellioptics.IntelliOptics)) for more info about using the IntelliOptics SDK.

## Development and Internal Architecture

This section describes the various components that comprise the IntelliOptics Edge Endpoint, and how they interoperate.
This might be useful for tuning operational aspects of your endpoint, contributing to the project, or debugging problems.

### Components and terms

Inside the edge-endpoint pod there are two containers: one for the edge logic and another one for creating/updating inference deployments.

* `edge-endpoint` container: This container handles the edge logic.
* `inference-model-updater` container: This container checks for changes to the models being used for edge inference and updates them when new versions are available.
* `status-monitor` container: This container serves the status page, and reports metrics to the cloud.

Each detector will have 2 inferencemodel pods, one for the primary model and one for the out of domain detection (OODD) model.
Each inferencemodel pod contains one container.

* `inference-server container`: This container holds the edge model

* `Cloud API:` This is the upstream API that we use as a fallback in case the edge logic server encounters problems. It is set to `https://intellioptics-api-37558.azurewebsites.net`.

* `Endpoint url:` This is the URL where the endpoint's functionality is exposed to the SDK or applications.  (i.e., the upstream you can set for the IntelliOptics application). This is set to `http://localhost:30101`.

## Attribution

This product includes software developed by third parties, which is subject to their respective open-source licenses.

See [THIRD_PARTY_LICENSES.md](./licenses/THIRD_PARTY_LICENSES.md) for details and license texts.
