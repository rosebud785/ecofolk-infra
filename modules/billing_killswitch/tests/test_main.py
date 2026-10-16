"""Unit tests for function/main.py (ecofolk-infra#15), with a mocked billing client. Stdlib only:

    python3 -m unittest discover -s modules/billing_killswitch/tests -p 'test_*.py'
"""

import base64
import json
import os
import sys
import types
import unittest
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "function"))

# functions_framework is a deploy-time dependency; stub its decorator if it isn't installed.
try:
    import functions_framework  # noqa: F401
except ImportError:
    stub = types.ModuleType("functions_framework")
    stub.cloud_event = lambda f: f
    sys.modules["functions_framework"] = stub

import main  # noqa: E402

ENV = {
    "TARGET_PROJECT_ID": "ecofolk-dev",
    "UNLINK_ALLOWLIST": "ecofolk-dev",
    "BUDGET_DISPLAY_NAME": "ecofolk-dev-killswitch",
    "UNLINK_THRESHOLD": "1",
}


def note(cost, budget=25.0, name="ecofolk-dev-killswitch", **extra):
    n = {
        "budgetDisplayName": name,
        "costAmount": cost,
        "budgetAmount": budget,
        "currencyCode": "USD",
    }
    n.update(extra)
    return n


class KillSwitchTest(unittest.TestCase):
    def run_handle(self, notification, env=ENV):
        client = mock.Mock()
        with mock.patch.dict(os.environ, env, clear=True):
            unlinked = main.handle(notification, client_factory=lambda: client)
        return unlinked, client

    def assert_unlinked(self, client, project="ecofolk-dev"):
        client.update_project_billing_info.assert_called_once_with(
            request={
                "name": f"projects/{project}",
                "project_billing_info": {"billing_account_name": ""},
            }
        )

    def test_over_threshold_unlinks(self):
        unlinked, client = self.run_handle(note(26.10))
        self.assertTrue(unlinked)
        self.assert_unlinked(client)

    def test_exactly_at_threshold_unlinks(self):
        unlinked, client = self.run_handle(note(25.0))
        self.assertTrue(unlinked)
        self.assert_unlinked(client)

    def test_under_threshold_does_not_unlink(self):
        unlinked, client = self.run_handle(note(24.99))
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_forecast_alert_with_actual_under_does_not_unlink(self):
        unlinked, client = self.run_handle(
            note(12.0, alertThresholdExceeded=0.5, forecastThresholdExceeded=1.0)
        )
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_non_allowlisted_project_does_not_unlink(self):
        env = dict(ENV, TARGET_PROJECT_ID="ecofolk-prod")
        unlinked, client = self.run_handle(note(100.0), env=env)
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_missing_project_id_does_not_unlink(self):
        env = {k: v for k, v in ENV.items() if k != "TARGET_PROJECT_ID"}
        unlinked, client = self.run_handle(note(100.0), env=env)
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_other_budget_over_threshold_does_not_unlink(self):
        unlinked, client = self.run_handle(note(500.0, name="ecofolk-all"))
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_threshold_variable_is_honoured(self):
        env = dict(ENV, UNLINK_THRESHOLD="0.9")
        unlinked, client = self.run_handle(note(22.5), env=env)
        self.assertTrue(unlinked)
        self.assert_unlinked(client)

    def test_defaults_without_env(self):
        # Allowlist, budget name and threshold fall back to ecofolk-dev / ecofolk-dev-killswitch / 1.0.
        env = {"TARGET_PROJECT_ID": "ecofolk-dev"}
        unlinked, client = self.run_handle(note(25.0), env=env)
        self.assertTrue(unlinked)
        self.assert_unlinked(client)
        unlinked, client = self.run_handle(note(24.0), env=env)
        self.assertFalse(unlinked)

    def test_malformed_amounts_do_not_unlink(self):
        unlinked, client = self.run_handle(note("n/a"))
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()

    def test_unlink_logs_cost_and_budget_name(self):
        client = mock.Mock()
        with mock.patch.dict(os.environ, ENV, clear=True):
            with self.assertLogs("killswitch", level="WARNING") as logs:
                main.handle(note(26.10), client_factory=lambda: client)
        text = "\n".join(logs.output)
        self.assertIn("26.1", text)
        self.assertIn("ecofolk-dev-killswitch", text)

    def test_cloud_event_entry_point_decodes_pubsub(self):
        payload = base64.b64encode(json.dumps(note(30.0)).encode()).decode()
        event = types.SimpleNamespace(data={"message": {"data": payload}})
        client = mock.Mock()
        with mock.patch.dict(os.environ, ENV, clear=True), mock.patch.object(
            main, "_billing_client", return_value=client
        ):
            main.on_budget_message(event)
        self.assert_unlinked(client)


if __name__ == "__main__":
    unittest.main()
