"""Build the bundled lexical-search data from pinned sources.

Run from the repository root:
    python tool/search_lexicon/build_search_lexicon.py --fetch   # first time: download + verify
    python tool/search_lexicon/build_search_lexicon.py           # rebuild from verified local copies

Outputs (deterministic, gzip mtime=0) under assets/search_lexicon/:
  hanzi_pinyin.json.gz   {"readings": {char: "reading1,reading2"}}  toneless, most common first
  zh_en_lexicon.json.gz  {"drop": [...], "words": {zh: [english tag token or phrase, ...]}}
  manifest.json, LICENSE.pinyin-data.txt, LICENSE.ecdict.txt

The Chinese-to-English word list only keeps English words that occur in tag
names (tag_catalog.db), so a Chinese query can be rewritten into tag tokens.
Candidate order: reviewed overrides, then AME single-word tag names (MIT, the
bundled zh lexicon) whose Chinese label is the word, then ECDICT glosses.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import re
import sqlite3
import sys
import unicodedata
import urllib.request
from collections import defaultdict
from contextlib import closing
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOCK = HERE / "source_lock.json"
OVERRIDES = HERE / "zh_en_overrides.json"
SOURCE = ROOT / "tool/.tmp/search-lexicon/source"
CATALOG = ROOT / "assets/databases/tag_catalog.db"
AME = ROOT / "assets/zh_lexicon/ame_lexicon.json.gz"
OUT = ROOT / "assets/search_lexicon"

CJK_WORD = re.compile(r"^[㐀-鿿]{1,6}$")
POS_PREFIX = re.compile(r"^(?:[a-z]{1,6}\.\s*)+(?:&\s*(?:[a-z]{1,6}\.\s*)+)*")
BRACKETS = re.compile(r"[（(\[【〈<《][^）)\]】〉>》]*[）)\]】〉>》]")
SPLIT = re.compile(r"[，,；;、/]+")
MAX_CANDIDATES = 4
MAX_READINGS = 3
MIN_TOKEN_WEIGHT = 50
GENERAL = (0, 7)


# --------------------------------------------------------------------------- sources

def load_lock() -> dict:
    return json.loads(LOCK.read_text(encoding="utf-8"))


def _check(name: str, data: bytes, expected: dict) -> None:
    if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
        raise ValueError(f"{name} does not match source_lock.json; run with --fetch")


def fetch() -> None:
    for source, spec in load_lock()["sources"].items():
        for relative, expected in spec["files"].items():
            url = f"{spec['raw_base']}/{spec['commit']}/{relative}"
            with urllib.request.urlopen(url, timeout=600) as response:
                data = response.read()
            _check(f"{source}/{relative}", data, expected)
            SOURCE.mkdir(parents=True, exist_ok=True)
            (SOURCE / f"{source}.{relative}").write_bytes(data)


def read_verified(source: str, relative: str) -> bytes:
    expected = load_lock()["sources"][source]["files"][relative]
    path = SOURCE / f"{source}.{relative}"
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing; run with --fetch")
    data = path.read_bytes()
    _check(f"{source}/{relative}", data, expected)
    return data


# --------------------------------------------------------------------------- pinyin

def toneless(syllable: str) -> str:
    decomposed = unicodedata.normalize("NFD", syllable.strip().lower())
    plain = "".join(c for c in decomposed if not unicodedata.combining(c))
    return plain.replace("ü", "v").replace("ü", "v")


def _readings(text: str) -> dict[str, list[str]]:
    result = {}
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line.startswith("U+"):
            continue
        code, values = line.split(":", 1)
        char = chr(int(code[2:], 16))
        result[char] = [toneless(v) for v in re.split(r"[,\s]+", values.strip()) if v]
    return result


def build_pinyin() -> dict[str, str]:
    standard = _readings(read_verified("pinyin-data", "kTGHZ2013.txt").decode("utf-8"))
    mandarin = _readings(read_verified("pinyin-data", "kMandarin.txt").decode("utf-8"))
    table = {}
    for char in sorted(set(standard) | set(mandarin)):
        if not ("㐀" <= char <= "鿿"):
            continue
        ordered = []
        # The most common reading first, then the other standard readings.
        for reading in mandarin.get(char, []) + standard.get(char, []):
            if reading and reading.isalpha() and reading not in ordered:
                ordered.append(reading)
        if ordered:
            table[char] = ",".join(ordered[:MAX_READINGS])
    return table


# --------------------------------------------------------------------------- zh -> en words

def tag_token_weights(catalog: Path) -> dict[str, int]:
    weights: dict[str, int] = defaultdict(int)
    with closing(sqlite3.connect(f"file:{catalog}?mode=ro", uri=True)) as db:
        for name, count in db.execute("SELECT name, post_count FROM tags"):
            for token in re.split(r"[^a-z]+", name.lower()):
                if len(token) >= 2:
                    weights[token] += count or 0
    return {t: w for t, w in weights.items() if w >= MIN_TOKEN_WEIGHT}


def _glosses(translation: str) -> list[tuple[str, int]]:
    """(Chinese word, rank) pairs; rank grows with line and item position."""
    out, rank = [], 0
    for line_index, line in enumerate(translation.replace("\\n", "\n").split("\n")):
        line = line.strip()
        if not line or line.startswith("[网络]") or line.startswith("["):
            continue
        line = BRACKETS.sub("", POS_PREFIX.sub("", line))
        for item in SPLIT.split(line):
            item = item.strip()
            variants = [item]
            if item.endswith("的") and len(item) > 2:
                variants.append(item[:-1])
            for word in variants:
                if CJK_WORD.match(word):
                    out.append((word, line_index * 10 + rank))
            rank += 1
    return out


def _forms(word: str, exchange: str, vocab: dict[str, int]) -> list[str]:
    forms = [word]
    for part in (exchange or "").split("/"):
        if ":" in part:
            key, value = part.split(":", 1)
            if key in "pdi3s" and value.isalpha():
                forms.append(value.lower())
    present = [f for f in dict.fromkeys(forms) if f in vocab]
    # A form that starts with another kept form adds nothing to a prefix search.
    present.sort(key=lambda f: (len(f), f))
    kept = []
    for form in present:
        if not any(form.startswith(k) for k in kept):
            kept.append(form)
    return kept


def build_words(catalog: Path) -> tuple[dict[str, list[str]], list[str], dict]:
    vocab = tag_token_weights(catalog)
    scored: dict[str, dict[str, float]] = defaultdict(dict)

    def offer(zh: str, forms: list[str], score: float) -> None:
        bucket = scored[zh]
        for index, form in enumerate(forms):
            value = score - index * 0.01
            if bucket.get(form, -1e9) < value:
                bucket[form] = value

    # AME single-word general tags: the label is the domain sense of the word.
    ame = json.loads(gzip.decompress(AME.read_bytes()))["entries"]
    ame_words = 0
    for tag, category, count, label, aliases in ame:
        if category not in GENERAL or not re.fullmatch(r"[a-z]+", tag) or tag not in vocab:
            continue
        for zh in [label, *aliases]:
            if zh and CJK_WORD.match(zh):
                offer(zh, [tag], 1000 + min(count, 10 ** 7) / 10 ** 7)
                ame_words += 1

    text = read_verified("ecdict", "ecdict.csv").decode("utf-8")
    ecdict_rows = 0
    for row in csv.DictReader(io.StringIO(text)):
        word = (row.get("word") or "").strip().lower()
        if not word.isalpha():
            continue
        forms = _forms(word, row.get("exchange", ""), vocab)
        if not forms:
            continue
        frq = int(row.get("frq") or 0) or 60000
        for zh, rank in _glosses(row.get("translation") or ""):
            offer(zh, forms, 500 - rank * 5 - frq / 1000)
        ecdict_rows += 1

    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    words = {}
    for zh, bucket in scored.items():
        ranked = sorted(bucket.items(), key=lambda item: (-item[1], item[0]))
        words[zh] = [form for form, _ in ranked[:MAX_CANDIDATES]]
    for zh, forms in overrides["map"].items():
        words[zh] = list(forms)
    drop = sorted(set(overrides["drop"]))
    for zh in drop:
        words.pop(zh, None)
    stats = {"tag_tokens": len(vocab), "ame_words": ame_words, "ecdict_rows": ecdict_rows,
             "overrides": len(overrides["map"]), "drop": len(drop), "words": len(words)}
    return dict(sorted(words.items())), drop, stats


# --------------------------------------------------------------------------- output

def _gzip_json(payload) -> bytes:
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return gzip.compress(text.encode("utf-8"), compresslevel=9, mtime=0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fetch", action="store_true", help="download the locked files first")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    pinyin = build_pinyin()
    words, drop, stats = build_words(CATALOG)
    files = {
        "hanzi_pinyin.json.gz": _gzip_json({"version": 1, "readings": pinyin}),
        "zh_en_lexicon.json.gz": _gzip_json({"version": 1, "drop": drop, "words": words}),
    }
    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (OUT / name).write_bytes(data)
    (OUT / "LICENSE.pinyin-data.txt").write_bytes(read_verified("pinyin-data", "LICENSE"))
    (OUT / "LICENSE.ecdict.txt").write_bytes(read_verified("ecdict", "LICENSE"))
    lock = load_lock()
    manifest = {
        "sources": {
            name: {k: spec[k] for k in ("repository", "commit", "license", "copyright")}
            for name, spec in lock["sources"].items()
        },
        "overrides_sha256": hashlib.sha256(OVERRIDES.read_bytes()).hexdigest(),
        "ame_lexicon_sha256": hashlib.sha256(AME.read_bytes()).hexdigest(),
        "catalog_sha256": hashlib.sha256(CATALOG.read_bytes()).hexdigest(),
        "pinyin_characters": len(pinyin),
        "zh_en": stats,
        "files": {
            name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in files.items()
        },
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"pinyin_characters": len(pinyin), **stats,
                      **{n: len(d) for n, d in files.items()}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
