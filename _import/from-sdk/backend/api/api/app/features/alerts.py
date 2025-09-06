from ..clients.intellioptics_client import io_experimental as exp_client
import os

BACKEND_WEBHOOK = os.getenv("BACKEND_WEBHOOK", "https://example.com/webhooks/intellioptics")

exp = exp_client()

def ensure_default_rule(detector_id: str, detector_name: str):
    action = exp.make_webhook_action(url=BACKEND_WEBHOOK, method="POST")
    condition = exp.make_condition(kind="CHANGED_TO", parameters={"label": "YES"})
    rule = exp.create_rule(detector=detector_id, rule_name=f"Alert {detector_name} YES", action=action, condition=condition, enabled=True)
    return rule

