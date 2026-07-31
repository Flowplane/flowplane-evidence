# HTTP native batch size 10 versus 50

The two exploratory campaigns used the same mapping hash, payload corpus,
10,000-record measured count, four Redpanda Connect threads, runtime batch
endpoint, and policy behavior. The single intended change was native batch count.

| Metric | Batch 10 | Batch 50 | Observation |
|---|---:|---:|---|
| Throughput | 142.811 records/s | 141.400 records/s | Batch 50 was 0.988% lower |
| Kafka-to-output p50 | 46 ms | 56 ms | Higher at 50 |
| Kafka-to-output p95 | 71 ms | 95 ms | Higher at 50 |
| Kafka-to-output p99 | 82 ms | 681 ms | Higher at 50 |
| Kafka-to-output max | 141 ms | 1,420 ms | Higher at 50 |
| Transform-only p99 | 2.3082 ms | 1.0943 ms | Lower at 50 |
| Negative timestamp correlations | 1 | 4 | Retained and flagged |

In these observations, increasing the batch count did not increase publisher
throughput and coincided with a much larger Kafka-to-output tail. Transform-only
p99 moved in the opposite direction, reinforcing why engine and pipeline latency
must remain separate.

This is one observation per size. It is not a statistically qualified tuning
recommendation. Repeat randomized trials before selecting a production batch
size from these results.
