# HTTP native batch size 10 observation

Campaign `http-batch-20260731-1305` used Redpanda Connect 4.96.1 to form native
count batches of 10 and call Flowplane `/v1/transform:batch`. Four bridge threads
unarchived runtime results to campaign-scoped Kafka output or DLQ topics. The tool
performed no mapping transformations, and no transformed records were inserted
manually.

| Metric | Observation |
|---|---:|
| Warmup / measured | 1,000 / 10,000 records |
| Measured input / output / DLQ | 10,000 / 10,000 / 0 |
| Publisher elapsed | 70.023 s |
| Publisher throughput | 142.811 records/s |
| Transform-only p50 / p95 / p99 | 0.5562 / 1.4848 / 2.3082 ms |
| Kafka-to-output p50 / p95 / p99 / max | 46 / 71 / 82 / 141 ms |
| Transform-only allocation | 419,096 B/op |

The Kafka observer matched 1,000 samples and retained one negative timestamp
correlation. Runtime Docker CPU averaged 41.12% and memory averaged 486.88 MiB.
Redpanda Connect CPU averaged 36.91% and memory averaged 82.05 MiB.

Status: `MEASURED`, exploratory. See [`result.json`](result.json).
