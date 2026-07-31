from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path

PUBLISHER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PUBLISHER_DIR))

import publisher  # noqa: E402


def config(**changes):
    values = dict(
        mode="smoke",
        campaign_id="http-smoke-001",
        topic="flowplane.benchmark.http-smoke-001.raw",
        count=10,
        rate_per_second=0,
        latency_sample_limit=5,
        flush_every=2,
        fixture_path=publisher.DEFAULT_FIXTURE_PATH,
        publish_timeout_seconds=7200,
    )
    values.update(changes)
    return publisher.PublisherConfig(**values)


class PublisherTests(unittest.TestCase):
    def test_exact_500k_schedule_math_and_last_sequence(self) -> None:
        count = 500_000
        last = publisher.schedule_entry(count - 1, count)
        self.assertEqual(499_999, last.sequence)
        self.assertEqual(99, last.variant_index)
        manifest = publisher.dry_run_manifest(
            config(mode="measured", count=count, latency_sample_limit=10)
        )
        self.assertEqual(5_000, manifest["roundRobinCycles"])
        self.assertEqual(0, manifest["partialCycleRecords"])
        self.assertEqual(51_200_000_000, manifest["payloadBytesPlanned"])

    def test_stream_has_exact_count_size_and_last_identity(self) -> None:
        sink = io.BytesIO()
        result = publisher.stream_records(config(), sink)
        lines = sink.getvalue().splitlines()
        self.assertEqual(10, len(lines))
        for sequence, line in enumerate(lines):
            key, value = line.split(b":", 1)
            self.assertEqual(str(sequence).encode("ascii"), key)
            self.assertEqual(102_400, len(value))
        self.assertEqual(9, result["lastSequence"])
        self.assertEqual(9, result["lastVariantIndex"])
        self.assertLessEqual(len(result["latencySamples"]), 5)
        self.assertIn("fixture corpus", result["payloadSource"])
        self.assertIn("feedElapsedSeconds", result)
        self.assertIn("feedRecordsPerSecond", result)
        self.assertNotIn("achievedRecordsPerSecond", result)

    def test_fixture_corpus_is_reused_round_robin(self) -> None:
        sink = io.BytesIO()
        publisher.stream_records(config(count=101), sink)
        lines = sink.getvalue().splitlines()
        first = lines[0].split(b":", 1)[1]
        repeated = lines[100].split(b":", 1)[1]
        self.assertEqual(first, repeated)

    def test_measured_count_must_be_exact(self) -> None:
        with self.assertRaisesRegex(publisher.PublisherError, "exactly 500000"):
            publisher.validate_config(config(mode="measured", count=499_999))

    def test_exploratory_count_is_exact_and_separate_from_measured(self) -> None:
        exploratory = publisher.dry_run_manifest(config(mode="exploratory", count=10_000))
        self.assertEqual("exploratory", exploratory["mode"])
        self.assertEqual(10_000, exploratory["recordCountPlanned"])
        with self.assertRaisesRegex(publisher.PublisherError, "exactly 10000"):
            publisher.validate_config(config(mode="exploratory", count=9_999))
        warmup = publisher.dry_run_manifest(config(mode="exploratory-warmup", count=1_000))
        self.assertEqual(1_000, warmup["recordCountPlanned"])
        with self.assertRaisesRegex(publisher.PublisherError, "exactly 1000"):
            publisher.validate_config(config(mode="exploratory-warmup", count=999))

    def test_rate_and_count_validation(self) -> None:
        with self.assertRaisesRegex(publisher.PublisherError, "count must be positive"):
            publisher.validate_config(config(count=0))
        with self.assertRaisesRegex(publisher.PublisherError, "rate must be"):
            publisher.validate_config(config(rate_per_second=-1))
        with self.assertRaisesRegex(publisher.PublisherError, "rate must be"):
            publisher.validate_config(config(rate_per_second=1_000_001))
        with self.assertRaisesRegex(publisher.PublisherError, "publish timeout"):
            publisher.validate_config(config(publish_timeout_seconds=59))

    def test_safe_campaign_topic_and_command_arguments(self) -> None:
        valid = config()
        command = publisher.producer_command(valid)
        self.assertEqual("docker", command[0])
        self.assertIn(valid.topic, command)
        self.assertIn("acks=all", command)
        self.assertIn("parse.key=true", command)
        self.assertIn("compression.type=lz4", command)
        self.assertIn("batch.size=1048576", command)
        self.assertIn("linger.ms=10", command)
        with self.assertRaisesRegex(publisher.PublisherError, "campaign ID"):
            publisher.validate_config(config(campaign_id="BAD; docker rm"))
        with self.assertRaisesRegex(publisher.PublisherError, "topic"):
            publisher.validate_config(config(topic="bad topic && evil"))

    def test_jfr_instruments_existing_console_producer_without_changing_payload_contract(self) -> None:
        output = Path("producer-recording.jfr")
        observed = config(producer_jfr_output=output)
        command = publisher.producer_command(observed)
        self.assertEqual(["docker", "exec", "-i"], command[:3])
        self.assertIn("-e", command)
        option = next(value for value in command if value.startswith("JAVA_TOOL_OPTIONS="))
        self.assertIn("StartFlightRecording", option)
        self.assertIn("dumponexit=true", option)
        self.assertIn(publisher.producer_jfr_container_path(observed), option)
        self.assertIn("kafka-console-producer", command)
        self.assertIn("parse.key=true", command)
        self.assertIn("key.separator=:", command)
        self.assertIn("compression.type=lz4", command)
        manifest = publisher.dry_run_manifest(observed)
        self.assertTrue(manifest["producerJfr"]["enabled"])
        self.assertEqual(10, manifest["recordCountPlanned"])
        self.assertEqual(102_400, manifest["payloadBytesEach"])

    def test_sample_indices_are_bounded_and_include_edges(self) -> None:
        samples = publisher.sample_sequences(500_000, 1_000)
        self.assertEqual(1_000, len(samples))
        self.assertEqual(0, samples[0])
        self.assertEqual(499_999, samples[-1])
        self.assertEqual(len(samples), len(set(samples)))


if __name__ == "__main__":
    unittest.main()
