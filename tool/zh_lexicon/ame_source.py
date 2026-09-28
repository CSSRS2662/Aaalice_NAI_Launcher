"""Pinned amenorira/danbooru-tags-data-zh (MIT) rows mapped onto tag_catalog.db.

Downloads happen only through ``fetch`` (``--fetch`` in the build scripts).
Every read verifies the exact raw bytes recorded in ``source_lock.json``.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import sqlite3
import urllib.request
from contextlib import closing
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOCK = HERE / "source_lock.json"
DEFAULT_SOURCE = ROOT / "tool/.tmp/zh-lexicon/source"
CATALOG = ROOT / "assets/databases/tag_catalog.db"

TAG_NAME = re.compile(r"[a-z0-9_()\-:'!.?/&+~^;@#*<>=]+")
CJK = re.compile(r"[぀-ヿ㐀-鿿]")

# Danbooru category -> catalog categories of the same family (Danbooru first).
FAMILIES = {0: (0, 7), 1: (1, 8), 3: (3, 10), 4: (4, 11), 5: (5, 14)}
TABLES = {"general": 0, "character": 4, "copyright": 3, "meta": 5}


def load_lock() -> dict:
    return json.loads(LOCK.read_text(encoding="utf-8"))


def _check(relative: str, data: bytes, expected: dict) -> None:
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != expected["bytes"] or digest != expected["sha256"]:
        raise ValueError(f"{relative} does not match source_lock.json; run with --fetch")


def fetch(destination: Path = DEFAULT_SOURCE) -> None:
    """Download every locked file from the pinned commit and verify it."""
    lock = load_lock()
    for relative, expected in lock["files"].items():
        url = f"{lock['raw_base']}/{lock['commit']}/{relative}"
        with urllib.request.urlopen(url, timeout=180) as response:
            data = response.read()
        _check(relative, data, expected)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def read_verified(relative: str, source: Path = DEFAULT_SOURCE) -> bytes:
    expected = load_lock()["files"][relative]
    path = source / relative
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing; run with --fetch")
    data = path.read_bytes()
    _check(relative, data, expected)
    return data


def clean(text: str) -> str:
    return " ".join((text or "").split())


def dedupe(items) -> list[str]:
    seen, out = set(), []
    for item in items:
        item = clean(item)
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


def read_table(name: str, source: Path = DEFAULT_SOURCE) -> list[dict]:
    text = read_verified(f"tags/{name}.csv", source).decode("utf-8-sig")
    rows = []
    for row in csv.DictReader(io.StringIO(text, newline="")):
        rows.append({
            "name": row["tag"].strip(),
            "category": int(row["category"]),
            "count": int(row["count"] or 0),
            "zh": clean(row["zh"]),
            "aliases": dedupe(row["aliases"].split("|")),
            "notes": clean(row["notes"]),
        })
    return rows


def catalog_tables(catalog: Path = CATALOG):
    """name -> (category, post_count) and alias -> [canonical names]."""
    with closing(sqlite3.connect(catalog.as_uri() + "?mode=ro", uri=True)) as db:
        tags = {name: (int(category), int(count)) for name, category, count in
                db.execute("SELECT name, category, post_count FROM tags")}
        aliases: dict[str, list[str]] = {}
        for alias, name in db.execute(
                "SELECT a.alias, t.name FROM aliases a JOIN tags t ON t.id = a.tag_id ORDER BY t.name"):
            aliases.setdefault(alias, []).append(name)
    return tags, aliases


def map_rows(rows, aliases, exact_ok, alias_ok) -> dict[str, dict]:
    """Catalog tag -> source row: exact name > catalog alias > source alias field.

    Ties inside a priority keep the most used source row.  ``exact_ok`` and
    ``alias_ok`` restrict which catalog names each route may claim.
    """
    best: dict[str, tuple] = {}
    for row in rows:
        targets = []
        if exact_ok(row["name"]):
            targets.append((0, row["name"]))
        else:
            targets += [(1, name) for name in aliases.get(row["name"], []) if alias_ok(name)]
            targets += [(2, alias) for alias in row["aliases"]
                        if TAG_NAME.fullmatch(alias) and alias_ok(alias)]
        for priority, name in targets:
            key = (priority, -row["count"])
            if name not in best or key < best[name][0]:
                best[name] = (key, row)
    return {name: row for name, (_key, row) in best.items()}
