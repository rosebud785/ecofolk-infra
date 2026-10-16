"""Dev billing kill-switch (ecofolk-infra#15).

Triggered by the dedicated dev budget's Pub/Sub notifications (budget `ecofolk-dev-killswitch`, scoped to
ecofolk-dev, counting gross cost with credits excluded). When the budget's actual `costAmount` reaches
`budgetAmount * UNLINK_THRESHOLD`, it unlinks billing from TARGET_PROJECT_ID by calling
cloudbilling.projects.updateBillingInfo with an empty billing account.

It does nothing unless BOTH hold:
  * the message's budgetDisplayName equals BUDGET_DISPLAY_NAME (every other budget, `ecofolk-all`
    included, is ignored), and
  * TARGET_PROJECT_ID is on UNLINK_ALLOWLIST (comma-separated; Terraform defaults it to ecofolk-dev).

Forecasted-spend alerts never unlink: only the actual costAmount is compared.

Dev only. Never prod: unlinking prod's billing takes the beta down.
"""

import base64
import json
import logging
import os

import functions_framework

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("killswitch")

DEFAULT_ALLOWLIST = "ecofolk-dev"
DEFAULT_BUDGET_DISPLAY_NAME = "ecofolk-dev-killswitch"
DEFAULT_UNLINK_THRESHOLD = "1.0"


def _billing_client():
    # Imported here so the unit tests need no Google client library.
    from google.cloud import billing_v1

    return billing_v1.CloudBillingClient()


def _config():
    allowlist = [
        p.strip()
        for p in os.environ.get("UNLINK_ALLOWLIST", DEFAULT_ALLOWLIST).split(",")
        if p.strip()
    ]
    return {
        "project_id": os.environ.get("TARGET_PROJECT_ID", ""),
        "allowlist": allowlist,
        "budget_display_name": os.environ.get(
            "BUDGET_DISPLAY_NAME", DEFAULT_BUDGET_DISPLAY_NAME
        ),
        "threshold": float(
            os.environ.get("UNLINK_THRESHOLD", DEFAULT_UNLINK_THRESHOLD)
        ),
    }


def should_unlink(notification, project_id, allowlist, budget_display_name, threshold):
    """Return (decision, reason). Pure: no I/O."""
    name = notification.get("budgetDisplayName")
    if name != budget_display_name:
        return False, f"budget {name!r} is not {budget_display_name!r}; ignored"
    if not project_id or project_id not in allowlist:
        return False, f"project {project_id!r} is not on the allowlist {allowlist}"
    try:
        cost = float(notification["costAmount"])
        budget = float(notification["budgetAmount"])
    except (KeyError, TypeError, ValueError):
        return False, "message has no numeric costAmount/budgetAmount"
    if cost >= budget * threshold:
        return True, f"costAmount {cost} >= budgetAmount {budget} x {threshold}"
    return False, f"costAmount {cost} < budgetAmount {budget} x {threshold}"


def unlink_billing(client, project_id):
    client.update_project_billing_info(
        request={
            "name": f"projects/{project_id}",
            "project_billing_info": {"billing_account_name": ""},
        }
    )


def handle(notification, client_factory=None):
    """Decide on one decoded budget notification and unlink if needed. Returns True if it unlinked."""
    cfg = _config()
    decision, reason = should_unlink(
        notification,
        cfg["project_id"],
        cfg["allowlist"],
        cfg["budget_display_name"],
        cfg["threshold"],
    )
    if not decision:
        log.info("no unlink: %s", reason)
        return False
    log.warning(
        "UNLINKING billing from %s: budget %r costAmount %s (%s)",
        cfg["project_id"],
        notification.get("budgetDisplayName"),
        notification.get("costAmount"),
        reason,
    )
    unlink_billing((client_factory or _billing_client)(), cfg["project_id"])
    log.warning("billing unlinked from %s", cfg["project_id"])
    return True


@functions_framework.cloud_event
def on_budget_message(cloud_event):
    """Pub/Sub messagePublished CloudEvent entry point."""
    data = cloud_event.data["message"]["data"]
    notification = json.loads(base64.b64decode(data).decode("utf-8"))
    handle(notification)
