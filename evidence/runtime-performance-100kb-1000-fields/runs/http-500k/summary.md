# HTTP 500,000-record live observation

Campaign `hard-http-20260731-0805` processed the frozen 100 KB / 1,000-field
workload through this topology:

```text
Kafka input → Redpanda Connect HTTP bridge → Flowplane HTTP runtime → Kafka output/DLQ
```

The input publisher could write only to the campaign input topic. Redpanda
Connect published output or DLQ records only after the live runtime returned a
response. No transformed records were inserted manually.

## Accounting and throughput

| Metric | Observation |
|---|---:|
| Measured input | 500,000 |
| Runtime-derived output | 500,000 |
| DLQ | 0 |
| Final consumer lag | 0 |
| Input bytes | 51.2 GB |
| Publisher elapsed | 2,677.128 s |
| Publisher throughput | 186.767 records/s |

## Latency

| Boundary | p50 | p95 | p99 | Max |
|---|---:|---:|---:|---:|
| Governed-core transform-only | 0.523 ms | 1.592 ms | 2.202 ms | 4.664 ms |
| Kafka input timestamp to derived output timestamp | 14 ms | 26 ms | 54 ms | 3,086 ms |

The Kafka latency observer matched all 1,000 requested samples and retained no
negative timestamp correlations. Live runtime telemetry consisted of 160 rolling
windows, not a single merged record histogram: p50 ranged 1.053–2.205 ms, p95
1.621–7.127 ms, and p99 3.252–17.766 ms.

## Allocation and resources

Transform-only sampling observed 419,144 B/op at p50, p95, and p99. Process
estimates were 864,950.590 runtime JVM B/op, 611,664.534 producer JVM B/op,
200,098.992 shared-broker JVM B/op, and 69,144.668 bridge B/op.

Their 1,745,858.784 B/op subtotal is incomplete. The Python renderer, stdin
feeder, Docker client/engine, operating system, and other required components
were not all allocation-instrumented.

The runtime averaged 62.97% CPU and 565.27 MiB, peaking at 120.04% CPU and
674.60 MiB. The bridge averaged 44.34% CPU and 85.61 MiB, peaking at 82.36%
CPU and 97.69 MiB.

## Interpretation

Status: `MEASURED`. The campaign completed exact accounting, policy-canary, UI,
and evidence gates, but no performance threshold or pass/fail verdict applied.
See [`result.json`](result.json) and the shared [methodology](../../methodology.md).
