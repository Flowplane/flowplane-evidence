# Flowplane evidence release 2026.07.3

This release adds the isolated 100 KB / 1,000-field runtime performance evidence
captured on 2026-07-31. Existing 2026.07.2 evidence remains preserved with its
original claim-level source revisions.

## Added observations

| Campaign | Preserved observation | Status |
|---|---|---|
| Live HTTP | 500,000 input/output, zero DLQ/final lag, 186.767 records/s | `MEASURED` |
| Live gRPC streaming | 500,000 responses, zero DLQ/failures, 1,314.523 records/s | `MEASURED` |
| Mapping-specific custom Java | 500,000 input/output, 141.080 records/s | `MEASURED` |
| HTTP batch 10 | 10,000 input/output, 142.811 records/s | `MEASURED` |
| HTTP batch 50 | 10,000 input/output, 141.400 records/s | `MEASURED` |

All campaigns used 100 deterministic variants of exactly 102,400 bytes and the
same 1,000-field mapping SHA-256
`007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31`.
The custom implementation matched all 100 valid variants and six policy/error
cases byte-for-byte before its live observation.

## Interpretation boundaries

- No performance pass/fail threshold was applied.
- HTTP, gRPC, and custom Java use different topologies and are not a protocol leaderboard.
- Transform-only and transport end-to-end latency remain separate.
- Process allocation values are estimates; incomplete component coverage is not called whole-stack B/op.
- Batch size 10 versus 50 has one observation per size and is exploratory.
- No manual downstream transformed insertion was used.

The Flowplane capture used commit
`107d4b18d76c2ef5db5578be0f74c315200ee265` with a disclosed dirty worktree.
Redpanda Connect reported 4.96.1, but its capture used a mutable `latest` tag.

Start with [`evidence/runtime-performance-100kb-1000-fields/README.md`](../../evidence/runtime-performance-100kb-1000-fields/README.md)
and validate the release with `python scripts/validate-evidence.py`.
