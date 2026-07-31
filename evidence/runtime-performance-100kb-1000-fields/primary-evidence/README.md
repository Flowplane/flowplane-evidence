# Primary run evidence

This directory contains the compact, sanitized primary artifacts behind the
published runtime-performance summaries. Files retain their original benchmark
JSON content; directory separators in original relative paths are represented
as `--` in filenames.

The `http-hard-500k` directory is the primary campaign behind the published
186.767 records/s HTTP result; `http-500k` retains the earlier 151.509 records/s
rerun as corroborating historical evidence, not as the source of that claim.
The remaining directories cover the gRPC 500,000-record run, custom Java
500,000-record comparison, and the HTTP batch-size 10 and 50 10,000-record
observations. Depending on the runtime, the retained artifacts
include source-publisher manifests, correlated latency observations, runtime
output provenance, assignment/setup evidence, JFR allocation summaries,
whole-stack allocation reports, transform-only measurements, UI-verification
records, and UI screenshots.

Raw JFR recordings and full logs are intentionally omitted because they are
large and may contain host-specific paths. Their sanitized analyzer outputs and
hash-bearing evidence manifests are retained here. The aggregate summaries must
not be used to infer a metric that is absent from these primary artifacts.
