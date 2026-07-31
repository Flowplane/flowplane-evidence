# HTTP native batch size 50 observation

Campaign `http-batch50-20260731-0915` changed only the Redpanda Connect native
batch count from 10 to 50. It retained four bridge threads, the same payload and
mapping hashes, the same runtime batch endpoint, and the same policy behavior.

| Metric | Observation |
|---|---:|
| Warmup / measured | 1,000 / 10,000 records |
| Measured input / output / DLQ | 10,000 / 10,000 / 0 |
| Publisher elapsed | 70.721 s |
| Publisher throughput | 141.400 records/s |
| Transform-only p50 / p95 / p99 | 0.4349 / 0.7052 / 1.0943 ms |
| Kafka-to-output p50 / p95 / p99 / max | 56 / 95 / 681 / 1,420 ms |
| Transform-only allocation | 419,128 B/op |

The Kafka observer matched 1,000 samples and retained four negative timestamp
correlations. Runtime Docker CPU averaged 35.37% and memory averaged 613.19 MiB.
Redpanda Connect CPU averaged 33.33% and memory averaged 96.41 MiB.

Status: `MEASURED`, exploratory. One observation cannot establish a general
batch-size optimum. See [`result.json`](result.json).
