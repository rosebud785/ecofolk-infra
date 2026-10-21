"""Logging under functions-framework (ecofolk-infra#132). Stdlib only:

    python3 -m unittest discover -s modules/billing_killswitch/tests -p 'test_*.py'

functions-framework puts a handler on the root logger, at WARNING, before it imports main.py. These tests
do the same, import main fresh, and read the stream the killswitch logger's own handler writes to (not
assertLogs, which installs its own handler and level and so can't see a dropped INFO line).
"""

import importlib
import io
import logging
import os
import sys
import types
import unittest
from unittest import mock

sys.dont_write_bytecode = True
FUNCTION_DIR = os.path.join(os.path.dirname(__file__), "..", "function")
if FUNCTION_DIR not in sys.path:
    sys.path.insert(0, FUNCTION_DIR)

# functions_framework is a deploy-time dependency; stub its decorator if it isn't installed.
try:
    import functions_framework  # noqa: F401
except ImportError:
    stub = types.ModuleType("functions_framework")
    stub.cloud_event = lambda f: f
    sys.modules["functions_framework"] = stub

ENV = {
    "TARGET_PROJECT_ID": "ecofolk-dev",
    "UNLINK_ALLOWLIST": "ecofolk-dev",
    "BUDGET_DISPLAY_NAME": "ecofolk-dev-killswitch",
    "UNLINK_THRESHOLD": "1",
}


def note(cost, budget=25.0):
    return {
        "budgetDisplayName": "ecofolk-dev-killswitch",
        "costAmount": cost,
        "budgetAmount": budget,
        "currencyCode": "USD",
    }


class FrameworkLoggingTest(unittest.TestCase):
    def setUp(self):
        root = logging.getLogger()
        ks = logging.getLogger("killswitch")
        saved = (root.handlers[:], root.level, ks.handlers[:], ks.level, ks.propagate)
        saved_main = sys.modules.pop("main", None)

        def restore():
            root.handlers[:], ks.handlers[:] = saved[0], saved[2]
            root.setLevel(saved[1])
            ks.setLevel(saved[3])
            ks.propagate = saved[4]
            sys.modules.pop("main", None)
            if saved_main is not None:
                sys.modules["main"] = saved_main

        self.addCleanup(restore)

        # The framework's state before user code: a root handler at WARNING, no killswitch handler.
        root.handlers[:] = []
        ks.handlers[:] = []
        ks.setLevel(logging.NOTSET)
        ks.propagate = True
        self.root_stream = io.StringIO()
        root.addHandler(logging.StreamHandler(self.root_stream))
        root.setLevel(logging.WARNING)

        # Whatever handler main.py builds at import writes here.
        self.stdout = io.StringIO()
        with mock.patch.object(sys, "stdout", self.stdout):
            self.main = importlib.import_module("main")

    def handle(self, notification):
        client = mock.Mock()
        with mock.patch.dict(os.environ, ENV, clear=True):
            unlinked = self.main.handle(notification, client_factory=lambda: client)
        return unlinked, client

    def test_decline_is_logged_as_plain_text(self):
        unlinked, client = self.handle(note(0))
        self.assertFalse(unlinked)
        client.update_project_billing_info.assert_not_called()
        # The ef#885 proof query is textPayload:"no unlink: costAmount".
        self.assertIn("no unlink: costAmount", self.stdout.getvalue())

    def test_unlink_warning_still_logged_once(self):
        # Control: a unit call over threshold, mocked billing client; nothing is published.
        unlinked, client = self.handle(note(26.10))
        self.assertTrue(unlinked)
        client.update_project_billing_info.assert_called_once()
        # Visible before #132 too (WARNING passes the root handler); after it, exactly once, not twice.
        both = self.stdout.getvalue() + self.root_stream.getvalue()
        self.assertEqual(both.count("UNLINKING billing from ecofolk-dev"), 1)


if __name__ == "__main__":
    unittest.main()
