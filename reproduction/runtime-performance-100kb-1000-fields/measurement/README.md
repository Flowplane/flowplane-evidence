# Isolated JFR evidence exporter

This benchmark-only module converts a Java Flight Recorder file into bounded,
machine-readable allocation evidence. It is standalone Java 17 code with no
Flowplane product or third-party dependency.

Only three Java sources are included: the streaming JFR allocation summarizer,
its small JSON writer, and the allocation workload used by the smoke test. The
summarizer reads one event at a time and never retains the recording in memory.
Weighted `jdk.ObjectAllocationSample` bytes are estimates, not exact allocator
counters. A recording without those events reports `state: unavailable` rather
than zero allocation.

## Export a recording

```powershell
.\export-jfr-evidence.ps1 `
  -CampaignId grpc-001 `
  -RuntimeType GRPC `
  -ArtifactHash 'sha256:published-artifact-hash' `
  -Recording C:\bench\grpc-001\grpc-client.jfr `
  -OutputDirectory C:\bench\grpc-001\jfr-evidence `
  -WindowStart '2026-07-31T16:00:00Z' `
  -WindowEnd '2026-07-31T17:00:00Z' `
  -MeasuredOperations 500000
```

The exporter writes `jfr-summary.txt`, `jfr-allocation-summary.json`, and
`jfr-evidence-manifest.json`. Window bounds are optional but must be supplied
together. Bytes per operation are emitted only when an exact operation count is
provided.

## Verify from a clean checkout

```powershell
.\Test-CleanCheckout.ps1
```

The test copies only this module's source and scripts into a new temporary
directory, compiles them, records a short allocation workload, invokes the public
exporter, and validates all three outputs. Generated artifacts stay under the
ignored `build/` directory and the temporary checkout is removed after success.
