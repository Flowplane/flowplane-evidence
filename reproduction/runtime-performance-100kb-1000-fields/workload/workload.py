#!/usr/bin/env python3
"""Generate and validate the immutable 100 x 100 KiB benchmark workload.

This module is intentionally standard-library-only and lives outside the product
repository. Generated JSON is compact UTF-8 with an LF delimiter in JSONL files;
the delimiter is not part of the 102,400-byte record size.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any, Iterable

import coverage_oracle

PAYLOAD_COUNT = 100
PAYLOAD_BYTES = 102_400
MAPPING_FIELD_COUNT = 1_000
ROUND_ROBIN_CYCLES = 5_000
MEASURED_RECORDS = PAYLOAD_COUNT * ROUND_ROBIN_CYCLES
GENERATOR_VERSION = "1.0.0"
PAYLOAD_FILE = "valid-payloads-100kb.jsonl"


class WorkloadError(RuntimeError):
    """A generated or supplied workload violates its immutable contract."""


def _compact_json(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _base_payload(index: int) -> OrderedDict[str, Any]:
    """Build a variant before exact-byte padding.

    Every substitution is scalar-only. Width formatting is deliberate but exact
    size is never assumed: `_fit_payload` always recalculates the padding.
    """
    wide = OrderedDict(
        (f"field{i:04d}", f"value-{index:03d}-{i:04d}")
        for i in range(1, 1001)
    )
    signal_delta = index % 7
    return OrderedDict(
        (
            (
                "run",
                OrderedDict(
                    (
                        ("campaignId", f"fixture-campaign-{index:03d}"),
                        ("sequence", index),
                        ("schemaVersion", "v1.0.0"),
                    )
                ),
            ),
            (
                "event",
                OrderedDict(
                    (
                        ("id", f"evt-benchmark-{index:03d}"),
                        ("type", "ORDER_CREATED" if index % 2 == 0 else "ORDER_UPDATED"),
                        ("ts", f"2026-07-30T12:{index % 60:02d}:{(index * 7) % 60:02d}Z"),
                        ("sourceTimestampEpochMs", 1785412800000 + index * 1000),
                        ("correlationId", f"corr-{index:03d}-http-grpc"),
                        ("trace", f"trace-flowplane-{index:03d}"),
                    )
                ),
            ),
            (
                "tenant",
                OrderedDict(
                    (
                        ("id", f"tenant-{index % 10:02d}"),
                        ("env", "performance"),
                        ("region", ("us-west", "us-east", "eu-west")[index % 3]),
                    )
                ),
            ),
            (
                "order",
                OrderedDict(
                    (
                        ("id", f"ORD-{1000000 + index:07d}"),
                        ("status", "submitted" if index % 2 == 0 else "cancelled"),
                        ("amount", f"{128 + index}.{(index * 17) % 100:02d}"),
                        ("currency", ("USD", "EUR", "GBP")[index % 3]),
                    )
                ),
            ),
            (
                "customer",
                OrderedDict(
                    (
                        ("id", f"CUST-{1000 + index:04d}"),
                        ("tier", ("GOLD", "SILVER", "BRONZE")[index % 3]),
                        ("email", f"buyer{index:03d}@example.com"),
                        ("ssn", f"{100 + index:03d}-45-{6700 + index:04d}"),
                        ("risk", ("LOW", "MEDIUM", "HIGH")[index % 3]),
                    )
                ),
            ),
            (
                "metrics",
                OrderedDict(
                    (
                        ("load", str(50 + index % 40)),
                        ("tempC", round(18.0 + index / 10.0, 1)),
                        ("risk", ("LOW", "MEDIUM", "HIGH")[index % 3]),
                        ("online", index % 2 == 0),
                        ("badInt", f"not-a-number-{index:03d}"),
                        ("huge", str(999999999999 - index)),
                    )
                ),
            ),
            (
                "signals",
                [
                    OrderedDict((("name", "cpu"), ("value", 70 + signal_delta), ("category", "compute"))),
                    OrderedDict((("name", "mem"), ("value", 60 + signal_delta), ("category", "memory"))),
                    OrderedDict((("name", "disk"), ("value", 80 + signal_delta), ("category", "storage"))),
                ],
            ),
            (
                "singleSignals",
                [OrderedDict((("name", f"single-{index:03d}"), ("value", 1), ("category", "singleton")))],
            ),
            (
                "packet",
                OrderedDict(
                    (
                        ("labels", f"alpha-{index:03d}|beta-{index:03d}|gamma-{index:03d}"),
                        ("message", f"  Flowplane   benchmark   variant {index:03d}  "),
                        ("policyNumber", f"POL-{index:03d}-2026"),
                        ("jsonObjectText", f'{{"variant":{index},"active":true}}'),
                        ("jsonArrayText", f'[{index},{index + 1},{index + 2}]'),
                        ("businessDate", f"{(index % 12) + 1:02d}/{(index % 27) + 1:02d}/2026"),
                        ("shipTime", f"{index % 24:02d}:{(index * 3) % 60:02d}:{(index * 7) % 60:02d}"),
                    )
                ),
            ),
            ("wide", wide),
            (
                "benchmark",
                OrderedDict(
                    (
                        ("mappingSchemaVersion", "v1.0.0"),
                        ("variant", index),
                        ("padding", ""),
                    )
                ),
            ),
        )
    )


def _fit_payload(payload: OrderedDict[str, Any]) -> bytes:
    payload["benchmark"]["padding"] = ""
    empty = _compact_json(payload)
    missing = PAYLOAD_BYTES - len(empty)
    if missing < 0:
        raise WorkloadError(f"payload base is {len(empty)} bytes, above {PAYLOAD_BYTES}")
    payload["benchmark"]["padding"] = "x" * missing
    encoded = _compact_json(payload)
    if len(encoded) != PAYLOAD_BYTES:
        raise WorkloadError(
            f"padding calculation produced {len(encoded)} bytes, expected {PAYLOAD_BYTES}"
        )
    return encoded


def build_payload(index: int) -> bytes:
    if not 0 <= index < PAYLOAD_COUNT:
        raise ValueError(f"variant must be 0..{PAYLOAD_COUNT - 1}")
    return _fit_payload(_base_payload(index))


def render_measured_payload(
    variant_index: int,
    campaign_id: str,
    measured_sequence: int,
    source_timestamp_epoch_ms: int,
) -> bytes:
    """Render one campaign record from a variant without structural changes.

    Publishers should call this at send time. The padding is recalculated after
    campaign substitutions, so even sequence 499,999 remains exactly 102,400
    UTF-8 bytes. The immutable bundle hashes identify the 100 source variants;
    campaign evidence should additionally hash rendered samples.
    """
    if not campaign_id:
        raise ValueError("campaign_id must not be empty")
    if measured_sequence < 0:
        raise ValueError("measured_sequence must be non-negative")
    payload = _base_payload(variant_index)
    payload["run"]["campaignId"] = campaign_id
    payload["run"]["sequence"] = measured_sequence
    payload["event"]["id"] = f"evt-benchmark-{measured_sequence:012d}"
    payload["event"]["sourceTimestampEpochMs"] = source_timestamp_epoch_ms
    payload["event"]["correlationId"] = f"{campaign_id}-{measured_sequence:012d}"
    return _fit_payload(payload)


CORE_FIELDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("demoRunId", ("    path: $.run.campaignId", "    required: true")),
    ("sequence", ("    path: $.run.sequence", "    cast: long")),
    ("eventId", ("    path: $.event.id", "    required: true", "    validate:", "      pattern: \"^evt-benchmark-\"")),
    ("orderId", ("    path: $.order.id", "    required: true")),
    ("customerTier", ("    path: $.customer.tier", "    case_convert: upper")),
    ("normalizedStatus", ("    path: $.order.status", "    lookup:", "      dictionary: statusCode")),
    ("orderAmountDouble", ("    path: $.order.amount", "    cast: double")),
    ("amountRounded", ("    path: $.order.amount", "    cast: decimal", "    decimalScale: 2", "    decimalScalePolicy: ROUND")),
    ("eventTypeUpper", ("    path: $.event.type", "    case_convert: upper")),
    ("eventTypeLower", ("    path: $.event.type", "    case_convert: lower")),
    ("receivedAt", ("    path: $.event.ts", "    cast: timestamp")),
    ("region", ("    path: $.tenant.missingRegion", "    fallback:", "      - $.tenant.region")),
    ("runtimeConstant", ("    constant: flowplane-http-grpc-benchmark",)),
    ("customerLabel", ("    path: $.customer.id", "    template: \"customer-${value}\"")),
    ("labelParts", ("    path: $.packet.labels", "    split:", "      by: \"|\"")),
    ("normalizedMessage", ("    path: $.packet.message", "    normalize_string: true")),
    ("loadPlusTen", ("    arithmetic: \"$.metrics.load + 10\"",)),
    ("hugeIntClamped", ("    path: $.metrics.huge", "    cast: int", "    onOverflow: CLAMP")),
    ("badIntDefault", ("    path: $.metrics.badInt", "    cast: int", "    onTypeMismatch: DEFAULT", "    default: -1")),
    ("customerEmailMasked", ("    path: $.customer.email", "    mask: last4")),
    ("customerSsnHashed", ("    path: $.customer.ssn", "    hash: sha256")),
    ("traceHash", ("    path: $.event.trace", "    hash: sha256")),
    ("mappingSchemaVersion", ("    path: $.benchmark.mappingSchemaVersion",)),
    ("signalNames", ("    path: $.signals[*].name", "    array_mode: JOIN", "    delimiter: '|'")),
    ("signalCount", ("    path: $.signals[*]", "    array_mode: COUNT")),
    ("firstHotSignal", ("    path: $.signals[?(@.value >= 70)].name", "    array_mode: FIRST")),
    ("filterFirstSignal", ("    path: $.signals[*].name", "    array_mode: FILTER_FIRST")),
    ("temperature", ("    path: $.metrics.tempC", "    round:", "      scale: 1")),
    ("online", ("    path: $.metrics.online", "    cast: boolean")),
    ("currencyLabel", ("    path: $.order.currency", "    template: \"currency-${value}\"")),
    ("riskBand", ("    path: $.customer.risk", "    lookup:", "      dictionary: riskBand")),
    ("defaultedValue", ("    path: $.packet.missingValue", "    default: fixture-default")),
    ("metadataTenant", ("    metadata: tenant",)),
    ("headerSource", ("    header: source",)),
    ("loadAsInt", ("    path: $.metrics.load", "    cast: int")),
    ("loadAsLong", ("    path: $.metrics.load", "    cast: long")),
    ("jsonObject", ("    path: $.packet.jsonObjectText", "    cast: object")),
    ("jsonArray", ("    path: $.packet.jsonArrayText", "    cast: array")),
    ("businessDate", ("    path: $.packet.businessDate", "    cast: date", "    date_format: MM/dd/yyyy")),
    ("shipTime", ("    path: $.packet.shipTime", "    cast: time", "    date_format: HH:mm:ss")),
    ("regexMatched", ("    path: $.order.id", "    regex_match: \"^ORD-[0-9]+$\"")),
    ("regexExtracted", ("    path: $.customer.email", "    regex_extract: \"buyer([0-9]+)@.*\"", "    sensitive: true")),
    ("regexReplaced", ("    path: $.customer.ssn", "    regex_replace: \"[^0-9]\"", "    replacement: \"\"", "    sensitive: true")),
    ("sensitiveEmail", ("    path: $.customer.email", "    sensitive: true")),
    ("redactedSsn", ("    path: $.customer.ssn", "    redact: true", "    sensitive: true")),
    ("lastSignal", ("    path: $.signals[*].name", "    array_mode: LAST")),
    ("onlySignal", ("    path: $.singleSignals[*].name", "    array_mode: ONLY")),
    ("indexedSignal", ("    path: $.signals[*].name", "    array_mode: INDEX", "    array_index: 1")),
    ("collectedSignals", ("    path: $.signals[*].name", "    array_mode: COLLECT")),
    ("filteredSignals", ("    path: $.signals[?(@.value >= 70)].name", "    array_mode: FILTER_ALL")),
    ("flattenedSignals", ("    path: $.signals[*].name", "    flatten: true")),
    ("distinctSignalCategories", ("    path: $.signals[*].category", "    distinct: true")),
    ("signalValueSum", ("    path: $.signals[*].value", "    aggregate: sum")),
    ("signalValueMin", ("    path: $.signals[*].value", "    aggregate: min")),
    ("signalValueMax", ("    path: $.signals[*].value", "    aggregate: max")),
    ("signalValueCount", ("    path: $.signals[*].value", "    aggregate: count")),
    ("mappedHotSignals", ("    path: $.signals[*]", "    filter: \"item.value > 70\"", "    map:", "      name: item.name", "      category: item.category")),
    ("arithmeticExpression", ("    expression: \"$.metrics.tempC * 1.8 + 32\"", "    round:", "      scale: 2")),
    ("booleanExpression", ("    expression: \"$.metrics.load >= 50\"",)),
    ("policyPrefix", ("    path: $.packet.policyNumber", "    substring:", "      start: 0", "      end: 7")),
    ("objectProjection", ("    object:", "      order.id: $.order.id", "      event.id: $.event.id")),
    ("mergedContext", ("    merge:", "      - $.order", "      - $.customer")),
    ("coalescedValue", ("    valueExpr:", "      coalesce:", "        mode: FIRST_NON_EMPTY", "        candidates:", "          - $.packet.missing", "          - $.customer.id", "          - type: CONST", "            value: fallback")),
    ("caseValue", ("    valueExpr:", "      case:", "        branches:", "          - when:", "              path: $.metrics.load", "              operator: GTE", "              value: 50", "            then: loaded", "        else: idle")),
    ("lookupExpression", ("    valueExpr:", "      lookup:", "        dictionary: riskBand", "        path: $.customer.risk")),
    ("functionConcat", ("    valueExpr:", "      function:", "        name: concat", "        args:", "          - $.order.id", "          - type: CONST", "            value: '-'", "          - $.customer.id")),
    ("functionUpper", ("    valueExpr:", "      function:", "        name: upper", "        args:", "          - $.order.status")),
    ("functionLower", ("    valueExpr:", "      function:", "        name: lower", "        args:", "          - $.order.status")),
    ("functionTrim", ("    valueExpr:", "      function:", "        name: trim", "        args:", "          - $.packet.message")),
    ("functionSubstring", ("    valueExpr:", "      function:", "        name: substring", "        args:", "          - $.packet.policyNumber", "          - type: CONST", "            value: 4", "          - type: CONST", "            value: 7")),
    ("functionSplit", ("    valueExpr:", "      function:", "        name: split", "        args:", "          - $.packet.policyNumber", "          - type: CONST", "            value: '-'")),
    ("functionRound", ("    valueExpr:", "      function:", "        name: round", "        args:", "          - $.order.amount", "          - type: CONST", "            value: 1")),
    ("functionHash", ("    valueExpr:", "      function:", "        name: hash", "        args:", "          - $.customer.email")),
    ("missingAsNull", ("    path: $.packet.notPresent", "    onMissing: NULL")),
    ("itemsAsJson", ("    path: $.signals", "    onArray: JSON_STRING")),
    ("customerAsJson", ("    path: $.customer", "    onObject: JSON_STRING")),
    ("decimalTruncated", ("    path: $.order.amount", "    cast: decimal", "    decimalScale: 1", "    decimalScalePolicy: TRUNCATE")),
)


def build_mapping() -> bytes:
    lines = [
        "version: 1",
        "name: http-grpc-runtime-500k",
        "error_policy:",
        "  on_transformation_error: ROUTE_TO_DLQ",
        "  on_validation_failure: ROUTE_TO_DLQ",
        "  on_type_mismatch: ROUTE_TO_DLQ",
        "output:",
        "  shape: FLAT_OBJECT",
        "  complexTypes: NATIVE_JSON",
        "  fieldNaming: AS_IS",
        "lookups:",
        "  statusCode:",
        "    submitted: ACCEPTED",
        "    cancelled: CANCELLED",
        "  riskBand:",
        "    LOW: LOW",
        "    MEDIUM: MEDIUM",
        "    HIGH: HIGH",
        "fields:",
    ]
    for name, body in CORE_FIELDS:
        lines.append(f"  {name}:")
        lines.extend(body)
    wide_field_count = MAPPING_FIELD_COUNT - len(CORE_FIELDS)
    for i in range(1, wide_field_count + 1):
        lines.extend((f"  wideField{i:04d}:", f"    path: $.wide.field{i:04d}"))
    mapping = ("\n".join(lines) + "\n").encode("utf-8")
    if count_mapping_fields(mapping.decode("utf-8")) != MAPPING_FIELD_COUNT:
        raise WorkloadError("internal mapping generator did not emit 1,000 fields")
    return mapping


def build_hard_mapping() -> bytes:
    """Build the versioned hard-complexity mapping without altering base fixtures."""
    base = build_mapping().decode("utf-8").replace(
        "name: http-grpc-runtime-500k", "name: grpc-hard-complexity-v1", 1
    )
    first_wide = base.index("  wideField0001:\n")
    lines = [base[:first_wide].rstrip("\n")]
    wide_field_count = MAPPING_FIELD_COUNT - len(CORE_FIELDS)
    for index in range(1, wide_field_count + 1):
        lines.append(f"  wideField{index:04d}:")
        lines.extend(_wide_mapping_body(index))
    mapping = ("\n".join(lines) + "\n").encode("utf-8")
    if count_mapping_fields(mapping.decode("utf-8")) != MAPPING_FIELD_COUNT:
        raise WorkloadError("hard mapping generator did not emit 1,000 fields")
    return mapping


def generate_hard_profile(output: Path) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    payload_path = output.parent / PAYLOAD_FILE
    if not payload_path.is_file():
        raise WorkloadError(f"hard profile payload reference is missing: {payload_path}")
    payload_records = payload_path.read_bytes().splitlines()
    if len(payload_records) != PAYLOAD_COUNT or any(len(value) != PAYLOAD_BYTES for value in payload_records):
        raise WorkloadError("hard profile requires the canonical 100 x 102400-byte payload corpus")
    mapping = build_hard_mapping()
    mapping_path = output / "mapping.dsl"
    mapping_path.write_bytes(mapping)
    wide_count = MAPPING_FIELD_COUNT - len(CORE_FIELDS)
    family_counts = {f"chain-{index}": wide_count // 8 for index in range(8)}
    for index in range(wide_count % 8):
        family_counts[f"chain-{index}"] += 1
    manifest = OrderedDict(
        (
            ("schemaVersion", 1),
            ("kind", "flowplane-benchmark-complexity-profile"),
            ("profileId", "grpc-hard-complexity-v1"),
            ("runtimeTarget", "GRPC"),
            ("mapping", "mapping.dsl"),
            ("mappingSha256", _sha256(mapping)),
            ("payloadCorpus", f"../{PAYLOAD_FILE}"),
            ("payloadCorpusSha256", _sha256(payload_path.read_bytes())),
            ("payloadVariantCount", PAYLOAD_COUNT),
            ("payloadBytesEach", PAYLOAD_BYTES),
            ("outputFieldCount", MAPPING_FIELD_COUNT),
            ("coreFieldCount", len(CORE_FIELDS)),
            ("hardWideFieldCount", wide_count),
            ("passThroughWideFieldCount", 0),
            ("minimumOperationsPerWideField", 3),
            ("chainFamilyCounts", family_counts),
            (
                "operationFamilies",
                [
                    "normalize_string", "case_convert", "regex_match", "regex_extract",
                    "regex_replace", "substring", "template", "hash_sha256",
                    "valueExpr_function_concat", "valueExpr_coalesce", "required_policy",
                ],
            ),
            (
                "policySemantics",
                OrderedDict(
                    (
                        ("onTransformationError", "ROUTE_TO_DLQ"),
                        ("onValidationFailure", "ROUTE_TO_DLQ"),
                        ("onTypeMismatch", "ROUTE_TO_DLQ"),
                        ("validCorpusExpectedErrors", 0),
                    )
                ),
            ),
            ("validationEvidence", "compile-simulation.json"),
        )
    )
    (output / "complexity-manifest.json").write_bytes(_compact_json(manifest) + b"\n")
    return dict(manifest)


def _wide_mapping_body(index: int) -> tuple[str, ...]:
    """Return a deterministic, compiler-backed transform chain for a wide field.

    The rotation deliberately avoids pass-through fields. It uses only operations
    exercised by the current real compiler and keeps all valid fixtures on the
    non-error path. Expensive SHA-256 is bounded to one eighth of wide outputs.
    """
    path = f"$.wide.field{index:04d}"
    selector = (index - 1) % 8
    if selector == 0:
        return (
            f"    path: {path}", "    required: true", "    normalize_string: true",
            "    case_convert: upper", '    regex_replace: "VALUE"',
            '    replacement: "WIDE"', '    template: "normalized-${value}"',
        )
    if selector == 1:
        return (
            f"    path: {path}", "    required: true", "    normalize_string: true",
            "    case_convert: lower", '    regex_extract: "value-([0-9]{3}-[0-9]{4})"',
            '    template: "extracted-${value}"',
        )
    if selector == 2:
        return (
            f"    path: {path}", "    required: true", "    normalize_string: true",
            '    regex_replace: "-"', '    replacement: ":"', "    substring:",
            "      start: 0", "      end: 14", '    template: "slice-${value}"',
        )
    if selector == 3:
        return (
            "    valueExpr:", "      function:", "        name: concat", "        args:",
            f"          - {path}", "          - type: CONST", "            value: ':'",
            "          - $.tenant.region", "    normalize_string: true",
            "    case_convert: upper", '    template: "joined-${value}"',
        )
    if selector == 4:
        return (
            "    valueExpr:", "      coalesce:", "        mode: FIRST_NON_EMPTY",
            "        candidates:", f"          - $.wide.missing{index:04d}",
            f"          - {path}", "    normalize_string: true", "    case_convert: lower",
            '    regex_replace: "-"', '    replacement: "_"',
        )
    if selector == 5:
        return (
            f"    path: {path}", "    required: true", "    normalize_string: true",
            "    case_convert: upper", '    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"',
            '    template: "validated-${value}"',
        )
    if selector == 6:
        return (
            f"    path: {path}", "    required: true", "    normalize_string: true",
            "    substring:", "      start: 0", "      end: 14", "    hash: sha256",
            '    template: "digest-${value}"',
        )
    return (
        "    valueExpr:", "      function:", "        name: concat", "        args:",
        f"          - {path}", "          - type: CONST", "            value: ':'",
        "          - $.customer.tier", "          - type: CONST", "            value: ':'",
        "          - $.order.currency", "    normalize_string: true", "    case_convert: lower",
        '    regex_replace: "-"', '    replacement: "_"', '    template: "context-${value}"',
    )


def count_mapping_fields(mapping: str) -> int:
    try:
        fields = mapping.split("\nfields:\n", 1)[1]
    except IndexError as exc:
        raise WorkloadError("mapping has no top-level fields section") from exc
    return len(re.findall(r"(?m)^  [A-Za-z][A-Za-z0-9_]*:$", fields))


def _schema_entries(value: Any, pointer: str = "") -> list[str]:
    if isinstance(value, dict):
        result = [f"{pointer or '/'}|object|properties={','.join(value.keys())}"]
        for key, child in value.items():
            escaped = key.replace("~", "~0").replace("/", "~1")
            result.extend(_schema_entries(child, f"{pointer}/{escaped}"))
        return result
    if isinstance(value, list):
        result = [f"{pointer}|array|cardinality={len(value)}"]
        for index, child in enumerate(value):
            result.extend(_schema_entries(child, f"{pointer}/{index}"))
        return result
    if value is None:
        kind = "null"
    elif isinstance(value, bool):
        kind = "boolean"
    elif isinstance(value, int):
        kind = "integer"
    elif isinstance(value, float):
        kind = "number"
    elif isinstance(value, str):
        kind = "string"
    else:
        raise WorkloadError(f"unsupported JSON type at {pointer}: {type(value).__name__}")
    return [f"{pointer}|{kind}"]


def schema_fingerprint(payload: Any) -> str:
    return _sha256("\n".join(_schema_entries(payload)).encode("utf-8"))


def _canaries() -> list[tuple[str, bytes]]:
    values: list[tuple[str, bytes]] = []
    mutations = (
        ("required", lambda p: p["event"].__setitem__("id", "")),
        ("validation", lambda p: p["event"].__setitem__("id", "invalid-event-id")),
        ("type_mismatch", lambda p: p["order"].__setitem__("amount", "not-a-number")),
        ("lookup_miss", lambda p: p["order"].__setitem__("status", "unknown-status")),
        ("overflow", lambda p: p["metrics"].__setitem__("huge", "999999999999999999999999999999999999")),
    )
    for index, (kind, mutate) in enumerate(mutations):
        payload = _base_payload(index)
        payload["run"]["campaignId"] = f"policy-canary-{kind}"
        mutate(payload)
        values.append((kind, _fit_payload(payload)))
    return values


def _write_jsonl(path: Path, records: Iterable[bytes]) -> None:
    materialized = list(records)
    path.write_bytes(b"\n".join(materialized) + b"\n")


def generate(output: Path, product_root: Path | None = None) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    payloads = [build_payload(i) for i in range(PAYLOAD_COUNT)]
    parsed = [json.loads(value) for value in payloads]
    fingerprint = schema_fingerprint(parsed[0])
    hashes = [_sha256(value) for value in payloads]

    mapping = build_mapping()
    resolved_product_root = product_root or coverage_oracle.default_product_root()
    coverage = _compact_json(coverage_oracle.build_matrix(resolved_product_root)) + b"\n"
    probes = _compact_json(coverage_oracle.compile_probes()) + b"\n"
    canaries = _canaries()
    canary_manifest = _compact_json(
        OrderedDict(
            (
                ("formatVersion", 1),
                ("schemaRequirement", "identical to valid workload schema"),
                ("payloadBytesEach", PAYLOAD_BYTES),
                ("canaries", [OrderedDict((("id", identifier), ("lineIndex", index))) for index, (identifier, _) in enumerate(canaries)]),
            )
        )
    ) + b"\n"
    _write_jsonl(output / PAYLOAD_FILE, payloads)
    _write_jsonl(output / "invalid-policy-payloads.jsonl", [value for _, value in canaries])
    (output / "mapping.dsl").write_bytes(mapping)
    (output / "mapping-coverage.json").write_bytes(coverage)
    (output / "coverage-compile-probes.json").write_bytes(probes)
    (output / "policy-canary-manifest.json").write_bytes(canary_manifest)

    manifest = OrderedDict(
        (
            ("formatVersion", 1),
            ("generatorVersion", GENERATOR_VERSION),
            ("payloadVariantCount", PAYLOAD_COUNT),
            ("payloadBytesExcludingNewline", PAYLOAD_BYTES),
            ("payloadHashes", hashes),
            ("uniquePayloadHashCount", len(set(hashes))),
            ("schemaFingerprint", fingerprint),
            ("schemaFingerprintDefinition", "ordered JSON pointers + node types + object property order + array cardinalities"),
            ("valueVariationOnly", True),
            ("mappingOutputFieldCount", MAPPING_FIELD_COUNT),
            ("roundRobinCycles", ROUND_ROBIN_CYCLES),
            ("measuredRecordCount", MEASURED_RECORDS),
            ("roundRobinFormula", "payloadVariantIndex = measuredSequence % 100"),
            ("jsonEncoding", "UTF-8 compact JSON; LF JSONL delimiter excluded from payload size"),
            ("mappingSha256", _sha256(mapping)),
            ("coverageSha256", _sha256(coverage)),
            ("compileProbesSha256", _sha256(probes)),
            ("policyCanaryManifestSha256", _sha256(canary_manifest)),
        )
    )
    (output / "workload-manifest.json").write_bytes(_compact_json(manifest) + b"\n")

    checksummed = (
        PAYLOAD_FILE,
        "invalid-policy-payloads.jsonl",
        "mapping.dsl",
        "mapping-coverage.json",
        "coverage-compile-probes.json",
        "policy-canary-manifest.json",
        "workload-manifest.json",
    )
    checksum_lines = [
        f"{_sha256((output / name).read_bytes())}  {name}" for name in checksummed
    ]
    (output / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n", encoding="ascii", newline="\n")
    return validate(output)


def _read_jsonl_records(path: Path) -> list[bytes]:
    raw = path.read_bytes()
    if not raw.endswith(b"\n"):
        raise WorkloadError(f"{path.name} must end with one LF delimiter")
    if b"\r\n" in raw:
        raise WorkloadError(f"{path.name} must use LF delimiters, not CRLF")
    return raw[:-1].split(b"\n")


def _verify_checksums(root: Path) -> None:
    lines = (root / "SHA256SUMS").read_text(encoding="ascii").splitlines()
    if not lines:
        raise WorkloadError("SHA256SUMS is empty")
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        if not match:
            raise WorkloadError(f"malformed SHA256SUMS line: {line!r}")
        expected, name = match.groups()
        target = root / name
        if not target.is_file():
            raise WorkloadError(f"checksummed file is missing: {name}")
        actual = _sha256(target.read_bytes())
        if actual != expected:
            raise WorkloadError(f"checksum mismatch for {name}: {actual} != {expected}")


def validate(root: Path, product_root: Path | None = None) -> dict[str, Any]:
    required = (
        PAYLOAD_FILE,
        "invalid-policy-payloads.jsonl",
        "mapping.dsl",
        "mapping-coverage.json",
        "coverage-compile-probes.json",
        "policy-canary-manifest.json",
        "workload-manifest.json",
        "SHA256SUMS",
    )
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        raise WorkloadError(f"missing fixture files: {', '.join(missing)}")
    _verify_checksums(root)

    manifest = json.loads((root / "workload-manifest.json").read_bytes())
    records = _read_jsonl_records(root / PAYLOAD_FILE)
    if len(records) != PAYLOAD_COUNT:
        raise WorkloadError(f"payload variant count is {len(records)}, expected {PAYLOAD_COUNT}")
    bad_sizes = [index for index, record in enumerate(records) if len(record) != PAYLOAD_BYTES]
    if bad_sizes:
        raise WorkloadError(f"payload sizes differ from {PAYLOAD_BYTES} at variants {bad_sizes[:10]}")

    parsed: list[Any] = []
    hashes: list[str] = []
    for index, record in enumerate(records):
        try:
            value = json.loads(record)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WorkloadError(f"variant {index} is not valid UTF-8 JSON: {exc}") from exc
        if _compact_json(value) != record:
            raise WorkloadError(f"variant {index} is not canonical compact JSON")
        if value["benchmark"]["variant"] != index or value["run"]["sequence"] != index:
            raise WorkloadError(f"variant {index} has a sequence/variant identity mismatch")
        parsed.append(value)
        hashes.append(_sha256(record))

    if len(set(hashes)) != PAYLOAD_COUNT:
        raise WorkloadError(f"unique payload hash count is {len(set(hashes))}, expected {PAYLOAD_COUNT}")
    fingerprints = [schema_fingerprint(value) for value in parsed]
    if len(set(fingerprints)) != 1:
        first = fingerprints[0]
        drift = [index for index, value in enumerate(fingerprints) if value != first]
        raise WorkloadError(f"schema drift at variants {drift[:10]}")

    mapping = (root / "mapping.dsl").read_text(encoding="utf-8")
    field_count = count_mapping_fields(mapping)
    if field_count != MAPPING_FIELD_COUNT:
        raise WorkloadError(f"mapping field count is {field_count}, expected {MAPPING_FIELD_COUNT}")
    coverage = json.loads((root / "mapping-coverage.json").read_bytes())
    probes = json.loads((root / "coverage-compile-probes.json").read_bytes())
    canary_manifest = json.loads((root / "policy-canary-manifest.json").read_bytes())

    expected_manifest_values = {
        "payloadVariantCount": PAYLOAD_COUNT,
        "payloadBytesExcludingNewline": PAYLOAD_BYTES,
        "uniquePayloadHashCount": PAYLOAD_COUNT,
        "schemaFingerprint": fingerprints[0],
        "mappingOutputFieldCount": MAPPING_FIELD_COUNT,
        "roundRobinCycles": ROUND_ROBIN_CYCLES,
        "measuredRecordCount": MEASURED_RECORDS,
        "mappingSha256": _sha256((root / "mapping.dsl").read_bytes()),
        "coverageSha256": _sha256((root / "mapping-coverage.json").read_bytes()),
        "compileProbesSha256": _sha256((root / "coverage-compile-probes.json").read_bytes()),
        "policyCanaryManifestSha256": _sha256((root / "policy-canary-manifest.json").read_bytes()),
    }
    for key, expected in expected_manifest_values.items():
        if manifest.get(key) != expected:
            raise WorkloadError(f"manifest {key} is {manifest.get(key)!r}, expected {expected!r}")
    if manifest.get("payloadHashes") != hashes:
        raise WorkloadError("manifest payloadHashes do not match ordered JSONL records")

    canaries = _read_jsonl_records(root / "invalid-policy-payloads.jsonl")
    declared_canaries = canary_manifest.get("canaries", [])
    canary_ids = {item.get("id") for item in declared_canaries}
    if len(canaries) != len(declared_canaries) or any(len(record) != PAYLOAD_BYTES for record in canaries):
        raise WorkloadError("policy canary corpus and manifest disagree or contain non-exact records")
    if any(schema_fingerprint(json.loads(record)) != fingerprints[0] for record in canaries):
        raise WorkloadError("policy canary schema differs from valid workload schema")
    _validate_coverage(
        coverage,
        probes,
        mapping,
        canary_ids,
        product_root or coverage_oracle.default_product_root(),
    )

    return {
        "status": "PASS",
        "root": str(root.resolve()),
        "payloadVariantCount": len(records),
        "payloadBytes": PAYLOAD_BYTES,
        "uniquePayloadHashes": len(set(hashes)),
        "schemaFingerprint": fingerprints[0],
        "mappingOutputFieldCount": field_count,
        "policyCanaryCount": len(canaries),
        "supportedCoverageFamilyCount": len(coverage["families"]),
        "measuredRecordCount": MEASURED_RECORDS,
    }


def _validate_coverage(
    matrix: dict[str, Any],
    probes: dict[str, Any],
    mapping: str,
    canary_ids: set[str],
    product_root: Path,
) -> None:
    try:
        current = coverage_oracle.build_matrix(product_root)
    except coverage_oracle.CoverageOracleError as exc:
        raise WorkloadError(str(exc)) from exc
    expected_hashes = {item["path"]: item["sha256"] for item in current["provenance"]}
    actual_hashes = {item["path"]: item["sha256"] for item in matrix.get("provenance", [])}
    if actual_hashes != expected_hashes:
        raise WorkloadError("coverage oracle provenance is stale relative to current product sources")
    field_names = set(re.findall(r"(?m)^  ([A-Za-z][A-Za-z0-9_]*):$", mapping.split("\nfields:\n", 1)[1]))
    probe_ids = {item.get("id") for item in probes.get("probes", []) if item.get("required")}
    family_ids: set[str] = set()
    for family in matrix.get("families", []):
        identifier = family.get("id")
        if not identifier or identifier in family_ids:
            raise WorkloadError(f"coverage family ID is missing or duplicated: {identifier!r}")
        family_ids.add(identifier)
        supported = set(family.get("supportedVariants", []))
        represented: set[str] = set()
        for evidence in family.get("coverage", []):
            scope = evidence.get("scope")
            variants = set(evidence.get("variants", []))
            if not variants or not evidence.get("evidence"):
                raise WorkloadError(f"coverage evidence is empty for family {identifier}")
            represented.update(variants)
            if scope == "MEASURED_VALID_MAPPING":
                for name in evidence["evidence"]:
                    if name.startswith("mapping:"):
                        continue
                    if name not in field_names:
                        raise WorkloadError(f"coverage family {identifier} references absent mapping field {name}")
            elif scope == "SAME_SCHEMA_POLICY_CANARY":
                missing = set(evidence["evidence"]) - canary_ids
                if missing:
                    raise WorkloadError(f"coverage family {identifier} references absent canaries {sorted(missing)}")
            elif scope == "ISOLATED_COMPILE_PROBE":
                missing = set(evidence["evidence"]) - probe_ids
                if missing:
                    raise WorkloadError(f"coverage family {identifier} references absent compile probes {sorted(missing)}")
            else:
                raise WorkloadError(f"coverage family {identifier} has unsupported scope {scope!r}")
        if family.get("required") and represented != supported:
            raise WorkloadError(
                f"required coverage family {identifier} has unsupported/unrepresented variants: "
                f"missing={sorted(supported - represented)}, extra={sorted(represented - supported)}"
            )


def default_fixture_root() -> Path:
    return Path(__file__).resolve().parent / "generated"


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("generate", "validate", "generate-hard-profile"):
        child = subparsers.add_parser(command)
        child.add_argument("--output", type=Path, default=default_fixture_root())
    args = parser.parse_args(argv)
    try:
        if args.command == "generate":
            result = generate(args.output)
        elif args.command == "validate":
            result = validate(args.output)
        else:
            result = generate_hard_profile(args.output)
    except (OSError, WorkloadError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
