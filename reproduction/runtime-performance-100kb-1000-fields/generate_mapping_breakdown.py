#!/usr/bin/env python3
"""Generate the public one-row-per-output-field mapping inventory.

This deliberately parses only the stable indentation contract used by the
synthetic benchmark mapping. It does not implement or execute Flowplane DSL.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


FIELD_RE = re.compile(r"^  ([A-Za-z][A-Za-z0-9_]*):\s*$")
PROPERTY_RE = re.compile(r"^    ([A-Za-z][A-Za-z0-9_]*):(?:\s*(.*))?$")
SOURCE_KEYS = {
    "path",
    "constant",
    "metadata",
    "header",
    "arithmetic",
    "valueExpr",
    "case",
}


def parse_fields(mapping: Path) -> list[dict[str, str]]:
    in_fields = False
    current: dict[str, object] | None = None
    rows: list[dict[str, str]] = []

    for line in mapping.read_text(encoding="utf-8").splitlines():
        if line == "fields:":
            in_fields = True
            continue
        if not in_fields:
            continue

        field_match = FIELD_RE.match(line)
        if field_match:
            if current is not None:
                rows.append(finalize(current, len(rows) + 1))
            current = {"name": field_match.group(1), "properties": []}
            continue

        if current is None:
            continue
        property_match = PROPERTY_RE.match(line)
        if property_match:
            current["properties"].append(
                (property_match.group(1), (property_match.group(2) or "").strip())
            )

    if current is not None:
        rows.append(finalize(current, len(rows) + 1))
    return rows


def finalize(field: dict[str, object], ordinal: int) -> dict[str, str]:
    properties = list(field["properties"])
    source = next((key for key, _ in properties if key in SOURCE_KEYS), "derived")
    source_value = next((value for key, value in properties if key == source), "")
    operations = [key for key, _ in properties if key not in SOURCE_KEYS]
    policies = [
        key
        for key, _ in properties
        if key in {"required", "validate", "onOverflow", "onTypeMismatch", "default"}
    ]
    family = "core" if ordinal <= 77 else f"chain-{(ordinal - 78) % 8}"
    return {
        "ordinal": str(ordinal),
        "output_field": str(field["name"]),
        "group": "core" if ordinal <= 77 else "hard-wide",
        "chain_family": family,
        "source_kind": source,
        "source": source_value,
        "operations": "|".join(operations),
        "policies": "|".join(policies),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    rows = parse_fields(args.mapping)
    if len(rows) != 1000:
        raise SystemExit(f"expected 1000 fields, found {len(rows)}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
