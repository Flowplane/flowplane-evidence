# Isolated gRPC observation client

This client drives the live FlowPlane `GRPC_STREAM` runtime using only the 100 source payload variants in `../workload/generated/valid-payloads-100kb.jsonl`. It belongs to the isolated benchmark tree and has no Kafka, Redpanda, Spark, database, or production-code dependency. Generate the ignored corpus first with `python ..\workload\workload.py generate`.

## Measurement model

- Multiple bidi streams provide controlled concurrency (`--streams`, default 4).
- The fetched runtime assignment must exactly match the expected runtime, mapping, artifact ID, and artifact hash before traffic. The endpoint omits transport, so `GRPC_STREAM` is bound from the controller's previously verified setup/control-plane evidence.
- A global semaphore bounds outstanding batches (`--max-inflight-batches`, default 128).
- Responses are counted in the callback and immediately released. They are never accumulated or republished.
- A fixed-size reservoir records response latency percentiles. A bounded JSONL sample records only batch metadata plus one output hash and size every 100 batches.
- Response latency is correlated end to end from source batch submission to runtime response. Every record in that response receives the batch latency; the report states this semantic explicitly.
- Sender-thread allocation captures request construction plus gRPC submission bytes per source record.
- JFR spans the full measured client JVM interval. `Export-GrpcJfrEvidence.ps1` creates the full-process allocation estimate and B/op evidence.
- Reports use `observationMode: PERFORMANCE_MONITORING_ONLY`. They contain no performance status, target-met field, or pass/fail gate. Counts and RPC errors are factual observations.

The transformed response is the terminal output of this benchmark path. There is intentionally no downstream publisher.

## Bounded parity evidence

For a policy canary of at most 1,000 records, pass `-ParityEvidencePath` to the
launcher. This writes one compact JSONL row per runtime result containing the
record status, headers, output bytes/hash/base64, complete `TransformError`, and
normalized `DlqEnvelope`. The launcher rejects this option for larger runs and
refuses to overwrite an existing evidence file. It is for parity certification,
not the 500,000-record measured campaign.

## Build and test

```powershell
Set-Location .\grpc-client
.\test.ps1
.\build.ps1
```

The runtime contract is consumed from the local Maven repository. This module does not compile or modify the production repository.

## Plan first

Without `-Execute`, the launcher writes and prints the exact plan but sends no traffic:

```powershell
.\grpc-client\Invoke-GrpcObservedClient.ps1 `
  -CampaignId grpc-YYYYMMDD-HHMM `
  -RuntimeId 'runtime-id-from-setup' `
  -MappingId 'mapping-id-from-setup' `
  -ArtifactId 'artifact-id-from-setup' `
  -ArtifactHash 'sha256:...' `
  -Target '127.0.0.1:19090' `
  -AssignmentUrl 'http://127.0.0.1:18090/v1/runtime/assignments'
```

The deployment-specific control-plane controller used by the original campaign
is not included in this public package. Create and verify the runtime assignment
through the existing stack first, then pass its exact runtime, mapping, artifact,
target, and assignment values to this launcher. The launcher creates no Compose
file and never republishes a transformed response.

The live controller must add `-Execute -Confirm:$false` only after the HTTP campaign is finalized and the live gRPC runtime assignment is verified in the UI. Tune speed with `BatchSize`, `Streams`, and `MaxInflightBatches`; change one dimension at a time and retain the generated plan with each run.

After the client finishes:

```powershell
.\grpc-client\Export-GrpcJfrEvidence.ps1 `
  -CampaignId grpc-YYYYMMDD-HHMM `
  -ArtifactHash 'sha256:...' `
  -RunDirectory '.\results\grpc-YYYYMMDD-HHMM\observed-grpc-run'
```
