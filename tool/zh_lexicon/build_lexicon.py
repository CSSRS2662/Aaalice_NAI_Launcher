"""Build the bundled Chinese name/alias lexicon from the pinned AME source.

Run from the repository root:
    python tool/zh_lexicon/build_lexicon.py --fetch   # first time: download + verify
    python tool/zh_lexicon/build_lexicon.py           # rebuild from verified local copy

Output (deterministic): assets/zh_lexicon/ame_lexicon.json.gz, manifest.json and
LICENSE.amenorira.txt.  Artist rows are excluded: their zh column mostly keeps the
original Japanese name, which adds noise to ordinary Chinese lookups.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ame_source  # noqa: E402

OUT = ame_source.ROOT / "assets/zh_lexicon"
MAX_ALIAS = 40


def lexicon_entry(tag, category, count, row):
    """[tag, catalog category, post count, zh label or '', [CJK aliases]] or None."""
    label = row["zh"] if ame_source.CJK.search(row["zh"]) else ""
    aliases = [alias for alias in row["aliases"]
               if ame_source.CJK.search(alias) and alias != label and len(alias) <= MAX_ALIAS]
    if not label and not aliases:
        return None
    return [tag, category, count, label, aliases]


def build(source: Path, catalog: Path) -> tuple[list, dict]:
    tags, aliases = ame_source.catalog_tables(catalog)
    entries, counts = {}, {}
    for table, danbooru in ame_source.TABLES.items():
        family = ame_source.FAMILIES[danbooru]
        rows = ame_source.read_table(table, source)
        mapped = ame_source.map_rows(
            rows, aliases,
            exact_ok=lambda name: name in tags and tags[name][0] in family,
            alias_ok=lambda name: name in tags and tags[name][0] == danbooru,
        )
        kept = 0
        for tag, row in mapped.items():
            category, count = tags[tag]
            entry = lexicon_entry(tag, category, count, row)
            if entry is not None and tag not in entries:
                entries[tag] = entry
                kept += 1
        counts[table] = {"source_rows": len(rows), "mapped": len(mapped), "entries": kept}
    return [entries[tag] for tag in sorted(entries)], counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fetch", action="store_true", help="download the locked files first")
    parser.add_argument("--source", type=Path, default=ame_source.DEFAULT_SOURCE)
    parser.add_argument("--catalog", type=Path, default=ame_source.CATALOG)
    args = parser.parse_args()
    if args.fetch:
        ame_source.fetch(args.source)
    lock = ame_source.load_lock()
    entries, counts = build(args.source, args.catalog)
    payload = json.dumps({"version": 1, "entries": entries}, ensure_ascii=False, separators=(",", ":"))
    data = gzip.compress(payload.encode("utf-8"), compresslevel=9, mtime=0)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "ame_lexicon.json.gz").write_bytes(data)
    (OUT / "LICENSE.amenorira.txt").write_bytes(ame_source.read_verified("LICENSE", args.source))
    catalog_sha = hashlib.sha256(args.catalog.read_bytes()).hexdigest()
    manifest = {
        "source": {k: lock[k] for k in ("name", "repository", "commit", "license", "copyright")},
        "source_files": {k: v["sha256"] for k, v in lock["files"].items()},
        "catalog_sha256": catalog_sha,
        "format": "[tag, catalog_category, post_count, zh_label, [cjk_aliases]]",
        "entries": len(entries),
        "tables": counts,
        "file": {"name": "ame_lexicon.json.gz", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()},
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"entries": len(entries), "bytes": len(data), "tables": counts}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
