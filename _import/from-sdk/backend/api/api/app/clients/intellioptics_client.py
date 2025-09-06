from intellioptics import IntelliOptics, ExperimentalApi
from ..config import settings  # assumes settings.io_endpoint / settings.io_token

_endpoint = settings.io_endpoint or ""
_token = settings.io_token or None

_client = IntelliOptics(api_token=_token, base_url=_endpoint)
_exp = ExperimentalApi(_client)

def io_client() -> IntelliOptics:
    return _client

def io_experimental() -> ExperimentalApi:
    return _exp

