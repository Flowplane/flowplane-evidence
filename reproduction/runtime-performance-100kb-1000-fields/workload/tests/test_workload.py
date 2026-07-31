from __future__ import annotations

import json
import copy
import sys
import tempfile
import unittest
from pathlib import Path

WORKLOAD_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKLOAD_DIR))

import workload  # noqa: E402


class WorkloadTests(unittest.TestCase):
    def test_generated_bundle_passes_all_contract_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            result = workload.generate(Path(temp))
            self.assertEqual("PASS", result["status"])
            self.assertEqual(100, result["payloadVariantCount"])
            self.assertEqual(102_400, result["payloadBytes"])
            self.assertEqual(100, result["uniquePayloadHashes"])
            self.assertEqual(1_000, result["mappingOutputFieldCount"])
            self.assertEqual(500_000, result["measuredRecordCount"])

    def test_generation_is_byte_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
            workload.generate(Path(left))
            workload.generate(Path(right))
            names = (
                workload.PAYLOAD_FILE,
                "invalid-policy-payloads.jsonl",
                "mapping.dsl",
                "mapping-coverage.json",
                "coverage-compile-probes.json",
                "policy-canary-manifest.json",
                "workload-manifest.json",
                "SHA256SUMS",
            )
            for name in names:
                self.assertEqual((Path(left) / name).read_bytes(), (Path(right) / name).read_bytes(), name)

    def test_variant_schema_is_identical_while_values_change(self) -> None:
        first = json.loads(workload.build_payload(0))
        second = json.loads(workload.build_payload(1))
        self.assertEqual(workload.schema_fingerprint(first), workload.schema_fingerprint(second))
        self.assertNotEqual(first["event"]["id"], second["event"]["id"])
        self.assertEqual(list(first.keys()), list(second.keys()))
        self.assertEqual(3, len(first["signals"]))
        self.assertEqual(3, len(second["signals"]))

    def test_validation_rejects_checksum_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workload.generate(root)
            payload_path = root / workload.PAYLOAD_FILE
            data = bytearray(payload_path.read_bytes())
            data[0] = ord("[")
            payload_path.write_bytes(data)
            with self.assertRaisesRegex(workload.WorkloadError, "checksum mismatch"):
                workload.validate(root)

    def test_mapping_has_exact_output_count(self) -> None:
        mapping = workload.build_mapping().decode("utf-8")
        self.assertEqual(1_000, workload.count_mapping_fields(mapping))

    def test_every_wide_output_has_a_nontrivial_transform_chain(self) -> None:
        mapping = workload.build_hard_mapping().decode("utf-8")
        wide_count = workload.MAPPING_FIELD_COUNT - len(workload.CORE_FIELDS)
        for index in range(1, wide_count + 1):
            start = mapping.index(f"  wideField{index:04d}:\n")
            next_marker = f"  wideField{index + 1:04d}:\n"
            end = mapping.find(next_marker, start) if index < wide_count else len(mapping)
            block = mapping[start:end]
            operations = sum(
                token in block
                for token in (
                    "normalize_string:", "case_convert:", "regex_replace:",
                    "regex_extract:", "regex_match:", "substring:", "hash:",
                    "template:", "valueExpr:",
                )
            )
            self.assertGreaterEqual(operations, 3, f"wideField{index:04d}")

    def test_hard_profile_references_canonical_payload_without_copying_it(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workload.generate(root)
            profile = root / "grpc-hard-complexity"
            manifest = workload.generate_hard_profile(profile)
            self.assertEqual(923, manifest["hardWideFieldCount"])
            self.assertEqual(0, manifest["passThroughWideFieldCount"])
            self.assertEqual("../valid-payloads-100kb.jsonl", manifest["payloadCorpus"])
            self.assertFalse((profile / workload.PAYLOAD_FILE).exists())
            self.assertEqual(1_000, workload.count_mapping_fields((profile / "mapping.dsl").read_text()))

    def test_campaign_render_keeps_exact_size_and_schema(self) -> None:
        template = json.loads(workload.build_payload(99))
        rendered_bytes = workload.render_measured_payload(
            99, "http-campaign-20260730", 499_999, 1_785_412_800_000
        )
        rendered = json.loads(rendered_bytes)
        self.assertEqual(102_400, len(rendered_bytes))
        self.assertEqual(499_999, rendered["run"]["sequence"])
        self.assertEqual(
            workload.schema_fingerprint(template), workload.schema_fingerprint(rendered)
        )

    def test_required_supported_family_cannot_be_unrepresented(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workload.generate(root)
            matrix = json.loads((root / "mapping-coverage.json").read_bytes())
            probes = json.loads((root / "coverage-compile-probes.json").read_bytes())
            canaries = json.loads((root / "policy-canary-manifest.json").read_bytes())
            broken = copy.deepcopy(matrix)
            broken["families"][0]["coverage"][0]["variants"].remove("PATH")
            with self.assertRaisesRegex(workload.WorkloadError, "unrepresented variants"):
                workload._validate_coverage(
                    broken,
                    probes,
                    (root / "mapping.dsl").read_text(encoding="utf-8"),
                    {item["id"] for item in canaries["canaries"]},
                    workload.coverage_oracle.default_product_root(),
                )

    def test_measured_coverage_requires_real_mapping_field(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workload.generate(root)
            matrix = json.loads((root / "mapping-coverage.json").read_bytes())
            probes = json.loads((root / "coverage-compile-probes.json").read_bytes())
            canaries = json.loads((root / "policy-canary-manifest.json").read_bytes())
            matrix["families"][0]["coverage"][0]["evidence"][0] = "doesNotExist"
            with self.assertRaisesRegex(workload.WorkloadError, "absent mapping field"):
                workload._validate_coverage(
                    matrix,
                    probes,
                    (root / "mapping.dsl").read_text(encoding="utf-8"),
                    {item["id"] for item in canaries["canaries"]},
                    workload.coverage_oracle.default_product_root(),
                )


if __name__ == "__main__":
    unittest.main()
