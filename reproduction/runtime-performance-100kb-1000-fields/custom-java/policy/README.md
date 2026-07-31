# Custom Java policy parity gate

This directory is benchmark-only. It does not modify or link production source
and it never publishes records.

The gate derives expected transform results from the exact FlowPlane Core
artifact and immutable hard mapping
`007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31`.
Six 100 KiB canaries exercise required, validation, type mismatch, lookup miss,
overflow, and malformed-JSON transformation-error behavior.

## Required comparison

Each custom-runtime response is compared with ordered keys and exact values:

- status and output bytes;
- every governed-core field error, in mapping evaluation order;
- the HTTP status/result header and normalized error-envelope semantics;
- the gRPC-compatible `TransformError` projection;
- the gRPC-compatible per-record `DlqEnvelope`;
- Kafka key bytes;
- Kafka header name order, duplicates, and value bytes.

The custom runtime must preserve Kafka keys and headers on both output and DLQ
delivery. The test includes duplicate header names, arbitrary binary bytes, an
empty value, and UTF-8.

HTTP error envelopes contain a generated error ID and timestamp. Those two
values cannot be byte-equal across executions. HTTP equivalence is therefore
defined semantically: ordered field errors, grouped error code/message, source
coordinates, artifact/runtime coordinates, policy action, and redacted payload
rules must match; generated ID and timestamp are validated by shape when the
HTTP projection is exercised. Valid transformed output remains byte-for-byte.

The measured 500,000-record run is not allowed to start until
`parityState` is `PROVEN`. This state is a correctness prerequisite, not a
performance pass/fail verdict.
