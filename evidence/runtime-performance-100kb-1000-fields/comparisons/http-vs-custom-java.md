# Flowplane HTTP versus mapping-specific custom Java

This is an observational counterfactual, not a winner verdict. Both campaigns
used the same 100 exact-size payload variants and the same 1,000-field mapping.
Valid output matched byte-for-byte for all 100 variants, and six policy/error
cases matched byte-for-byte before the live runs.

| Metric | Flowplane HTTP | Custom Java | Custom versus HTTP |
|---|---:|---:|---:|
| Measured input/output | 500,000 / 500,000 | 500,000 / 500,000 | — |
| DLQ / final lag | 0 / 0 | 0 / 0 | — |
| Publisher elapsed | 2,677.128 s | 3,544.097 s | +32.38% |
| Publisher throughput | 186.767 records/s | 141.080 records/s | -24.46% |
| Runtime allocation estimate | 864,950.590 B/op | 446,297.633 B/op | -48.40% |
| Available-component allocation subtotal | 1,745,858.784 B/op | 1,226,895.802 B/op | -29.73% |

The throughput observation favors Flowplane HTTP in these runs. The allocation
observation favors the custom runtime at the measured JVM boundary. Neither
supports a universal conclusion because the topologies differ:

```text
Flowplane: Kafka → Redpanda Connect HTTP bridge → Flowplane runtime → Kafka
Custom:    Kafka → mapping-specific custom Java runtime → Kafka
```

Only Flowplane HTTP preserved correlated Kafka-to-output latency. Transform
statistics are also incompatible: Flowplane preserved transform-only percentiles,
while custom Java preserved a mean across warmup plus measured traffic.

The custom comparison required 2,506 inspected nonblank physical lines across production
Java, tests, a policy oracle, and the PowerShell campaign harness. That count
shows the implementation burden of this exact counterfactual. It does not prove
that every Flowplane mapping saves the same number of lines, engineering hours,
or dollars.

See the [HTTP run](../runs/http-500k/summary.md), [custom run](../runs/custom-java-500k/summary.md),
and shared [methodology](../methodology.md).
