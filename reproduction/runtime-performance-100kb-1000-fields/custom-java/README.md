# Custom Java JSON runtime

This is an isolated benchmark competitor for the exact hard mapping whose SHA-256 is
`007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31`.
It is not product code and does not call FlowPlane transformation classes.

The runtime uses Jackson's streaming parser, a fixed-schema context, and an ordered
UTF-8 writer. It never builds a JSON tree or a `Map`. Wide-field token text is read
from Jackson's parser character buffer and written immediately, so the 923 wide
values are not retained as Java objects.

This is allocation-minimized, not literally zero-copy. Kafka clients allocate,
Jackson decodes JSON strings, SHA-256 creates digest arrays, and the transformed
record requires a new output byte array.

Build and run the offline parity test:

```powershell
mvn -q test
mvn -q package -DskipTests
```

Generate the shared deterministic workload first from the benchmark package root:

```powershell
python .\workload\workload.py generate --output-dir .\workload\generated
```

The test asserts all 100 valid 102,400-byte variants against the governed
FlowPlane oracle byte-for-byte. Policy parity is separately gated by:

```powershell
.\New-ValidParityEvidence.ps1
.\policy\Invoke-PolicyParityGate.ps1 -Action Prepare `
  -WorkDirectory .\policy\generated `
  -ArtifactClasspath <exact-published-flowplane-core-jar-and-runtime-dependencies>
```

`Prepare` is the only prerequisite that needs the separately built, exact
published FlowPlane Core artifact. The artifact is referenced from the local
build/Maven cache; no production source or binary is copied into this package.
After preparation, run the isolated competitor and verify the six policy
canaries:

```powershell
.\policy\Invoke-PolicyParityGate.ps1 -Action Verify `
  -WorkDirectory .\policy\generated `
  -CompetitorJar .\target\custom-java-json-runtime.jar
```

Finally, generate or independently audit
`policy\generated\custom-java-artifact-audit.json` for the just-built JAR. The
campaign controller validates that audit, both parity evidence files, and every
current hash before `Plan` or `Run`. Generated policy material is intentionally
ignored because it is artifact-specific and must be recreated for each build.

The parity CLI contract is line-delimited JSON:

```text
java -jar target/custom-java-json-runtime.jar parity \
  --mapping <mapping.dsl> --requests <requests.jsonl> --responses <responses.jsonl>
```

It preserves key bytes, ordered duplicate headers, and source coordinates. Its
response contains the ordered field errors plus normalized HTTP, TransformError,
and DLQ projections consumed by the policy gate.

The JVM supports standard JFR startup flags, for example:

```powershell
java -XX:StartFlightRecording=filename=custom-java.jfr,settings=profile,dumponexit=true `
  -jar target/custom-java-json-runtime.jar kafka ...
```

For a self-contained offline JFR smoke run:

```powershell
.\Invoke-OfflineParityJfr.ps1
```

No Docker Compose file is provided. Live execution is intentionally delegated to
the isolated campaign controller:

```powershell
.\Invoke-CustomJavaCampaign.ps1 -Action Plan -CampaignId custom-java-500k-next
```

`Run` is fail-closed: both valid-byte and policy parity evidence must be
`PROVEN`, their current artifact hashes must match, no other campaign lock may
exist, and `-Execute -ConfirmCampaignId <exact-id>` is required. The controller
uses the existing Docker network and Kafka container, creates only exact
campaign-scoped topics, publishes the standard 500,000 records through the raw
topic, and lets the runtime alone produce output/DLQ records.

It records runtime and source-producer JFR, five-second Docker stats, transform
nanoseconds, publisher evidence, topic end offsets, group lag, runtime logs,
container exit code, and artifact provenance. `CleanupPlan` and `Cleanup`
preserve reports while targeting only the exact labeled container, three topics,
consumer group, and matching global lock.

The live methodology runs a 10,000-record warmup first, using the same 100
payloads and ASCII decimal-sequence Kafka keys. It waits for those records to
reach output/DLQ, captures baseline offsets, then starts broker JFR and the
500,000-record measured publisher. The measured window records `startUtc`,
`publishEndUtc`, and `drainEndUtc`. Completion requires measured deltas of
exactly 500,000 input and 500,000 output plus DLQ records with zero committed
consumer lag. Broker and producer JFR exclude warmup; runtime JFR covers the
510,000-record process and is filtered later using the measured timestamps.
