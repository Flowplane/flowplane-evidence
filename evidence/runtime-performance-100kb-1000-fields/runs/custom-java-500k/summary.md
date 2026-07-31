# Mapping-specific custom Java 500,000-record observation

Campaign `custom-java-20260731-0937` preserved a hand-written Java
counterfactual for the exact frozen mapping:

```text
Kafka input → mapping-specific custom Java runtime → Kafka output/DLQ
```

This code is not a generic JSON tool and is not zero-copy. It implements this
particular mapping, error envelope, Kafka key, and ordered-header behavior.

## Parity

- All 100 valid payload variants matched Flowplane output byte-for-byte.
- Six error/policy cases matched byte-for-byte.
- Ordered field errors, HTTP error semantics, transformation errors, DLQ
  envelopes, Kafka keys, and ordered headers were compared.
- The 500,000-record traffic used only valid variants; zero live DLQ does not
  independently re-prove error-policy parity.

## Measured observation

| Metric | Observation |
|---|---:|
| Input / output / DLQ | 500,000 / 500,000 / 0 |
| Final lag | 0 |
| Input bytes | 51.2 GB |
| Publisher elapsed | 3,544.097 s |
| Publisher throughput | 141.080 records/s |
| Runtime transform mean | 1.180 ms/record |

The transform accumulator covered 510,000 warmup-plus-measured records and did
not preserve percentiles. It is not scope-equivalent to Flowplane's separate
10,000-operation transform-only calibration.

## Allocation and implementation size

The custom runtime JFR estimate was 446,297.633 B/op. Producer and broker
estimates were 595,494.094 and 185,104.075 B/op. Their 1,226,895.802 B/op
subtotal is incomplete for the same reasons documented in the shared methodology.

The preserved counterfactual contains 1,237 physical lines of production Java,
137 nonblank lines of Java tests, 147 nonblank lines of policy-oracle Java, and
985 nonblank lines of PowerShell campaign harness: 2,506 nonblank physical lines in the inspected comparison
implementation and harness. This is an implementation-size observation, not a
universal LOC-savings claim.

Status: `MEASURED`; parity is separately `CONTRACT_VERIFIED`. See
[`result.json`](result.json) and the [comparison](../../comparisons/http-vs-custom-java.md).
