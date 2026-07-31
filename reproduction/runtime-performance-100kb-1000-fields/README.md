# Reproduce the 100 KB / 1,000-field runtime workload

This package contains benchmark-only fixtures and clients from the isolated
HTTP/gRPC campaign. It is not Flowplane production source and does not create a
Docker Compose stack. Supply an already running Flowplane stack and use unique,
campaign-scoped Kafka topics and container labels.

## What is included

- [`mapping/mapping.dsl`](mapping/mapping.dsl): the exact synthetic 1,000-field mapping.
- [`workload/workload.py`](workload/workload.py): deterministic 100-variant payload generator and validator.
- [`workload/publisher/publisher.py`](workload/publisher/publisher.py): input-only Kafka publisher.
- [`grpc-client/`](grpc-client/): isolated Java bidirectional-stream observation client.
- [`custom-java/`](custom-java/): mapping-specific comparison implementation and parity tests.
- [`generate_mapping_breakdown.py`](generate_mapping_breakdown.py): produces the public 1,000-row field inventory.

Generated payloads are intentionally omitted because the 100-record JSONL corpus
is approximately 10 MB. Regenerate it and require SHA-256
`ba3fc084ce067c2ef6b52b7326760889b492e6ad8dc553a0a2aecf4bf0c7a607`.
Generated files are written under `workload/generated/` and ignored by Git.

## Validate the workload

From this directory:

```powershell
python .\workload\workload.py generate
python .\workload\workload.py validate
python -m unittest discover .\workload\tests -v
python -m unittest discover .\workload\publisher\tests -v
python .\generate_mapping_breakdown.py `
  .\mapping\mapping.dsl `
  ..\..\evidence\runtime-performance-100kb-1000-fields\operations-breakdown.csv
```

The mapping must hash to
`007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31`
and expose exactly 1,000 output fields.

## Build the gRPC observation client

```powershell
Set-Location .\grpc-client
.\test.ps1
.\build.ps1
```

The client measures source-send to runtime-response latency. Every record in a
batch shares the batch latency. Responses are observed and discarded; the client
does not publish transformed output downstream.

## Verify the custom Java counterfactual

```powershell
Set-Location .\custom-java
mvn test
python .\policy\policy_gate.py --help
```

The custom implementation is mapping-specific, materializes output bytes, and is
not a zero-copy tool. Its source is preserved to make the engineering-effort and
parity comparison inspectable.

## Execute against a live stack

Copy [`public-config.example.json`](public-config.example.json), replace every
placeholder, pin image references by digest, and keep the configuration outside
version control. The original campaign controller is not published because it
contains workstation- and deployment-specific control-plane orchestration. The
portable contract is:

1. Register one runtime through the control plane.
2. Publish and assign the exact mapping hash.
3. Verify the active assignment hash in the runtime and UI.
4. Publish raw records only to the input boundary.
5. Let the runtime or its transport bridge create output and DLQ records.
6. Capture transform-only, request/end-to-end latency, JFR allocation, Docker
   resources, record accounting, policy canaries, and UI telemetry.
7. Remove only exact campaign-labelled topics and containers; retain evidence.

See the [measurement methodology](../../evidence/runtime-performance-100kb-1000-fields/methodology.md)
before comparing results. HTTP and gRPC use different transport topologies and
must not be ranked as if they were the same end-to-end boundary.
