#!/usr/bin/env python3
"""Observe sampled raw-to-output Kafka latency without consuming record values."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Iterable

from publisher import SAFE_ID, SAFE_TOPIC, PublisherError, sample_sequences

TIMESTAMP_AND_KEY = re.compile(
    rb"(?:CreateTime|LogAppendTime):(\d+).*?(\d+)\s*$"
)


def parse_metadata_line(line: bytes) -> tuple[int, int] | None:
    match = TIMESTAMP_AND_KEY.search(line.rstrip())
    if not match:
        return None
    return int(match.group(2)), int(match.group(1))


def retain_latest_timestamp(observed: dict[int, int], sequence: int, timestamp_ms: int) -> None:
    """Keep the later phase when duplicate keys arrive out of partition order."""
    observed[sequence] = max(observed.get(sequence, timestamp_ms), timestamp_ms)


def observe_topic(
    *, container: str, bootstrap: str, topic: str, max_messages: int,
    selected: set[int], timeout_ms: int,
) -> tuple[dict[int, int], int, int]:
    command = [
        "docker", "exec", container, "kafka-console-consumer",
        "--bootstrap-server", bootstrap, "--topic", topic,
        "--from-beginning", "--max-messages", str(max_messages),
        "--timeout-ms", str(timeout_ms),
        "--property", "print.timestamp=true",
        "--property", "print.key=true",
        "--property", "print.value=false",
    ]
    observed: dict[int, int] = {}
    parsed = 0
    with tempfile.TemporaryFile() as stderr_file:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=stderr_file)
        if process.stdout is None:
            process.kill()
            raise PublisherError("Kafka metadata consumer stdout was unavailable")
        for line in process.stdout:
            item = parse_metadata_line(line)
            if item is None:
                continue
            parsed += 1
            sequence, timestamp_ms = item
            # Warmup and measured publications reuse keys 0..999. Console-consumer
            # output across partitions is not globally ordered, so retain the
            # greatest timestamp rather than whichever duplicate is emitted last.
            if sequence in selected:
                retain_latest_timestamp(observed, sequence, timestamp_ms)
        code = process.wait(timeout=max(300, timeout_ms // 1000 + 60))
        stderr_file.seek(0)
        stderr = stderr_file.read().decode("utf-8", errors="replace")
    if code != 0:
        raise PublisherError(f"Kafka metadata consumer exited {code}: {stderr[-2000:]}")
    return observed, parsed, code


def percentile(values: list[int], fraction: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def summarize(raw: dict[int, int], output: dict[int, int], selected: Iterable[int]) -> dict:
    requested = list(selected)
    matched = [key for key in requested if key in raw and key in output]
    latencies = [output[key] - raw[key] for key in matched]
    negative = sum(1 for value in latencies if value < 0)
    nonnegative = [value for value in latencies if value >= 0]
    return {
        "sampleCountRequested": len(requested),
        "sampleCountMatched": len(matched),
        "sampleCountMissing": len(requested) - len(matched),
        "negativeLatencyCount": negative,
        "latencyMillis": {
            "min": min(nonnegative) if nonnegative else None,
            "p50": percentile(nonnegative, 0.50),
            "p95": percentile(nonnegative, 0.95),
            "p99": percentile(nonnegative, 0.99),
            "max": max(nonnegative) if nonnegative else None,
        },
        "samples": [
            {
                "sequence": key,
                "rawTimestampEpochMs": raw[key],
                "outputTimestampEpochMs": output[key],
                "latencyMillis": output[key] - raw[key],
            }
            for key in matched
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-id", required=True)
    parser.add_argument("--raw-topic", required=True)
    parser.add_argument("--output-topic", required=True)
    parser.add_argument("--total-topic-records", type=int, required=True)
    parser.add_argument("--measured-records", type=int, default=500_000)
    parser.add_argument(
        "--measurement-profile",
        choices=("standard-500k", "exploratory-10k"),
        default="standard-500k",
    )
    parser.add_argument("--samples", type=int, default=1_000)
    parser.add_argument("--kafka-container", default="flowplane-kafka")
    parser.add_argument("--kafka-bootstrap", default="kafka:9092")
    parser.add_argument("--timeout-ms", type=int, default=120_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not SAFE_ID.fullmatch(args.campaign_id):
        raise PublisherError("unsafe campaign ID")
    if not SAFE_ID.fullmatch(args.kafka_container):
        raise PublisherError("unsafe Kafka container")
    if not SAFE_TOPIC.fullmatch(args.raw_topic) or not SAFE_TOPIC.fullmatch(args.output_topic):
        raise PublisherError("unsafe Kafka topic")
    expected_measured = 500_000 if args.measurement_profile == "standard-500k" else 10_000
    if args.total_topic_records <= 0 or args.measured_records != expected_measured:
        raise PublisherError(
            f"latency observation profile {args.measurement_profile} requires exactly "
            f"{expected_measured} measured records"
        )
    selected_tuple = sample_sequences(args.measured_records, args.samples)
    selected = set(selected_tuple)
    raw, raw_parsed, _ = observe_topic(
        container=args.kafka_container, bootstrap=args.kafka_bootstrap,
        topic=args.raw_topic, max_messages=args.total_topic_records,
        selected=selected, timeout_ms=args.timeout_ms,
    )
    output, output_parsed, _ = observe_topic(
        container=args.kafka_container, bootstrap=args.kafka_bootstrap,
        topic=args.output_topic, max_messages=args.total_topic_records,
        selected=selected, timeout_ms=args.timeout_ms,
    )
    result = {
        "schemaVersion": 1,
        "kind": "flowplane-benchmark-kafka-end-to-end-latency",
        "campaignId": args.campaign_id,
        "runtimeType": "HTTP",
        "outcome": "OBSERVED",
        "measurement": "raw Kafka record timestamp to runtime-derived output Kafka record timestamp",
        "measurementProfile": args.measurement_profile,
        "measuredRecordCount": args.measured_records,
        "duplicateKeySelection": "maximum timestamp per sequence independently in raw and output topics",
        "topicRecordsScanned": {"raw": raw_parsed, "output": output_parsed},
        **summarize(raw, output, selected_tuple),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
