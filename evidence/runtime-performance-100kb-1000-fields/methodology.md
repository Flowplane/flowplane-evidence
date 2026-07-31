# Live multi-process runtime measurement methodology

This methodology extends the repository's controlled benchmark protocol for
live, multi-process runtime campaigns. It separates correctness accounting from
performance observation. A completed campaign can be both live-local verified
at the processing boundary and measured without having a performance pass/fail
threshold.

## Measurement boundaries

| Boundary | Starts | Ends | Valid interpretation |
|---|---|---|---|
| Transform-only | Immediately before compiled mapping execution | Immediately after owned output or governed error result | Mapping engine cost for the frozen fixture |
| Runtime request | Runtime transport receives a request | Runtime transport emits its response | Runtime wrapper plus mapping execution |
| Kafka-to-output | Timestamp on the raw input record | Timestamp on the correlated runtime-derived output | Broker, bridge, runtime, batching, and output publication |
| gRPC send-to-response | Observation client submits a batch | The matching runtime response arrives | Client, transport, runtime, flow control, and response delivery |

Every record in a gRPC batch inherits its batch latency. Rolling runtime UI
percentiles are reported as ranges of windows and are not merged into a synthetic
record-level distribution.

## Correctness and provenance

The measured publisher may address only the input boundary. Runtime output and
DLQ destinations are written by the deployed runtime or its transport bridge
after receiving the runtime response. The verifier requires exact input,
output/DLQ, and final-lag accounting. Policy canaries are separate from the valid
500,000-record measured corpus.

The benchmark records no performance verdict. `MEASURED` means the observation
completed and the numeric evidence is preserved. `LIVE_LOCAL_VERIFIED` applies
to separately stated correctness and provenance claims.

## Allocation scopes

- Transform B/op uses exact thread-allocation sampling around governed-core
  operations.
- JVM process B/op uses weighted JFR `ObjectAllocationSample` estimates divided
  by measured records in the aligned observation window.
- Redpanda Connect allocation uses the tool's process/runtime metrics when
  available.
- Producer and broker estimates include their own background allocation.

Independent process estimates may be shown side by side. They are not an exact
allocator counter and must not be added into a value labelled "whole stack" when
the payload renderer, feeder, Docker engine, operating system, or another required
component is uninstrumented. Docker RSS is not converted to B/op.

## Correlation quality

Kafka latency observers retain and count negative timestamp correlations instead
of silently clamping or deleting them. Such samples indicate clock or timestamp
quality limitations. Batch-10 retained one negative correlation and batch-50
retained four. The 500,000-record HTTP run retained none in its 1,000 matched
samples.

## Comparison rules

- Compare throughput only with the topology and publisher boundary attached.
- Do not rank transform-only percentiles against transport end-to-end latency.
- Do not compare means with percentiles as if they were equivalent statistics.
- Treat the custom Java comparison as a mapping-specific counterfactual, not a
  generic Java or zero-copy product benchmark.
- Treat the batch-size comparison as exploratory because only one observation
  per size was preserved.
- Treat UI telemetry as corroborating operational evidence, not the source of
  benchmark truth.

## Reproduction limitations

The captured Flowplane repository was at commit
`107d4b18d76c2ef5db5578be0f74c315200ee265` with a dirty worktree. The campaign
preserved status and tracked-diff hashes, but the public repository does not
contain the private product diff. Redpanda Connect reported version 4.96.1, while
the captured configuration used the mutable tag `redpandadata/connect:latest`.
Future reproduction must pin an immutable image digest.
