#!/usr/bin/env python3
"""Build and verify the custom-Java policy parity corpus.

The verifier deliberately has no third-party dependencies. It compares semantic
runtime contracts and byte-bearing Base64 fields exactly. It never publishes to
Kafka and never inserts downstream records.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
from datetime import datetime
from collections import OrderedDict
from pathlib import Path
from typing import Any

EXPECTED_MAPPING_SHA256 = (
    "007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31"
)
EXPECTED_ACTION = "ROUTE_TO_DLQ"


class GateError(RuntimeError):
    pass


def compact(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=False)


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_jsonl(path: Path) -> list[Any]:
    raw = path.read_bytes()
    if not raw.endswith(b"\n") or b"\r\n" in raw:
        raise GateError(f"{path} must be LF-delimited JSONL ending in one LF")
    result = []
    for line_number, line in enumerate(raw[:-1].split(b"\n"), 1):
        try:
            result.append(json.loads(line, object_pairs_hook=OrderedDict))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GateError(f"{path}:{line_number} is invalid JSON: {exc}") from exc
    return result


def write_jsonl(path: Path, values: list[Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(compact(value) + "\n" for value in values), encoding="utf-8", newline="\n")


def headers_for(identifier: str) -> list[OrderedDict[str, str]]:
    # Repeated names, empty bytes, arbitrary binary, and UTF-8 expose accidental
    # conversion to Map<String,String> or text-only handling.
    values = (
        ("content-type", b"application/json"),
        ("x-flowplane-canary", identifier.encode("ascii")),
        ("trace-bin", b"\x00\x01\xfe\xff"),
        ("trace-bin", b"second-value"),
        ("empty", b""),
        ("utf8", "Grüße-東京".encode("utf-8")),
    )
    return [
        OrderedDict((("key", key), ("valueBase64", base64.b64encode(value).decode("ascii"))))
        for key, value in values
    ]


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    mapping = args.mapping.read_bytes()
    if sha256(mapping) != EXPECTED_MAPPING_SHA256:
        raise GateError("hard mapping SHA-256 does not match the immutable benchmark profile")
    payload_raw = args.payloads.read_bytes()
    payload_lines = payload_raw[:-1].split(b"\n") if payload_raw.endswith(b"\n") else []
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    declared = manifest.get("canaries", [])
    oracle = read_jsonl(args.oracle)
    malformed = bytearray(payload_lines[0])
    malformed[0] = ord("!")
    payload_lines.append(bytes(malformed))
    declared.append({"id": "malformed_json", "lineIndex": len(declared)})
    if len(payload_lines) != len(declared) or len(oracle) != len(declared):
        raise GateError("payload, extended canary manifest, and oracle counts differ")

    requests: list[Any] = []
    expected: list[Any] = []
    for index, (payload, declaration, raw_oracle) in enumerate(
        zip(payload_lines, declared, oracle, strict=True)
    ):
        identifier = declaration.get("id")
        if declaration.get("lineIndex") != index or not identifier:
            raise GateError(f"invalid manifest entry at index {index}")
        if len(payload) != 102_400:
            raise GateError(f"canary {identifier} is {len(payload)} bytes, expected 102400")
        if raw_oracle.get("index") != index or raw_oracle.get("inputSha256") != sha256(payload):
            raise GateError(f"oracle identity mismatch for canary {identifier}")
        policy = raw_oracle.get("errorPolicy", {})
        if set(policy.values()) != {EXPECTED_ACTION} or len(policy) != 3:
            raise GateError(f"mapping policy is not all {EXPECTED_ACTION}: {policy}")

        record_id = f"policy-canary-{index:02d}-{identifier}"
        key = identifier.encode("utf-8") + b"\x00\xff"
        headers = headers_for(identifier)
        request = OrderedDict(
            (
                ("recordId", record_id),
                ("keyBase64", base64.b64encode(key).decode("ascii")),
                ("headers", headers),
                (
                    "source",
                    OrderedDict(
                        (
                            ("topic", "benchmark-policy-input"),
                            ("partition", index % 3),
                            ("offset", 10_000 + index),
                        )
                    ),
                ),
                ("payloadBase64", base64.b64encode(payload).decode("ascii")),
            )
        )
        requests.append(request)

        status = raw_oracle["status"]
        item: OrderedDict[str, Any] = OrderedDict(
            (
                ("recordId", record_id),
                ("status", status),
                ("keyBase64", request["keyBase64"]),
                ("headers", headers),
                ("source", request["source"]),
            )
        )
        if status == "OUTPUT":
            item["outputBase64"] = raw_oracle["outputBase64"]
            item["fieldErrors"] = []
            item["http"] = OrderedDict(
                (("httpStatus", 200), ("resultHeader", "SUCCESS"), ("errorEnvelope", None))
            )
            item["error"] = None
            item["dlq"] = None
        elif status == "DLQ":
            exception = raw_oracle.get("exception")
            field_errors = raw_oracle.get("fieldErrors", [])
            if exception:
                field_errors = [
                    OrderedDict(
                        (
                            ("field", "<record>"),
                            ("code", exception["code"]),
                            ("message", exception["message"]),
                        )
                    )
                ]
            if not field_errors:
                raise GateError(f"DLQ canary {identifier} has no governed-core field errors")
            first = field_errors[0]
            item["outputBase64"] = ""
            item["fieldErrors"] = field_errors
            grouped_code = (
                first["code"] if len(field_errors) == 1 else "MULTIPLE_FIELD_ERRORS"
            )
            grouped_message = (
                first["message"]
                if len(field_errors) == 1
                else f"{len(field_errors)} field errors occurred in one source record."
            )
            item["http"] = OrderedDict(
                (
                    ("httpStatus", 422),
                    ("resultHeader", "ERROR"),
                    (
                        "errorEnvelope",
                        OrderedDict(
                            (
                                ("schemaVersion", "flowplane.runtime.error.v1"),
                                ("type", "com.flowplane.runtime.error"),
                                ("tenantId", args.tenant_id),
                                (
                                    "runtime",
                                    OrderedDict(
                                        (
                                            ("id", args.runtime_id),
                                            ("type", "HTTP"),
                                        )
                                    ),
                                ),
                                (
                                    "artifact",
                                    OrderedDict(
                                        (
                                            ("mappingId", args.mapping_id),
                                            ("artifactVersion", args.mapping_version),
                                            (
                                                "artifactHash",
                                                f"sha256:{EXPECTED_MAPPING_SHA256}",
                                            ),
                                        )
                                    ),
                                ),
                                ("source", request["source"]),
                                (
                                    "error",
                                    OrderedDict(
                                        (
                                            ("field", first["field"]),
                                            (
                                                "path",
                                                "$"
                                                if first["code"] == "INVALID_PAYLOAD"
                                                else first["field"],
                                            ),
                                            ("code", grouped_code),
                                            ("severity", "ERROR"),
                                            ("message", grouped_message),
                                            ("category", "TRANSFORMATION"),
                                            ("retryable", False),
                                        )
                                    ),
                                ),
                                (
                                    "errors",
                                    [
                                        OrderedDict(
                                            (
                                                ("field", error["field"]),
                                                (
                                                    "path",
                                                    "$"
                                                    if error["code"] == "INVALID_PAYLOAD"
                                                    else error["field"],
                                                ),
                                                ("code", error["code"]),
                                                ("message", error["message"]),
                                            )
                                        )
                                        for error in field_errors
                                    ],
                                ),
                                (
                                    "policy",
                                    OrderedDict(
                                        (
                                            ("action", EXPECTED_ACTION),
                                            ("format", "ENVELOPE"),
                                        )
                                    ),
                                ),
                                (
                                    "generatedFields",
                                    OrderedDict(
                                        (
                                            ("errorIdPattern", "^err-[0-9a-f-]{36}$"),
                                            ("timestampFormat", "ISO-8601"),
                                        )
                                    ),
                                ),
                            )
                        ),
                    ),
                )
            )
            invalid_payload = first["code"] == "INVALID_PAYLOAD"
            item["error"] = OrderedDict(
                (
                    ("code", "INVALID_PAYLOAD" if invalid_payload else "VALIDATION_FAILED"),
                    ("message", first["message"]),
                    ("fieldPath", None if invalid_payload else first["field"]),
                    ("stage", "INPUT_PARSE" if invalid_payload else "CORE_MAPPING"),
                    ("retryable", False),
                )
            )
            item["dlq"] = OrderedDict(
                (
                    ("reason", "INVALID_PAYLOAD" if invalid_payload else "VALIDATION_FAILED"),
                    ("tenantId", args.tenant_id),
                    ("runtimeId", args.runtime_id),
                    ("mappingId", args.mapping_id),
                    ("mappingVersion", args.mapping_version),
                    ("artifactHash", f"sha256:{EXPECTED_MAPPING_SHA256}"),
                    ("originalRecordId", record_id),
                    (
                        "metadata",
                        OrderedDict(
                            (("stage", "INPUT_PARSE" if invalid_payload else "CORE_MAPPING"),)
                        ),
                    ),
                )
            )
        else:
            raise GateError(f"unsupported oracle status {status!r}")
        expected.append(item)

    write_jsonl(args.requests, requests)
    write_jsonl(args.expected, expected)
    result = {
        "schemaVersion": 1,
        "kind": "custom-java-policy-parity-preparation",
        "mappingSha256": EXPECTED_MAPPING_SHA256,
        "canaryCount": len(requests),
        "payloadBytesEach": 102_400,
        "oracleSha256": sha256(args.oracle.read_bytes()),
        "requestsSha256": sha256(args.requests.read_bytes()),
        "expectedSha256": sha256(args.expected.read_bytes()),
        "manualDownstreamInsertionUsed": False,
        "liveTrafficUsed": False,
    }
    return result


def compare(expected: Any, actual: Any, pointer: str, differences: list[str]) -> None:
    if type(expected) is not type(actual):
        differences.append(
            f"{pointer}: type {type(actual).__name__} != {type(expected).__name__}"
        )
        return
    if isinstance(expected, dict):
        if list(expected.keys()) != list(actual.keys()):
            differences.append(
                f"{pointer}: ordered keys {list(actual.keys())} != {list(expected.keys())}"
            )
            return
        for key in expected:
            compare(expected[key], actual[key], f"{pointer}/{key}", differences)
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            differences.append(f"{pointer}: length {len(actual)} != {len(expected)}")
            return
        for index, (expected_item, actual_item) in enumerate(zip(expected, actual, strict=True)):
            compare(expected_item, actual_item, f"{pointer}/{index}", differences)
    elif expected != actual:
        differences.append(f"{pointer}: {actual!r} != {expected!r}")


def verify(args: argparse.Namespace) -> dict[str, Any]:
    expected = read_jsonl(args.expected)
    actual = read_jsonl(args.actual)
    differences: list[str] = []
    if len(expected) != len(actual):
        differences.append(f"/: record count {len(actual)} != {len(expected)}")
    for index, item in enumerate(actual):
        envelope = item.get("http", {}).get("errorEnvelope") if isinstance(item, dict) else None
        if not isinstance(envelope, dict) or (
            "errorId" not in envelope and "timestamp" not in envelope
        ):
            continue
        error_id = envelope.pop("errorId", None)
        timestamp = envelope.pop("timestamp", None)
        if not isinstance(error_id, str) or not re.fullmatch(r"err-[0-9a-f-]{36}", error_id):
            differences.append(f"/{index}/http/errorEnvelope/errorId: invalid generated ID")
        try:
            if not isinstance(timestamp, str):
                raise ValueError("not a string")
            datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        except ValueError:
            differences.append(f"/{index}/http/errorEnvelope/timestamp: invalid ISO-8601")
        envelope["generatedFields"] = OrderedDict(
            (("errorIdPattern", "^err-[0-9a-f-]{36}$"), ("timestampFormat", "ISO-8601"))
        )
    for index, (expected_item, actual_item) in enumerate(zip(expected, actual)):
        compare(expected_item, actual_item, f"/{index}", differences)

    result = OrderedDict(
        (
            ("schemaVersion", 1),
            ("kind", "custom-java-policy-parity-evidence"),
            ("parityState", "PROVEN" if not differences else "NOT_PROVEN"),
            ("performanceVerdict", None),
            ("mappingSha256", EXPECTED_MAPPING_SHA256),
            ("expectedSha256", sha256(args.expected.read_bytes())),
            ("actualSha256", sha256(args.actual.read_bytes())),
            (
                "competitorArtifact",
                None
                if args.competitor_artifact is None
                else OrderedDict(
                    (
                        ("path", str(args.competitor_artifact.resolve())),
                        ("sha256", sha256(args.competitor_artifact.read_bytes())),
                    )
                ),
            ),
            ("expectedRecordCount", len(expected)),
            ("actualRecordCount", len(actual)),
            ("orderedFieldErrorsCompared", True),
            ("httpErrorEnvelopeSemanticsCompared", True),
            ("transformErrorCompared", True),
            ("dlqEnvelopeCompared", True),
            ("kafkaKeyBytesCompared", True),
            ("kafkaHeaderOrderAndBytesCompared", True),
            ("manualDownstreamInsertionUsed", False),
            ("differences", differences[:100]),
        )
    )
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(compact(result) + "\n", encoding="utf-8", newline="\n")
    if differences:
        raise GateError(f"parity not proven; {len(differences)} difference(s)")
    return result


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    sub = root.add_subparsers(dest="command", required=True)
    make = sub.add_parser("prepare")
    make.add_argument("--mapping", type=Path, required=True)
    make.add_argument("--payloads", type=Path, required=True)
    make.add_argument("--manifest", type=Path, required=True)
    make.add_argument("--oracle", type=Path, required=True)
    make.add_argument("--requests", type=Path, required=True)
    make.add_argument("--expected", type=Path, required=True)
    make.add_argument("--tenant-id", default="benchmark-tenant")
    make.add_argument("--runtime-id", default="custom-java-zero-copy")
    make.add_argument("--mapping-id", default="grpc-hard-complexity-v1")
    make.add_argument("--mapping-version", default="v1")
    check = sub.add_parser("verify")
    check.add_argument("--expected", type=Path, required=True)
    check.add_argument("--actual", type=Path, required=True)
    check.add_argument("--evidence", type=Path, required=True)
    check.add_argument("--competitor-artifact", type=Path)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        result = prepare(args) if args.command == "prepare" else verify(args)
    except (OSError, GateError, ValueError, KeyError) as exc:
        print(compact({"parityState": "NOT_PROVEN", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
