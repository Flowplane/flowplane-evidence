from __future__ import annotations

import sys
import unittest
from pathlib import Path

PUBLISHER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PUBLISHER_DIR))

import kafka_latency  # noqa: E402


class KafkaLatencyTests(unittest.TestCase):
    def test_parses_console_consumer_metadata(self) -> None:
        self.assertEqual(
            (42, 1785412800123),
            kafka_latency.parse_metadata_line(b"CreateTime:1785412800123\t42\t"),
        )
        self.assertIsNone(kafka_latency.parse_metadata_line(b"payload was intentionally disabled"))

    def test_summarizes_correlated_samples(self) -> None:
        result = kafka_latency.summarize(
            {0: 1000, 5: 2000, 9: 3000},
            {0: 1010, 5: 2020, 9: 3030},
            (0, 5, 9),
        )
        self.assertEqual(3, result["sampleCountMatched"])
        self.assertEqual(20, result["latencyMillis"]["p50"])
        self.assertEqual(30, result["latencyMillis"]["p99"])

    def test_duplicate_keys_keep_max_timestamp_across_partition_order(self) -> None:
        observed: dict[int, int] = {}
        kafka_latency.retain_latest_timestamp(observed, 200, 2_000)
        kafka_latency.retain_latest_timestamp(observed, 200, 1_000)
        kafka_latency.retain_latest_timestamp(observed, 200, 3_000)
        self.assertEqual({200: 3_000}, observed)

    def test_exploratory_profile_is_explicit_in_cli_contract(self) -> None:
        source = Path(kafka_latency.__file__).read_text(encoding="utf-8")
        self.assertIn('choices=("standard-500k", "exploratory-10k")', source)
        self.assertIn('expected_measured = 500_000 if args.measurement_profile == "standard-500k" else 10_000', source)


if __name__ == "__main__":
    unittest.main()
