# gRPC streaming 500,000-record live observation

Campaign `grpc-20260730-2317` sent the frozen workload directly through the live
`GRPC_STREAM` sidecar using an isolated Java bidirectional-stream client:

```text
Observation client → Flowplane gRPC runtime → response stream
```

Kafka and Redpanda Connect were not inserted into this path. Responses were
observed and discarded. No downstream publisher or manual transformed insertion
existed.

## Accounting and throughput

| Metric | Observation |
|---|---:|
| Sent / responses | 500,000 / 500,000 |
| Runtime OK / DLQ / failed | 500,000 / 0 / 0 |
| Batch size | 10 |
| Bidirectional streams | 16 |
| Maximum in-flight batches | 256 |
| Elapsed | 380.366 s |
| Throughput | 1,314.523 records/s |
| Input | 51.2 GB |
| Transformed output | 23.594 GB |

## Latency

| Boundary | p50 | p95 | p99 | p999 | Max |
|---|---:|---:|---:|---:|---:|
| Transform-only | 0.4646 ms | 0.7419 ms | 1.3203 ms | 3.6224 ms | 5.4619 ms |
| Source send to runtime response | 262.786 ms | 340.473 ms | 397.863 ms | 474.932 ms | 716.644 ms |

The end-to-end distribution contains 50,000 batch samples. Every record in a
batch shares its batch latency.

## Allocation and resources

- Transform-only p50: 419,232 B/op.
- Runtime JFR estimate: 725,247,265,616 bytes, or 1,450,494.531 B/record.
- Client JFR estimate: 26,848,458,296 bytes, or 53,696.917 B/record.
- The cross-process sum is an estimate from independently windowed recordings,
  not an exact allocator counter.
- Runtime CPU averaged 189.28% and peaked at 233.41% across 33 Docker samples.
- Last observed runtime memory was 1.344 GiB.

Variant 0 produced 46,995 bytes with SHA-256
`db1437054f8f166b4755f86451850b9b5bf9127a8c9b9bb83ad1f758a1b62bfd`,
matching the governed-core calibration output. A separate 100-record policy
canary produced 20 OK, 80 DLQ, and zero failed responses.

Status: `MEASURED`. No performance threshold or pass/fail verdict applied. See
[`result.json`](result.json) and the shared [methodology](../../methodology.md).
