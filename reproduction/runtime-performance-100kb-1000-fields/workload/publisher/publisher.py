#!/usr/bin/env python3
"""Stream deterministic benchmark records to Kafka without corpus expansion.

Dry-run is the default and never starts Docker or opens a producer. Live publishing
requires both ``--execute`` and an exact campaign confirmation token.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO, Callable, Iterator

WORKLOAD_DIR = Path(__file__).resolve().parents[1]
if str(WORKLOAD_DIR) not in sys.path:
    sys.path.insert(0, str(WORKLOAD_DIR))

import workload

MODE_COUNTS = {"smoke": 1_000, "exploratory-warmup": 1_000, "warmup": 10_000, "exploratory": 10_000, "measured": 500_000}
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{2,62}$")
SAFE_TOPIC = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{2,248}$")
MAX_RATE = 1_000_000
MAX_LATENCY_SAMPLES = 10_000
DEFAULT_FIXTURE_PATH = WORKLOAD_DIR / "generated" / workload.PAYLOAD_FILE
PRODUCER_TUNING = {
    "compression.type": "lz4",
    "linger.ms": "10",
    "batch.size": "1048576",
    "buffer.memory": "268435456",
    "max.request.size": "2097152",
}


class PublisherError(RuntimeError):
    """Publisher configuration or execution failed a safety contract."""


@dataclass(frozen=True)
class ScheduleEntry:
    sequence: int
    variant_index: int


@dataclass(frozen=True)
class PublisherConfig:
    mode: str
    campaign_id: str
    topic: str
    count: int
    rate_per_second: int
    latency_sample_limit: int
    flush_every: int
    fixture_path: Path
    kafka_container: str = "flowplane-kafka"
    kafka_bootstrap: str = "kafka:9092"
    producer_jfr_output: Path | None = None
    publish_timeout_seconds: int = 7200


def schedule_entry(sequence: int, count: int) -> ScheduleEntry:
    if count <= 0:
        raise PublisherError("count must be positive")
    if sequence < 0 or sequence >= count:
        raise PublisherError(f"sequence must be in 0..{count - 1}")
    return ScheduleEntry(sequence, sequence % workload.PAYLOAD_COUNT)


def iter_schedule(count: int) -> Iterator[ScheduleEntry]:
    if count <= 0:
        raise PublisherError("count must be positive")
    for sequence in range(count):
        yield ScheduleEntry(sequence, sequence % workload.PAYLOAD_COUNT)


def validate_config(config: PublisherConfig) -> None:
    if config.mode not in MODE_COUNTS:
        raise PublisherError(f"unsupported mode: {config.mode}")
    if not SAFE_ID.fullmatch(config.campaign_id):
        raise PublisherError("campaign ID must be 3-63 lowercase letters, digits, or hyphens")
    if not SAFE_TOPIC.fullmatch(config.topic):
        raise PublisherError("topic contains unsafe characters or has an invalid length")
    if config.count <= 0:
        raise PublisherError("count must be positive")
    if config.mode == "measured" and config.count != workload.MEASURED_RECORDS:
        raise PublisherError("measured mode requires exactly 500000 records")
    if config.mode == "exploratory" and config.count != 10_000:
        raise PublisherError("exploratory mode requires exactly 10000 records")
    if config.mode == "exploratory-warmup" and config.count != 1_000:
        raise PublisherError("exploratory-warmup mode requires exactly 1000 records")
    if config.rate_per_second < 0 or config.rate_per_second > MAX_RATE:
        raise PublisherError(f"rate must be 0..{MAX_RATE}; zero means unthrottled")
    if not 1 <= config.latency_sample_limit <= MAX_LATENCY_SAMPLES:
        raise PublisherError(f"latency sample limit must be 1..{MAX_LATENCY_SAMPLES}")
    if not 1 <= config.flush_every <= 100_000:
        raise PublisherError("flush-every must be 1..100000")
    if not 60 <= config.publish_timeout_seconds <= 86_400:
        raise PublisherError("publish timeout must be 60..86400 seconds")
    if not config.fixture_path.is_file():
        raise PublisherError(f"fixture corpus does not exist: {config.fixture_path}")
    if not SAFE_ID.fullmatch(config.kafka_container):
        raise PublisherError("Kafka container name is unsafe")
    if not re.fullmatch(r"[A-Za-z0-9._-]+:[0-9]{2,5}", config.kafka_bootstrap):
        raise PublisherError("Kafka bootstrap must be host:port without shell syntax")
    if config.producer_jfr_output is not None and config.producer_jfr_output.exists():
        raise PublisherError(
            f"producer JFR output already exists: {config.producer_jfr_output}"
        )


def producer_jfr_container_path(config: PublisherConfig) -> str:
    return f"/tmp/flowplane-benchmark-producer-{config.campaign_id}.jfr"


def sample_sequences(count: int, limit: int) -> tuple[int, ...]:
    """Return deterministic, bounded indices including first and last."""
    if count <= 0 or limit <= 0:
        raise PublisherError("count and sample limit must be positive")
    if count <= limit:
        return tuple(range(count))
    if limit == 1:
        return (count - 1,)
    return tuple((index * (count - 1)) // (limit - 1) for index in range(limit))


def producer_command(config: PublisherConfig) -> list[str]:
    validate_config(config)
    command = [
        "docker",
        "exec",
        "-i",
    ]
    if config.producer_jfr_output is not None:
        recording_path = producer_jfr_container_path(config)
        command.extend(
            [
                "-e",
                (
                    "JAVA_TOOL_OPTIONS=-XX:StartFlightRecording="
                    f"name=flowplane_producer_{config.campaign_id.replace('-', '_')},"
                    "settings=profile,disk=true,dumponexit=true,maxsize=2g,"
                    f"filename={recording_path}"
                ),
            ]
        )
    command.extend([
        config.kafka_container,
        "kafka-console-producer",
        "--bootstrap-server",
        config.kafka_bootstrap,
        "--topic",
        config.topic,
        "--producer-property",
        "acks=all",
        "--producer-property",
        "enable.idempotence=true",
        "--producer-property",
        "max.in.flight.requests.per.connection=5",
    ])
    for name, value in PRODUCER_TUNING.items():
        command.extend(("--producer-property", f"{name}={value}"))
    command.extend([
        "--property",
        "parse.key=true",
        "--property",
        "key.separator=:",
    ])
    return command


def load_fixture_payloads(path: Path) -> tuple[bytes, ...]:
    records = tuple(path.read_bytes().splitlines())
    if len(records) != workload.PAYLOAD_COUNT:
        raise PublisherError(f"fixture corpus has {len(records)} records, expected {workload.PAYLOAD_COUNT}")
    invalid = [index for index, value in enumerate(records) if len(value) != workload.PAYLOAD_BYTES]
    if invalid:
        raise PublisherError(f"fixture records are not exactly {workload.PAYLOAD_BYTES} bytes: {invalid[:10]}")
    return records


def _payload(config: PublisherConfig, entry: ScheduleEntry, fixtures: tuple[bytes, ...] | None = None) -> bytes:
    corpus = fixtures if fixtures is not None else load_fixture_payloads(config.fixture_path)
    return corpus[entry.variant_index]


def _sample_descriptor(config: PublisherConfig, sequence: int) -> dict[str, Any]:
    entry = schedule_entry(sequence, config.count)
    payload = _payload(config, entry)
    return {
        "sequence": sequence,
        "variantIndex": entry.variant_index,
        "payloadBytes": len(payload),
        "payloadSha256": hashlib.sha256(payload).hexdigest(),
    }


def dry_run_manifest(config: PublisherConfig) -> dict[str, Any]:
    validate_config(config)
    samples = sample_sequences(config.count, min(config.latency_sample_limit, 10))
    return {
        "formatVersion": 1,
        "status": "DRY_RUN",
        "mutatedExternalState": False,
        "mode": config.mode,
        "campaignId": config.campaign_id,
        "topic": config.topic,
        "recordCountPlanned": config.count,
        "payloadBytesEach": workload.PAYLOAD_BYTES,
        "payloadBytesPlanned": config.count * workload.PAYLOAD_BYTES,
        "variantCount": workload.PAYLOAD_COUNT,
        "roundRobinCycles": config.count // workload.PAYLOAD_COUNT,
        "partialCycleRecords": config.count % workload.PAYLOAD_COUNT,
        "firstSequence": 0,
        "lastSequence": config.count - 1,
        "lastVariantIndex": (config.count - 1) % workload.PAYLOAD_COUNT,
        "ratePerSecond": config.rate_per_second,
        "estimatedMinimumSeconds": (
            config.count / config.rate_per_second if config.rate_per_second else None
        ),
        "producerCommand": producer_command(config),
        "producerTuning": PRODUCER_TUNING,
        "sampledPayloads": [_sample_descriptor(config, value) for value in samples],
        "latencySampleLimit": config.latency_sample_limit,
        "payloadSource": "immutable 100-record fixture corpus reused round-robin",
        "fixturePath": str(config.fixture_path.resolve()),
        "producerJfr": (
            {
                "enabled": True,
                "hostOutput": str(config.producer_jfr_output.resolve()),
                "containerRecording": producer_jfr_container_path(config),
                "scope": "kafka-console-producer JVM only",
            }
            if config.producer_jfr_output is not None
            else {"enabled": False}
        ),
    }


def _pace(
    sent: int,
    rate: int,
    started: float,
    clock: Callable[[], float],
    sleeper: Callable[[float], None],
) -> None:
    if rate <= 0:
        return
    due = started + sent / rate
    remaining = due - clock()
    if remaining > 0:
        sleeper(remaining)


def stream_records(
    config: PublisherConfig,
    sink: BinaryIO,
    *,
    clock: Callable[[], float] = time.perf_counter,
    sleeper: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    """Render and write one record at a time; memory is independent of count."""
    validate_config(config)
    selected = set(sample_sequences(config.count, config.latency_sample_limit))
    fixtures = load_fixture_payloads(config.fixture_path)
    latency_samples: list[dict[str, Any]] = []
    started = clock()
    sent = 0
    for entry in iter_schedule(config.count):
        _pace(sent, config.rate_per_second, started, clock, sleeper)
        record_started = clock()
        payload = _payload(config, entry, fixtures)
        if len(payload) != workload.PAYLOAD_BYTES:
            raise PublisherError(f"sequence {entry.sequence} rendered to {len(payload)} bytes")
        # The Kafka key is the measured sequence. It gives the downstream
        # runtime path a provenance/correlation identity without changing the
        # exactly-102400-byte record value delivered to the runtime.
        sink.write(str(entry.sequence).encode("ascii"))
        sink.write(b":")
        sink.write(payload)
        sink.write(b"\n")
        sent += 1
        if sent % config.flush_every == 0:
            sink.flush()
        elapsed_micros = max(0, round((clock() - record_started) * 1_000_000))
        if entry.sequence in selected:
            latency_samples.append(
                {
                    "sequence": entry.sequence,
                    "variantIndex": entry.variant_index,
                    "renderWriteMicros": elapsed_micros,
                    "payloadSha256": hashlib.sha256(payload).hexdigest(),
                }
            )
    sink.flush()
    elapsed = max(0.0, clock() - started)
    return {
        "formatVersion": 1,
        "status": "COMPLETE",
        "mode": config.mode,
        "campaignId": config.campaign_id,
        "topic": config.topic,
        "sentRecordCount": sent,
        "firstSequence": 0,
        "lastSequence": sent - 1,
        "lastVariantIndex": (sent - 1) % workload.PAYLOAD_COUNT,
        "payloadBytesEach": workload.PAYLOAD_BYTES,
        "payloadBytesSent": sent * workload.PAYLOAD_BYTES,
        "kafkaKey": "decimal measured sequence",
        "recordValueBytesEach": workload.PAYLOAD_BYTES,
        "feedElapsedSeconds": elapsed,
        "feedRecordsPerSecond": sent / elapsed if elapsed > 0 else None,
        "configuredRatePerSecond": config.rate_per_second,
        "payloadSource": "immutable 100-record fixture corpus reused round-robin",
        "fixturePath": str(config.fixture_path.resolve()),
        "latencySampleLimit": config.latency_sample_limit,
        "latencySamples": latency_samples,
    }


def execute(config: PublisherConfig) -> dict[str, Any]:
    validate_config(config)
    command = producer_command(config)
    recording_path = (
        producer_jfr_container_path(config)
        if config.producer_jfr_output is not None
        else None
    )
    if recording_path is not None:
        stale = subprocess.run(
            ["docker", "exec", config.kafka_container, "test", "-e", recording_path],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if stale.returncode == 0:
            raise PublisherError(
                f"producer JFR container recording already exists: {recording_path}"
            )
    with tempfile.TemporaryFile() as stderr_file:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=stderr_file)
        if process.stdin is None:
            process.kill()
            raise PublisherError("producer stdin was not available")
        completed = threading.Event()
        timed_out = threading.Event()

        def enforce_deadline() -> None:
            if not completed.wait(config.publish_timeout_seconds):
                timed_out.set()
                process.kill()

        watchdog = threading.Thread(target=enforce_deadline, name="publisher-deadline", daemon=True)
        watchdog.start()
        try:
            acknowledged_started = time.perf_counter()
            manifest = stream_records(config, process.stdin)
            process.stdin.close()
            remaining = max(
                1.0,
                config.publish_timeout_seconds - (time.perf_counter() - acknowledged_started),
            )
            code = process.wait(timeout=remaining)
            acknowledged_elapsed = max(0.0, time.perf_counter() - acknowledged_started)
            stderr_file.seek(0)
            stderr = stderr_file.read().decode("utf-8", errors="replace")
        except Exception as exc:
            if process.poll() is None:
                process.kill()
            process.wait()
            if timed_out.is_set():
                raise PublisherError(
                    f"Kafka publication exceeded {config.publish_timeout_seconds} seconds"
                ) from exc
            raise
        finally:
            completed.set()
            watchdog.join(timeout=1)
        if timed_out.is_set():
            raise PublisherError(
                f"Kafka publication exceeded {config.publish_timeout_seconds} seconds"
            )
    if code != 0:
        raise PublisherError(f"Kafka producer exited {code}: {stderr[-2000:]}")
    manifest["producerExitCode"] = code
    manifest["producerAcks"] = "all"
    manifest["producerIdempotence"] = True
    manifest["producerFlushConfirmedByExit"] = True
    manifest["elapsedSeconds"] = acknowledged_elapsed
    manifest["achievedRecordsPerSecond"] = (
        manifest["sentRecordCount"] / acknowledged_elapsed
        if acknowledged_elapsed > 0
        else None
    )
    manifest["throughputSemantics"] = "stdin feed start through acks=all producer exit"
    manifest["producerTuning"] = PRODUCER_TUNING
    if recording_path is not None and config.producer_jfr_output is not None:
        output = config.producer_jfr_output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        copied = subprocess.run(
            ["docker", "cp", f"{config.kafka_container}:{recording_path}", str(output)],
            check=False,
            capture_output=True,
            text=True,
        )
        if copied.returncode != 0:
            raise PublisherError(
                f"producer JFR copy failed: {copied.stderr[-2000:]}"
            )
        if not output.is_file() or output.stat().st_size == 0:
            raise PublisherError(f"producer JFR is missing or empty after copy: {output}")
        cleanup = subprocess.run(
            ["docker", "exec", config.kafka_container, "rm", "-f", "--", recording_path],
            check=False,
            capture_output=True,
            text=True,
        )
        if cleanup.returncode != 0:
            raise PublisherError(
                f"producer JFR copied but container cleanup failed: {cleanup.stderr[-2000:]}"
            )
        manifest["producerJfr"] = {
            "enabled": True,
            "hostOutput": str(output),
            "containerRecording": recording_path,
            "recordingBytes": output.stat().st_size,
            "sha256": _sha256_file(output),
            "scope": "kafka-console-producer JVM only",
            "allocationSemantics": "JFR sampled allocation estimate; divide only by the exact sentRecordCount",
            "pythonRendererIncluded": False,
        }
    else:
        manifest["producerJfr"] = {"enabled": False}
    return manifest


def _write_manifest(path: Path | None, manifest: dict[str, Any]) -> None:
    rendered = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=tuple(MODE_COUNTS), default="smoke")
    parser.add_argument("--campaign-id", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--count", type=int)
    parser.add_argument("--rate", type=int, default=0, help="records/s; 0 is unthrottled")
    parser.add_argument("--latency-samples", type=int, default=1_000)
    parser.add_argument("--flush-every", type=int, default=100)
    parser.add_argument("--publish-timeout-seconds", type=int, default=7200)
    parser.add_argument("--fixture-path", type=Path, default=DEFAULT_FIXTURE_PATH)
    parser.add_argument("--kafka-container", default="flowplane-kafka")
    parser.add_argument("--kafka-bootstrap", default="kafka:9092")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument(
        "--producer-jfr-output",
        type=Path,
        help="host path for JFR from the existing kafka-console-producer JVM",
    )
    parser.add_argument("--execute", action="store_true")
    parser.add_argument(
        "--confirm-campaign",
        help="required with --execute and must exactly match --campaign-id",
    )
    args = parser.parse_args(argv)
    count = args.count if args.count is not None else MODE_COUNTS[args.mode]
    config = PublisherConfig(
        mode=args.mode,
        campaign_id=args.campaign_id,
        topic=args.topic,
        count=count,
        rate_per_second=args.rate,
        latency_sample_limit=args.latency_samples,
        flush_every=args.flush_every,
        fixture_path=args.fixture_path,
        kafka_container=args.kafka_container,
        kafka_bootstrap=args.kafka_bootstrap,
        producer_jfr_output=args.producer_jfr_output,
        publish_timeout_seconds=args.publish_timeout_seconds,
    )
    try:
        validate_config(config)
        if args.execute and args.confirm_campaign != args.campaign_id:
            raise PublisherError("--execute requires --confirm-campaign matching campaign ID")
        manifest = execute(config) if args.execute else dry_run_manifest(config)
        _write_manifest(args.manifest, manifest)
        return 0
    except (OSError, PublisherError, subprocess.SubprocessError, ValueError) as exc:
        failure = {
            "formatVersion": 1,
            "status": "FAIL",
            "mode": args.mode,
            "campaignId": args.campaign_id,
            "topic": args.topic,
            "error": str(exc),
            "publishTimeoutSeconds": args.publish_timeout_seconds,
        }
        if args.manifest:
            _write_manifest(args.manifest, failure)
        print(json.dumps(failure), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(_main())
