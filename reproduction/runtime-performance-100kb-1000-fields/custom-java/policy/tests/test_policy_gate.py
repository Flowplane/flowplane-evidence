#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from collections import OrderedDict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "policy_gate.py"


def write(path: Path, values: list[object]) -> None:
    path.write_text(
        "".join(json.dumps(value, separators=(",", ":"), sort_keys=False) + "\n" for value in values),
        encoding="utf-8",
        newline="\n",
    )


def run(expected: Path, actual: Path, evidence: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(GATE),
            "verify",
            "--expected",
            str(expected),
            "--actual",
            str(actual),
            "--evidence",
            str(evidence),
        ],
        text=True,
        capture_output=True,
        check=False,
    )


class PolicyGateTest(unittest.TestCase):
    def test_exact_ordered_parity_and_mutations(self) -> None:
        response = OrderedDict(
            (
                ("recordId", "r1"),
                ("status", "DLQ"),
                ("keyBase64", "AA=="),
                (
                    "headers",
                    [
                        OrderedDict((("key", "dup"), ("valueBase64", "AQ=="))),
                        OrderedDict((("key", "dup"), ("valueBase64", "Ag=="))),
                    ],
                ),
                ("outputBase64", ""),
                (
                    "fieldErrors",
                    [
                        OrderedDict(
                            (
                                ("field", "eventId"),
                                ("code", "REGEX_FAILED"),
                                ("message", "Value did not match validation pattern"),
                            )
                        )
                    ],
                ),
                ("http", OrderedDict((("httpStatus", 422), ("resultHeader", "ERROR")))),
                (
                    "error",
                    OrderedDict(
                        (
                            ("code", "VALIDATION_FAILED"),
                            ("message", "Value did not match validation pattern"),
                            ("fieldPath", "eventId"),
                            ("stage", "CORE_MAPPING"),
                            ("retryable", False),
                        )
                    ),
                ),
                ("dlq", OrderedDict((("reason", "VALIDATION_FAILED"),))),
            )
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = root / "expected.jsonl"
            actual = root / "actual.jsonl"
            evidence = root / "evidence.json"
            write(expected, [response])
            write(actual, [response])
            success = run(expected, actual, evidence)
            self.assertEqual(0, success.returncode, success.stdout + success.stderr)
            self.assertEqual("PROVEN", json.loads(evidence.read_text())["parityState"])

            mutated = json.loads(json.dumps(response), object_pairs_hook=OrderedDict)
            mutated["headers"].reverse()
            write(actual, [mutated])
            failure = run(expected, actual, evidence)
            self.assertNotEqual(0, failure.returncode)
            failed = json.loads(evidence.read_text())
            self.assertEqual("NOT_PROVEN", failed["parityState"])
            self.assertTrue(any("/headers/0" in difference for difference in failed["differences"]))

            mutated = json.loads(json.dumps(response), object_pairs_hook=OrderedDict)
            mutated["fieldErrors"][0]["code"] = "VALIDATION_FAILED"
            write(actual, [mutated])
            failure = run(expected, actual, evidence)
            self.assertNotEqual(0, failure.returncode)
            differences = json.loads(evidence.read_text())["differences"]
            self.assertTrue(any("/fieldErrors/0/code" in difference for difference in differences))


if __name__ == "__main__":
    unittest.main()
