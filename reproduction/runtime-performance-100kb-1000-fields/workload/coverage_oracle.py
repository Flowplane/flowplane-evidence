"""Read-only supported-operation oracle for the isolated workload.

The catalog is intentionally explicit. Product files are read only to attach
content hashes and verify the source markers used to derive each family.
"""

from __future__ import annotations

import hashlib
from collections import OrderedDict
from pathlib import Path
from typing import Any


class CoverageOracleError(RuntimeError):
    pass


PROVENANCE = (
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/Recipe.java", ("arrayMode", "valueExpression", "regexMatch")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/OptimizedRuntimeExecutor.java", ("evaluateFunction", 'case "uuid"', "applyTransforms")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/MappingCompiler.java", ("collectExpressionPaths", "resolveLookup")),
    ("flowplane-java-sdk/flowplane-core/src/test/java/com/flowplane/core/ParseStrategyAllOperationsEquivalenceTest.java", ("deterministicOperationsMatchAcrossAllParseStrategies", "function_uuid", "validation_default")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/ArrayMode.java", ("FILTER_ALL", "JOIN")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/TypeMismatchPolicy.java", ("STRINGIFY", "DEFAULT")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/OverflowPolicy.java", ("CLAMP", "DEFAULT")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/MissingPolicy.java", ("SKIP_FIELD", "ERROR")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/NullPolicy.java", ("ALLOW", "DEFAULT")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/LookupOnMiss.java", ("KEEP_ORIGINAL", "SKIP_FIELD")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/ErrorPolicy.java", ("ROUTE_TO_DLQ", "REDACT_AND_PROCEED")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/ArrayPolicy.java", ("USE_PICK", "JSON_STRING")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/ObjectPolicy.java", ("NATIVE", "JSON_STRING")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/DecimalScalePolicy.java", ("ROUND", "TRUNCATE")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/OutputShape.java", ("FLAT_OBJECT", "BYTES")),
    ("flowplane-java-sdk/flowplane-core/src/main/java/com/flowplane/core/ComplexTypeMode.java", ("NATIVE_JSON", "ERROR")),
)


def default_product_root() -> Path:
    return Path(__file__).resolve().parents[4] / "repositories" / "flowplane-controlplane"


def provenance(product_root: Path) -> list[dict[str, Any]]:
    result = []
    for relative, markers in PROVENANCE:
        path = product_root / relative
        if not path.is_file():
            raise CoverageOracleError(f"coverage provenance file missing: {relative}")
        data = path.read_bytes()
        text = data.decode("utf-8")
        missing = [marker for marker in markers if marker not in text]
        if missing:
            raise CoverageOracleError(f"coverage provenance markers missing in {relative}: {missing}")
        result.append(
            OrderedDict(
                (
                    ("path", relative.replace("\\", "/")),
                    ("sha256", hashlib.sha256(data).hexdigest()),
                    ("markers", list(markers)),
                )
            )
        )
    return result


def _e(scope: str, variants: list[str], evidence: list[str], gate: str) -> OrderedDict[str, Any]:
    return OrderedDict((("scope", scope), ("variants", variants), ("evidence", evidence), ("gate", gate)))


def _family(identifier: str, variants: list[str], coverage: list[OrderedDict[str, Any]], note: str | None = None) -> OrderedDict[str, Any]:
    value = OrderedDict((("id", identifier), ("required", True), ("supportedVariants", variants), ("coverage", coverage)))
    if note:
        value["coexistenceNote"] = note
    return value


def families() -> list[OrderedDict[str, Any]]:
    measured = "MEASURED_VALID_MAPPING"
    canary = "SAME_SCHEMA_POLICY_CANARY"
    probe = "ISOLATED_COMPILE_PROBE"
    return [
        _family("value_sources", ["PATH", "FALLBACK", "DEFAULT", "CONSTANT", "METADATA", "HEADER"], [_e(measured, ["PATH", "FALLBACK", "DEFAULT", "CONSTANT", "METADATA", "HEADER"], ["orderId", "region", "defaultedValue", "runtimeConstant", "metadataTenant", "headerSource"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("string_transforms", ["UPPER", "LOWER", "NORMALIZE", "TEMPLATE", "SUBSTRING", "SPLIT"], [_e(measured, ["UPPER", "LOWER", "NORMALIZE", "TEMPLATE", "SUBSTRING", "SPLIT"], ["eventTypeUpper", "eventTypeLower", "normalizedMessage", "customerLabel", "policyPrefix", "labelParts"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("scalar_and_json_casts", ["INT", "LONG", "DOUBLE", "DECIMAL", "BOOLEAN", "OBJECT", "ARRAY"], [_e(measured, ["INT", "LONG", "DOUBLE", "DECIMAL", "BOOLEAN", "OBJECT", "ARRAY"], ["loadAsInt", "loadAsLong", "orderAmountDouble", "amountRounded", "online", "jsonObject", "jsonArray"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("temporal_casts", ["TIMESTAMP", "DATE", "TIME"], [_e(measured, ["TIMESTAMP", "DATE", "TIME"], ["receivedAt", "businessDate", "shipTime"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("lookup", ["FIELD_LOOKUP", "VALUE_EXPRESSION_LOOKUP"], [_e(measured, ["FIELD_LOOKUP", "VALUE_EXPRESSION_LOOKUP"], ["normalizedStatus", "lookupExpression"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("regex", ["MATCH", "EXTRACT", "REPLACE"], [_e(measured, ["MATCH", "EXTRACT", "REPLACE"], ["regexMatched", "regexExtracted", "regexReplaced"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("data_protection", ["MASK", "SENSITIVE", "HASH", "REDACT", "ENCRYPT", "DECRYPT"], [_e(measured, ["MASK", "SENSITIVE", "HASH", "REDACT"], ["customerEmailMasked", "sensitiveEmail", "customerSsnHashed", "redactedSsn"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["ENCRYPT", "DECRYPT"], ["crypto-key-provider"], "COMPILE_THEN_KEYED_CANARY")], "Encryption and decryption require benchmark-only key material and are excluded from the valid 500K population."),
        _family("array_modes", ["FIRST", "LAST", "INDEX", "ONLY", "FILTER_FIRST", "FILTER_ALL", "COUNT", "COLLECT", "JOIN"], [_e(measured, ["FIRST", "LAST", "INDEX", "ONLY", "FILTER_FIRST", "FILTER_ALL", "COUNT", "COLLECT", "JOIN"], ["firstHotSignal", "lastSignal", "indexedSignal", "onlySignal", "firstHotSignal", "filteredSignals", "signalCount", "collectedSignals", "signalNames"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("array_advanced", ["PATH_FILTER", "FLATTEN", "DISTINCT", "FILTER_MAP"], [_e(measured, ["PATH_FILTER", "FLATTEN", "DISTINCT", "FILTER_MAP"], ["firstHotSignal", "flattenedSignals", "distinctSignalCategories", "mappedHotSignals"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("aggregates", ["SUM", "MIN", "MAX", "COUNT"], [_e(measured, ["SUM", "MIN", "MAX", "COUNT"], ["signalValueSum", "signalValueMin", "signalValueMax", "signalValueCount"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("expressions", ["ARITHMETIC", "BOOLEAN_COMPARISON", "ROUND"], [_e(measured, ["ARITHMETIC", "BOOLEAN_COMPARISON", "ROUND"], ["arithmeticExpression", "booleanExpression", "arithmeticExpression"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("structured_values", ["OBJECT_PROJECTION", "MERGE"], [_e(measured, ["OBJECT_PROJECTION", "MERGE"], ["objectProjection", "mergedContext"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("value_expressions", ["COALESCE", "CASE", "LOOKUP"], [_e(measured, ["COALESCE", "CASE", "LOOKUP"], ["coalescedValue", "caseValue", "lookupExpression"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("deterministic_functions", ["CONCAT", "TEMPLATE", "UPPER", "LOWER", "TRIM", "SUBSTRING", "SPLIT", "ROUND", "HASH"], [_e(measured, ["CONCAT", "TEMPLATE", "UPPER", "LOWER", "TRIM", "SUBSTRING", "SPLIT", "ROUND", "HASH"], ["functionConcat", "functionConcat", "functionUpper", "functionLower", "functionTrim", "functionSubstring", "functionSplit", "functionRound", "functionHash"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE")]),
        _family("nondeterministic_functions", ["UUID", "NOW"], [_e(probe, ["UUID", "NOW"], ["nondeterministic-functions"], "COMPILE_AND_ISOLATED_SHAPE_CANARY")], "Nondeterministic outputs cannot participate in stable output-hash parity and are excluded from the valid 500K mapping."),
        _family("validation", ["REQUIRED", "PATTERN", "ONE_OF", "MIN", "MAX"], [_e(measured, ["REQUIRED", "PATTERN"], ["eventId"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["ONE_OF", "MIN", "MAX"], ["validation-constraints"], "COMPILE_AND_SAME_SCHEMA_CANARY"), _e(canary, ["REQUIRED", "PATTERN"], ["required", "validation"], "POLICY_CANARY_AFTER_MEASURED_DRAIN")]),
        _family("validation_on_error", ["SET_DEFAULT", "SET_NULL", "SKIP_FIELD"], [_e(probe, ["SET_DEFAULT", "SET_NULL", "SKIP_FIELD"], ["validation-on-error-actions"], "COMPILE_AND_SAME_SCHEMA_CANARY")], "Mutually exclusive on one field and deliberately kept out of the success population."),
        _family("type_mismatch_policy", ["COERCE", "STRINGIFY", "DEFAULT", "ERROR"], [_e(measured, ["COERCE", "DEFAULT"], ["loadAsInt", "badIntDefault"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["STRINGIFY", "ERROR"], ["type-mismatch-actions"], "COMPILE_AND_SAME_SCHEMA_CANARY"), _e(canary, ["ERROR"], ["type_mismatch"], "POLICY_CANARY_AFTER_MEASURED_DRAIN")], "Only one type-mismatch action applies to a field; failure actions use a separate mapping probe."),
        _family("overflow_policy", ["ERROR", "CLAMP", "DEFAULT"], [_e(measured, ["CLAMP"], ["hugeIntClamped"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["ERROR", "DEFAULT"], ["overflow-actions"], "COMPILE_AND_SAME_SCHEMA_CANARY"), _e(canary, ["ERROR", "DEFAULT"], ["overflow"], "POLICY_CANARY_AFTER_MEASURED_DRAIN")], "Overflow actions are mutually exclusive on a field."),
        _family("missing_policy", ["NULL", "SKIP_FIELD", "ERROR"], [_e(measured, ["NULL"], ["missingAsNull"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["SKIP_FIELD", "ERROR"], ["missing-actions"], "COMPILE_AND_STRUCTURAL_POLICY_PROBE")], "A missing-path probe necessarily differs structurally and is not counted among the 100 valid schema variants."),
        _family("null_policy", ["ALLOW", "DEFAULT", "ERROR"], [_e(probe, ["ALLOW", "DEFAULT", "ERROR"], ["null-actions"], "COMPILE_AND_NULL_POLICY_PROBE")], "JSON null changes the valid scalar type fingerprint, so null branches use an isolated policy corpus."),
        _family("array_policy", ["USE_PICK", "JSON_STRING", "ERROR"], [_e(measured, ["USE_PICK", "JSON_STRING"], ["firstHotSignal", "itemsAsJson"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["ERROR"], ["array-policy-error"], "COMPILE_AND_POLICY_CANARY")]),
        _family("object_policy", ["NATIVE", "JSON_STRING", "ERROR"], [_e(measured, ["NATIVE", "JSON_STRING"], ["objectProjection", "customerAsJson"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["ERROR"], ["object-policy-error"], "COMPILE_AND_POLICY_CANARY")]),
        _family("decimal_scale_policy", ["FAIL", "ROUND", "TRUNCATE"], [_e(measured, ["ROUND", "TRUNCATE"], ["amountRounded", "decimalTruncated"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["FAIL"], ["decimal-scale-fail"], "COMPILE_AND_POLICY_CANARY")]),
        _family("lookup_on_miss", ["KEEP_ORIGINAL", "DEFAULT", "NULL", "SKIP_FIELD", "ERROR"], [_e(probe, ["KEEP_ORIGINAL", "DEFAULT", "NULL", "SKIP_FIELD", "ERROR"], ["lookup-miss-actions"], "COMPILE_AND_SAME_SCHEMA_CANARY"), _e(canary, ["KEEP_ORIGINAL", "DEFAULT", "NULL", "SKIP_FIELD", "ERROR"], ["lookup_miss"], "POLICY_CANARY_AFTER_MEASURED_DRAIN")], "Lookup miss actions are mutually exclusive for one lookup and need separate compiled probe fields/mappings."),
        _family("mapping_error_actions", ["FAIL_PIPELINE", "SKIP_RECORD", "ROUTE_TO_DLQ", "REDACT_AND_PROCEED"], [_e(canary, ["ROUTE_TO_DLQ"], ["required", "validation", "type_mismatch"], "POLICY_CANARY_AFTER_MEASURED_DRAIN"), _e(probe, ["FAIL_PIPELINE", "SKIP_RECORD", "REDACT_AND_PROCEED"], ["mapping-error-actions"], "SEPARATE_MAPPING_COMPILE_AND_CANARY")], "Each mapping has one action per error category; alternatives cannot coexist in the primary mapping."),
        _family("output_shape", ["OBJECT", "FLAT_OBJECT", "JSON_STRING", "PRIMITIVE", "BYTES"], [_e(measured, ["FLAT_OBJECT"], ["mapping:output.shape"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["OBJECT", "JSON_STRING", "PRIMITIVE", "BYTES"], ["output-shapes"], "SEPARATE_MAPPING_COMPILE_PROBES")], "Output shape is mapping-wide and mutually exclusive."),
        _family("complex_type_mode", ["NATIVE_JSON", "JSON_STRING", "ERROR"], [_e(measured, ["NATIVE_JSON"], ["mapping:output.complexTypes"], "PRIMARY_MAPPING_COMPILE_AND_SMOKE"), _e(probe, ["JSON_STRING", "ERROR"], ["complex-type-modes"], "SEPARATE_MAPPING_COMPILE_PROBES")], "Complex type mode is mapping-wide and mutually exclusive."),
    ]


def compile_probes() -> OrderedDict[str, Any]:
    identifiers = [
        "crypto-key-provider", "nondeterministic-functions", "validation-constraints",
        "validation-on-error-actions", "type-mismatch-actions", "overflow-actions",
        "missing-actions", "null-actions", "array-policy-error", "object-policy-error",
        "decimal-scale-fail", "lookup-miss-actions", "mapping-error-actions",
        "output-shapes", "complex-type-modes",
    ]
    return OrderedDict(
        (
            ("formatVersion", 1),
            ("status", "DECLARED_NOT_EXECUTED"),
            ("executionGate", "Every probe must compile through the live mapping validation endpoint before either runtime is created."),
            (
                "probes",
                [
                    OrderedDict(
                        (
                            ("id", identifier),
                            ("required", True),
                            ("isolation", "separate mapping version or policy corpus; excluded from valid 500K latency population"),
                            ("cases", _probe_cases(identifier)),
                            ("caseCount", len(_probe_cases(identifier))),
                        )
                    )
                    for identifier in identifiers
                ],
            ),
        )
    )


def _doc(fields: str, prefix: str = "output: FLAT_OBJECT\n") -> str:
    return prefix + "fields:\n" + fields.rstrip() + "\n"


def _case(identifier: str, dsl: str, execution: str = "COMPILE_ONLY") -> OrderedDict[str, Any]:
    return OrderedDict((("id", identifier), ("mappingDsl", dsl), ("execution", execution)))


def _probe_cases(identifier: str) -> list[OrderedDict[str, Any]]:
    simple = {
        "crypto-key-provider": _doc("  encrypted:\n    path: $.customer.email\n    encrypt:\n      key_ref: benchmark-key\n  decrypted:\n    path: $.packet.ciphertext\n    decrypt:\n      key_ref: benchmark-key"),
        "nondeterministic-functions": _doc("  generatedUuid:\n    valueExpr:\n      function:\n        name: uuid\n  generatedNow:\n    valueExpr:\n      function:\n        name: now"),
        "validation-constraints": _doc("  checked:\n    path: $.metrics.load\n    validate:\n      one_of: ['50', '51']\n      min: 0\n      max: 100"),
        "validation-on-error-actions": _doc("  setDefault:\n    path: $.metrics.load\n    validate: { min: 10 }\n    on_error: { action: SET_DEFAULT, value: 10 }\n  setNull:\n    path: $.metrics.load\n    validate: { min: 10 }\n    on_error: { action: SET_NULL }\n  skipField:\n    path: $.metrics.load\n    validate: { min: 10 }\n    on_error: { action: SKIP_FIELD }"),
        "type-mismatch-actions": _doc("  stringifyMismatch:\n    path: $.order.amount\n    cast: int\n    onTypeMismatch: STRINGIFY\n  errorMismatch:\n    path: $.order.amount\n    cast: int\n    onTypeMismatch: ERROR"),
        "overflow-actions": _doc("  errorOverflow:\n    path: $.metrics.huge\n    cast: int\n    onOverflow: ERROR\n  defaultOverflow:\n    path: $.metrics.huge\n    cast: int\n    onOverflow: DEFAULT\n    default: 0"),
        "missing-actions": _doc("  skipMissing:\n    path: $.missing.value\n    onMissing: SKIP_FIELD\n  errorMissing:\n    path: $.missing.value\n    onMissing: ERROR"),
        "null-actions": _doc("  allowNull:\n    path: $.nullable\n    onNull: ALLOW\n  defaultNull:\n    path: $.nullable\n    onNull: DEFAULT\n    default: fallback\n  errorNull:\n    path: $.nullable\n    onNull: ERROR"),
        "array-policy-error": _doc("  arrayError:\n    path: $.signals\n    onArray: ERROR"),
        "object-policy-error": _doc("  objectError:\n    path: $.customer\n    onObject: ERROR"),
        "decimal-scale-fail": _doc("  scaleFail:\n    path: $.order.amount\n    cast: decimal\n    decimalScale: 1\n    decimalScalePolicy: FAIL"),
    }
    if identifier in simple:
        execution = "COMPILE_THEN_ISOLATED_CANARY" if identifier != "nondeterministic-functions" else "COMPILE_THEN_SHAPE_ONLY_CANARY"
        return [_case(identifier, simple[identifier], execution)]
    if identifier == "lookup-miss-actions":
        fields = []
        for action in ("KEEP_ORIGINAL", "DEFAULT", "NULL", "SKIP_FIELD", "ERROR"):
            fields.append(f"  miss{action.title().replace('_', '')}:\n    valueExpr:\n      lookup:\n        dictionary: status\n        path: $.order.status\n        onMiss: {action}\n        defaultValue: fallback")
        prefix = "output: FLAT_OBJECT\nlookups:\n  status:\n    submitted: ACCEPTED\n"
        return [_case(identifier, _doc("\n".join(fields), prefix), "COMPILE_THEN_SAME_SCHEMA_CANARY")]
    if identifier == "mapping-error-actions":
        return [
            _case(f"{identifier}-{action.lower()}", _doc("  value: $.event.id", f"error_policy:\n  on_transformation_error: {action}\n  on_validation_failure: {action}\n  on_type_mismatch: {action}\noutput: FLAT_OBJECT\n"), "COMPILE_THEN_POLICY_CANARY")
            for action in ("FAIL_PIPELINE", "SKIP_RECORD", "REDACT_AND_PROCEED")
        ]
    if identifier == "output-shapes":
        return [_case(f"output-{shape.lower()}", _doc("  value: $.event.id", f"output: {shape}\n")) for shape in ("OBJECT", "JSON_STRING", "PRIMITIVE", "BYTES")]
    if identifier == "complex-type-modes":
        return [
            _case(f"complex-{mode.lower()}", _doc("  value: $.customer", f"output:\n  shape: FLAT_OBJECT\n  complexTypes: {mode}\n"), "COMPILE_THEN_POLICY_CANARY")
            for mode in ("JSON_STRING", "ERROR")
        ]
    raise CoverageOracleError(f"no compile probe cases for {identifier}")


def build_matrix(product_root: Path) -> OrderedDict[str, Any]:
    catalog = families()
    return OrderedDict(
        (
            ("formatVersion", 2),
            ("oracle", "current product compiler definitions and all-operations equivalence test"),
            ("productRootReadOnly", str(product_root.resolve())),
            ("provenance", provenance(product_root)),
            ("familyCount", len(catalog)),
            ("families", catalog),
            ("claimBoundary", "MEASURED_VALID_MAPPING means exercised by the valid population; CANARY and COMPILE_PROBE evidence is never reported as 500K measured coverage."),
        )
    )
