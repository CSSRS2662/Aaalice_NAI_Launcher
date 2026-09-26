"""Offline unseen-paraphrase benchmark for the Danbooru Chinese search.

The benchmark is intentionally separate from the Flutter application.  It
reads the catalog/dictionaries read-only, never calls a translation service,
and never writes a query into a production database.  Queries are curated
evaluation text and are excluded whenever they contain the complete current
Chinese label of their target (leakage prevention).
"""
import argparse
from contextlib import closing
import ctypes
import gc
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import statistics
import sys
import time

import numpy as np

from evaluate import Encoder, ROOT, sha256, verify_model


HAN = re.compile(r"[\u3400-\u9fff]")
KANA = re.compile(r"[\u3040-\u30ff]")
_TOKEN = re.compile(r"[a-z0-9]+(?:[-'][a-z0-9]+)*")


REQUIRED_CASES = [
    {"query": "衣服不要塞进裙子", "target": "untucked_shirt", "category": "clothing"},
    {"query": "让衬衣自然垂在裤子外面", "target": "untucked_shirt", "category": "clothing"},
    {"query": "上衣别扎进去", "target": "untucked_shirt", "category": "clothing"},
    {"query": "衣摆留在外面", "target": "untucked_shirt", "category": "clothing"},
    {"query": "不把衣服塞进裤腰", "target": "untucked_shirt", "category": "clothing"},
    {"query": "不穿袜子", "target": "no_socks", "category": "negation"},
    {"query": "腿上别有袜子", "target": "no_socks", "category": "negation"},
    {"query": "不要给她穿袜", "target": "no_socks", "category": "negation"},
    {"query": "脚上没有袜子", "target": "no_socks", "category": "negation"},
    {"query": "袜子去掉", "target": "no_socks", "category": "negation"},
    {"query": "穿袜子", "target": "socks", "category": "negation"},
    {"query": "给她穿上袜子", "target": "socks", "category": "negation"},
    {"query": "把上衣边缘收进腰里", "target": "shirt_tucked_in", "category": "clothing"},
    {"query": "衣角整齐塞进裙腰", "target": "shirt_tucked_in", "category": "clothing"},
    {"query": "下摆全部收好别露在外面", "target": "shirt_tucked_in", "category": "clothing"},
    {"query": "两只眼睛都合上", "target": "closed_eyes", "category": "quantity"},
    {"query": "不要睁眼", "target": "closed_eyes", "category": "negation"},
    {"query": "只闭一只眼", "target": "one_eye_closed", "category": "quantity"},
    {"query": "双眼闭着", "target": "closed_eyes", "category": "quantity"},
]


def _read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _open_readonly(path):
    return sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)


def load_catalog(catalog_path, dictionary_path):
    """Return production candidates and all existing text sources."""
    with closing(_open_readonly(dictionary_path)) as db:
        external = {
            name: (label or "").strip()
            for name, label in db.execute("SELECT name,cn_name FROM tags")
        }
        external = {name: label for name, label in external.items() if label}
    with closing(_open_readonly(catalog_path)) as db:
        bundled = {
            tag: label.strip()
            for tag, label, mode in db.execute(
                "SELECT tag,zh_cn,mode FROM zh_translations"
            )
            if label and (mode == 1 or tag not in external)
        }
        rows = list(
            db.execute(
                "SELECT name,category,post_count FROM tags "
                "WHERE category IN (0,7) ORDER BY name"
            )
        )
        aliases = {}
        for tag_id, alias in db.execute(
            "SELECT t.name,a.alias FROM aliases a JOIN tags t ON t.id=a.tag_id "
            "WHERE t.category IN (0,7) ORDER BY t.name,a.alias"
        ):
            aliases.setdefault(tag_id, []).append(alias)
        metadata = dict(db.execute("SELECT key,value FROM metadata"))
        columns = {row[1] for row in db.execute("PRAGMA table_info(zh_translations)")}
    labels = dict(external)
    labels.update(bundled)
    records = []
    for name, category, post_count in rows:
        records.append(
            {
                "tag": name,
                "category": int(category),
                "post_count": int(post_count),
                "zh_cn": labels.get(name, ""),
                "zh_tw": "",  # No traditional field exists in this schema.
                "aliases": aliases.get(name, []),
            }
        )
    return records, metadata, columns


def _language(query):
    if KANA.search(query):
        return "ja"
    if HAN.search(query):
        return "zh"
    return "en"


def _has_label_leak(query, record):
    query_fold = query.casefold()
    reasons = []
    for field, value in (("zh_cn", record["zh_cn"]), ("zh_tw", record["zh_tw"])):
        value = value.strip()
        # A one-character label is too ambiguous to be a useful leakage test;
        # labels of two or more characters must not occur verbatim in a query.
        if len(value) >= 2 and value in query:
            reasons.append(field)
    return reasons


def build_cases(records, dictionary_path, seed_path, hard_path, holdout_path):
    by_tag = {record["tag"]: record for record in records}
    seed = _read_json(seed_path)
    hard = _read_json(hard_path)
    holdout = _read_json(holdout_path)
    all_cases = []

    def add(case, source, case_id, query_type, target, conflict=None, **extra):
        if target not in by_tag:
            raise ValueError(f"Target outside production catalog: {target}")
        record = by_tag[target]
        leakage = _has_label_leak(case["query"], record)
        all_cases.append(
            {
                "id": case_id,
                "source": source,
                "query_type": query_type,
                "query": case["query"],
                "target": target,
                "alternatives": list(case.get("alternatives", [])),
                "conflict": conflict,
                "group": extra.get("group", case.get("group", query_type)),
                "polarity": extra.get("polarity", "unspecified"),
                "target_polarity": extra.get("target_polarity", "positive"),
                "conflict_polarity": extra.get("conflict_polarity", "positive"),
                "language": _language(case["query"]),
                "category": record["category"],
                "post_count": record["post_count"],
                "zh_cn": record["zh_cn"],
                "zh_tw": record["zh_tw"],
                "leakage": leakage,
                "leakage_reasons": leakage,
                **extra,
            }
        )

    for item_index, item in enumerate(seed, 1):
        for query_index, query in enumerate(item["queries"], 1):
            add(
                {"query": query, "group": item["group"]},
                "paraphrase",
                f"p-{item_index:03d}-{query_index}",
                item["group"],
                item["tag"],
                group=item["group"],
            )
    for item in hard:
        if item["target"] not in by_tag or item["conflict"] not in by_tag:
            raise ValueError(f"Hard pair outside production catalog: {item}")
        for query_index, query in enumerate(item["queries"], 1):
            add(
                {"query": query, "group": item["type"]},
                "hard",
                f"{item['id']}-{query_index}",
                item["type"],
                item["target"],
                conflict=item["conflict"],
                group=item["type"],
                polarity=item["type"],
                target_polarity="positive",
                conflict_polarity="positive",
            )
    for index, item in enumerate(REQUIRED_CASES, 1):
        conflict = {
            "untucked_shirt": "shirt_tucked_in",
            "no_socks": "socks",
            "socks": "no_socks",
            "shirt_tucked_in": "untucked_shirt",
            "closed_eyes": "one_eye_closed",
            "one_eye_closed": "closed_eyes",
        }.get(item["target"])
        add(
            item,
            "required-case",
            f"r-{index:03d}",
            item["category"],
            item["target"],
            conflict=conflict,
            group=item["category"],
            polarity=item["category"],
        )
    for index, item in enumerate(holdout, 1):
        add(
            item,
            "real-world-holdout",
            f"h-{index:03d}",
            "holdout",
            item["target"],
            conflict=item.get("opposite"),
            group="holdout",
            polarity="holdout",
        )
    # A duplicate query/target pair would count the same user utterance twice.
    unique = {}
    for item in all_cases:
        unique.setdefault((item["query"], item["target"]), item)
    for item in unique.values():
        record = by_tag[item["target"]]
        item["english_tag"] = item["target"].replace("_", " ")
        item["aliases"] = record["aliases"]
    if len(unique) != len(all_cases):
        all_cases = list(unique.values())
    return all_cases, by_tag


def candidate_texts(records, variant):
    texts = []
    for record in records:
        # A keeps the canonical Danbooru spelling intact.  B adds a readable
        # underscore-split form plus only existing catalog data.
        fields = [record["tag"]]
        if record["zh_cn"]:
            fields.append(record["zh_cn"])
        if variant == "enhanced-existing":
            # Only existing catalog aliases are added.  There is no local
            # description or traditional-translation field in this database.
            fields.insert(1, record["tag"].replace("_", " "))
            fields.extend(record["aliases"])
        texts.append("; ".join(fields))
    return texts


def _metadata(catalog_path, dictionary_path, directory, texts, dimensions, variant):
    result = {
        name: sha256(path)
        for name, path in {
            "catalog": catalog_path,
            "dictionary": dictionary_path,
            "model": directory / "model.onnx",
            "tokenizer": directory / "tokenizer.json",
        }.items()
    }
    result["corpus"] = hashlib.sha256(
        json.dumps(texts, ensure_ascii=False).encode()
    ).hexdigest()
    result["candidate_variant"] = variant
    result["encoding"] = "e5-query-passage-mean-l2-max128-length-batches-v2"
    result["dimensions"] = dimensions
    return result


def encode_cache(directory, texts, dimensions, metadata, threads, timeout=900):
    """Encode a candidate document variant with resumable temp checkpoints."""
    key = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()
    cache = directory / f"paraphrase-vectors-{key}.npy"
    if cache.exists():
        vectors = np.load(cache, mmap_mode="r", allow_pickle=False)
        if vectors.shape != (len(texts), dimensions) or not np.isfinite(vectors).all():
            raise ValueError(f"Invalid cache {cache}")
        return vectors, cache, True, 0.0
    started = time.monotonic()
    partial = directory / f"paraphrase-vectors-{key}.partial.npy"
    progress = directory / f"paraphrase-vectors-{key}.progress"
    completed = int(progress.read_text(encoding="utf-8")) if progress.exists() else 0
    if not 0 <= completed <= len(texts):
        raise ValueError("Invalid encoding checkpoint")
    encoder = Encoder(directory, threads)
    vectors = np.lib.format.open_memmap(
        partial,
        mode="r+" if partial.exists() else "w+",
        dtype=np.float32,
        shape=(len(texts), dimensions),
    )
    order = sorted(range(len(texts)), key=lambda index: (len(texts[index]), index))
    for start in range(completed, len(texts), 32):
        if time.monotonic() - started > timeout:
            raise TimeoutError("Candidate encoding time budget exceeded")
        positions = order[start : start + 32]
        vectors[positions] = encoder.encode(
            [texts[index] for index in positions], "passage: "
        )
        vectors.flush()
        progress.write_text(str(start + len(positions)), encoding="utf-8")
        if start % 4096 == 0:
            print(f"encoded {start}/{len(texts)} ({time.monotonic()-started:.1f}s)", flush=True)
    np.save(cache, vectors, allow_pickle=False)
    del vectors
    partial.unlink(missing_ok=True)
    progress.unlink(missing_ok=True)
    return np.load(cache, mmap_mode="r", allow_pickle=False), cache, False, time.monotonic() - started


def _normalize_english(value):
    return re.sub(r"[^a-z0-9]+", "_", value.casefold()).strip("_")


def _chinese_variants(query):
    match = re.fullmatch(r"(?:不穿|没穿|没有穿|未穿)([\u3400-\u9fff]{2,12})", query)
    if not match:
        return []
    noun = match.group(1)
    nouns = {noun}
    short_forms = {"袜子": "袜", "鞋子": "鞋", "裤子": "裤", "帽子": "帽"}
    for long, short in short_forms.items():
        if noun.endswith(long):
            nouns.add(noun[: -len(long)] + short)
    return [prefix + item for item in nouns for prefix in ("未穿", "不穿", "没穿", "没有穿", "没有", "无") if prefix + item != query]


def lexical_order(records, query):
    """Database-level equivalent of current TagCatalog/ZhDictionary search."""
    if HAN.search(query):
        variants = _chinese_variants(query)
        matched = []
        for record in records:
            label = record["zh_cn"]
            if not label:
                continue
            if label == query:
                rank = 0
            elif label.startswith(query):
                rank = 1
            elif query in label:
                rank = 2
            elif any(value in label for value in variants):
                rank = 3
            else:
                continue
            matched.append((rank, -record["post_count"], record["tag"]))
        matched.sort()
        return [item[2] for item in matched]
    normalized = _normalize_english(query)
    if not normalized:
        return []
    matched = []
    for record in records:
        fields = [record["tag"], *record["aliases"]]
        field_values = [_normalize_english(value) for value in fields]
        if normalized in field_values:
            rank = 0
        elif any(value.startswith(normalized) for value in field_values):
            rank = 1
        elif any(normalized in value for value in field_values):
            rank = 2
        else:
            continue
        matched.append((rank, -record["post_count"], record["tag"]))
    matched.sort()
    return [item[2] for item in matched]


def _accepted_indices(case, index):
    return [index[case["target"]], *(index[item] for item in case.get("alternatives", []))]


def rank_model(vectors, names, cases, encoder):
    index = {name: position for position, name in enumerate(names)}
    result = []
    query_vectors = []
    for start in range(0, len(cases), 32):
        query_vectors.extend(encoder.encode([case["query"] for case in cases[start:start+32]], "query: "))
    for case, query in zip(cases, query_vectors):
        scores = vectors @ query
        order = np.argsort(-scores, kind="stable")
        accepted = _accepted_indices(case, index)
        rank = min(int(np.flatnonzero(order == target)[0]) + 1 for target in accepted)
        conflict_rank = None
        conflict_score = None
        if case.get("conflict"):
            conflict_index = index[case["conflict"]]
            conflict_rank = int(np.flatnonzero(order == conflict_index)[0]) + 1
            conflict_score = float(scores[conflict_index])
        result.append(
            {
                **case,
                "rank": rank,
                "target_score": round(float(scores[index[case["target"]]]), 6),
                "conflict_rank": conflict_rank,
                "conflict_score": None if conflict_score is None else round(conflict_score, 6),
                "conflict_margin": None if conflict_score is None else round(float(scores[index[case["target"]]] - conflict_score), 6),
                "top5": [
                    {"tag": names[position], "score": round(float(scores[position]), 5)}
                    for position in order[:5]
                ],
                "query_embedding_ms": None,
            }
        )
    return result


def _percentile(values, percentile):
    if not values:
        return None
    return float(np.percentile(np.asarray(values, dtype=float), percentile, method="linear"))


def metric(items, corpus_size):
    ranks = [item if item is not None else corpus_size + 1 for item in items]
    if not ranks:
        return {"count": 0}
    return {
        "count": len(ranks),
        "top1": round(sum(rank <= 1 for rank in ranks) / len(ranks), 4),
        "top3": round(sum(rank <= 3 for rank in ranks) / len(ranks), 4),
        "top5": round(sum(rank <= 5 for rank in ranks) / len(ranks), 4),
        "top10": round(sum(rank <= 10 for rank in ranks) / len(ranks), 4),
        "top20": round(sum(rank <= 20 for rank in ranks) / len(ranks), 4),
        "top50": round(sum(rank <= 50 for rank in ranks) / len(ranks), 4),
        "mrr10": round(sum(1 / rank if rank <= 10 else 0 for rank in ranks) / len(ranks), 4),
        "median_rank": int(np.median(ranks)),
        "mean_rank": round(float(np.mean(ranks)), 2),
        "p90_rank": round(_percentile(ranks, 90), 2),
        "p95_rank": round(_percentile(ranks, 95), 2),
        "no_result": sum(item is None for item in items),
    }


def grouped_metrics(results, corpus_size):
    groups = {"all": results}
    keys = ["source", "query_type", "language", "group"]
    for key in keys:
        values = sorted({item.get(key) for item in results if item.get(key) is not None})
        for value in values:
            groups[f"{key}:{value}"] = [item for item in results if item.get(key) == value]
    return {name: metric([item.get("rank") for item in items], corpus_size)
            for name, items in groups.items()}


def conflict_metrics(results):
    values = [item for item in results if item.get("conflict_rank") is not None]
    return {
        "with_conflict": len(values),
        "conflict_before_target": sum(item["conflict_rank"] < item["rank"] for item in values),
        "conflict_before_target_rate": round(
            sum(item["conflict_rank"] < item["rank"] for item in values) / len(values), 4
        ) if values else None,
        "average_target_conflict_margin": round(
            statistics.mean(item["conflict_margin"] for item in values), 6
        ) if values else None,
        "negative_margin_count": sum(item["conflict_margin"] < 0 for item in values),
        "cases": [item for item in values if item["conflict_margin"] < 0],
    }


def stability(results):
    by_target = {}
    for item in results:
        if item["source"] != "paraphrase" or item.get("leakage"):
            continue
        by_target.setdefault(item["target"], []).append(item["rank"])
    rows = []
    for target, ranks in by_target.items():
        rows.append({
            "target": target,
            "count": len(ranks),
            "best_rank": min(ranks),
            "worst_rank": max(ranks),
            "median_rank": int(np.median(ranks)),
            "spread": max(ranks) - min(ranks),
            "variance": round(float(np.var(ranks)), 2),
        })
    return sorted(rows, key=lambda row: (-row["worst_rank"], -row["spread"], row["target"]))


def union_metrics(semantic, lexical, cases, corpus_size):
    rows = []
    for sem, lex, case in zip(semantic, lexical, cases):
        index = {name: position for position, name in enumerate(lex)}
        sem_top20 = {row["tag"] for row in sem["top5"]}  # overwritten below
        # The full semantic order is retained separately on each row.
        sem20 = set(sem["semantic_top20"])
        sem40 = set(sem["semantic_top40"])
        lex20 = set(lex["lexical_top20"])
        lex40 = set(lex["lexical_top40"])
        accepted = {case["target"], *case.get("alternatives", [])}
        rows.append({
            "target": case["target"],
            "union20_hit": bool(accepted & (sem20 | lex20)),
            "union40_hit": bool(accepted & (sem40 | lex40)),
            "union20_size": len(sem20 | lex20),
            "union40_size": len(sem40 | lex40),
        })
    return {
        "count": len(rows),
        "union20": {
            "recall": round(sum(row["union20_hit"] for row in rows) / len(rows), 4),
            "mean_candidate_set": round(statistics.mean(row["union20_size"] for row in rows), 2),
        },
        "union40": {
            "recall": round(sum(row["union40_hit"] for row in rows) / len(rows), 4),
            "mean_candidate_set": round(statistics.mean(row["union40_size"] for row in rows), 2),
        },
    }, rows


class _PROCESS_MEMORY_COUNTERS(ctypes.Structure):
    _fields_ = [("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]


def rss_mb():
    try:
        if sys.platform != "win32":
            return None
        counters = _PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        psapi = ctypes.WinDLL("Psapi.dll")
        kernel32 = ctypes.WinDLL("Kernel32.dll")
        get_info = psapi.GetProcessMemoryInfo
        get_info.argtypes = [ctypes.c_void_p, ctypes.POINTER(_PROCESS_MEMORY_COUNTERS), ctypes.c_ulong]
        get_info.restype = ctypes.c_int
        process = kernel32.GetCurrentProcess()
        if not get_info(process, ctypes.byref(counters), counters.cb):
            return None
        if counters.WorkingSetSize <= 0:
            return None
        return round(counters.WorkingSetSize / (1024 * 1024), 2)
    except Exception:
        return None


def percentile_summary(values):
    return {"median_ms": round(_percentile(values, 50), 3),
            "p90_ms": round(_percentile(values, 90), 3),
            "p95_ms": round(_percentile(values, 95), 3),
            "samples": len(values)}


def performance(directory, vectors, encoder, query, threads):
    cold = []
    for _ in range(30):
        started = time.perf_counter()
        session = Encoder(directory, threads=threads)
        cold.append((time.perf_counter() - started) * 1000)
        del session
        gc.collect()
    warm_query = []
    similarity = []
    total = []
    for _ in range(30):
        started = time.perf_counter()
        query_vector = encoder.encode([query], "query: ")[0]
        warm_query.append((time.perf_counter() - started) * 1000)
        started = time.perf_counter()
        scores = vectors @ query_vector
        np.argsort(-scores, kind="stable")[:50]
        similarity.append((time.perf_counter() - started) * 1000)
        started = time.perf_counter()
        query_vector = encoder.encode([query], "query: ")[0]
        scores = vectors @ query_vector
        np.argsort(-scores, kind="stable")[:50]
        total.append((time.perf_counter() - started) * 1000)
    return {
        "cold_model_load": percentile_summary(cold),
        "warm_query_embedding": percentile_summary(warm_query),
        "candidate_similarity_top50": percentile_summary(similarity),
        "total_semantic_query": percentile_summary(total),
        "rss_after_load_mb": rss_mb(),
    }


def enrich_model_results(results, vectors, names, cases, lexical):
    index = {name: position for position, name in enumerate(names)}
    for row, case in zip(results, cases):
        query_vector = None
        # ``rank_model`` already computed the rank; obtain deterministic full
        # order only for union recall and do not expose the entire ranking.
        # The caller fills these private fields immediately after query encode.
        del query_vector
    return results


def evaluate_model(vectors, names, cases, encoder, lexical_rows):
    index = {name: position for position, name in enumerate(names)}
    results = []
    query_vectors = []
    for start in range(0, len(cases), 32):
        query_vectors.extend(encoder.encode([case["query"] for case in cases[start:start+32]], "query: "))
    for case, query in zip(cases, query_vectors):
        scores = vectors @ query
        order = np.argsort(-scores, kind="stable")
        accepted = _accepted_indices(case, index)
        rank = min(int(np.flatnonzero(order == target)[0]) + 1 for target in accepted)
        conflict_rank = None
        conflict_score = None
        if case.get("conflict"):
            conflict_idx = index[case["conflict"]]
            conflict_rank = int(np.flatnonzero(order == conflict_idx)[0]) + 1
            conflict_score = float(scores[conflict_idx])
        lexical = lexical_order(lexical_rows, case["query"])
        results.append({
            **case,
            "rank": rank,
            "conflict_rank": conflict_rank,
            "target_score": round(float(scores[index[case["target"]]]), 6),
            "conflict_score": None if conflict_score is None else round(conflict_score, 6),
            "conflict_margin": None if conflict_score is None else round(float(scores[index[case["target"]]] - conflict_score), 6),
            "top5": [{"tag": names[pos], "score": round(float(scores[pos]), 5)} for pos in order[:5]],
            "semantic_top20": [names[pos] for pos in order[:20]],
            "semantic_top40": [names[pos] for pos in order[:40]],
            "lexical_rank": (lexical.index(case["target"]) + 1) if case["target"] in lexical else None,
            "lexical_top20": lexical[:20],
            "lexical_top40": lexical[:40],
        })
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dictionary", type=Path, default=ROOT / "tool/.tmp/translation-audit/ffdkj.sqlite")
    parser.add_argument("--output", type=Path, default=ROOT / "tool/.tmp/semantic-search/paraphrase")
    parser.add_argument("--threads", type=int, choices=[1, 2, 4], default=4)
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "tool/.tmp").resolve()):
        raise ValueError("Output must remain under tool/.tmp")
    output.mkdir(parents=True, exist_ok=True)
    catalog_path = ROOT / "assets/databases/tag_catalog.db"
    records, db_metadata, translation_columns = load_catalog(catalog_path, args.dictionary.resolve())
    names = [record["tag"] for record in records]
    seed_path = Path(__file__).with_name("semantic_paraphrase_cases.json")
    hard_path = Path(__file__).with_name("semantic_paraphrase_hard_cases.json")
    holdout_path = Path(__file__).with_name("cases.json")
    cases_all, by_tag = build_cases(records, args.dictionary.resolve(), seed_path, hard_path, holdout_path)
    cases_path = output / "cases.json"
    cases_path.write_text(json.dumps(cases_all, ensure_ascii=False, indent=2), encoding="utf-8")
    clean_cases = [case for case in cases_all if not case["leakage"]]
    leaked_cases = [case for case in cases_all if case["leakage"]]
    if sum(case["source"] == "paraphrase" for case in clean_cases) < 300:
        raise RuntimeError("Leakage filtering left fewer than 300 clean paraphrase cases")
    texts = {variant: candidate_texts(records, variant) for variant in ("minimal", "enhanced-existing")}
    models = [
        ("intfloat/multilingual-e5-small", ROOT / "tool/.tmp/semantic-search", 384),
        ("intfloat/multilingual-e5-base", ROOT / "tool/.tmp/semantic-search/e5-base", 768),
    ]
    reports = []
    performance_report = {}
    for model, directory, dimensions in models:
        encoder = Encoder(directory, args.threads)
        variant_results = {}
        for variant in ("minimal", "enhanced-existing"):
            metadata = _metadata(catalog_path, args.dictionary.resolve(), directory, texts[variant], dimensions, variant)
            verify_model(metadata, dimensions)
            vectors, cache, reused, build_seconds = encode_cache(
                directory, texts[variant], dimensions, metadata, args.threads, args.timeout
            )
            results = evaluate_model(vectors, names, clean_cases, encoder, records)
            # Derive lexical/semantic union sets from the full rankings kept
            # on each semantic result row.
            union_rows = []
            for row, case in zip(results, clean_cases):
                accepted = {case["target"], *case.get("alternatives", [])}
                sem20, sem40 = set(row["semantic_top20"]), set(row["semantic_top40"])
                lex20, lex40 = set(row["lexical_top20"]), set(row["lexical_top40"])
                union_rows.append({
                    "target": case["target"],
                    "union20_hit": bool(accepted & (sem20 | lex20)),
                    "union40_hit": bool(accepted & (sem40 | lex40)),
                    "union20_size": len(sem20 | lex20),
                    "union40_size": len(sem40 | lex40),
                })
            union = {
                "count": len(union_rows),
                "union20": {"recall": round(sum(r["union20_hit"] for r in union_rows) / len(union_rows), 4), "mean_candidate_set": round(statistics.mean(r["union20_size"] for r in union_rows), 2)},
                "union40": {"recall": round(sum(r["union40_hit"] for r in union_rows) / len(union_rows), 4), "mean_candidate_set": round(statistics.mean(r["union40_size"] for r in union_rows), 2)},
            }
            lexical_results = []
            for case in clean_cases:
                lexical = lexical_order(records, case["query"])
                lexical_results.append({**case, "rank": (lexical.index(case["target"]) + 1) if case["target"] in lexical else None, "conflict_rank": (lexical.index(case["conflict"]) + 1) if case.get("conflict") and case["conflict"] in lexical else None, "lexical_top20": lexical[:20], "lexical_top40": lexical[:40]})
            variant_results[variant] = {
                "model": model,
                "variant": variant,
                "cache": cache.name,
                "cache_reused": reused,
                "build_seconds": round(build_seconds, 3),
                "metadata": metadata,
                "metrics": grouped_metrics(results, len(names)),
                "conflicts": conflict_metrics(results),
                "union": union,
                "details": results,
            }
            variant_results[f"lexical-{variant}"] = {
                "model": "production-lexical-equivalent",
                "variant": variant,
                "metrics": grouped_metrics(lexical_results, len(names)),
                "conflicts": {"with_conflict": sum(r["conflict_rank"] is not None for r in lexical_results), "conflict_before_target": sum(r["conflict_rank"] is not None and r["rank"] is not None and r["conflict_rank"] < r["rank"] for r in lexical_results), "conflict_before_target_rate": None, "average_target_conflict_margin": None, "negative_margin_count": 0, "cases": []},
                "details": lexical_results,
            }
            del vectors
        # Performance against the actual enhanced matrix, loaded from cache.
        enhanced = variant_results["enhanced-existing"]
        enhanced_vectors = np.load(directory / enhanced["cache"], mmap_mode="r", allow_pickle=False)
        performance_report[model] = performance(directory, enhanced_vectors, encoder, clean_cases[0]["query"], args.threads)
        del enhanced_vectors
        reports.append({"model": model, "variants": variant_results})
    summary = {
        "candidate_count": len(records),
        "category_counts": {str(category): sum(record["category"] == category for record in records) for category in (0, 7)},
        "database": {"path": str(catalog_path), "bytes": catalog_path.stat().st_size, "sha256": sha256(catalog_path), "metadata": db_metadata, "translation_columns": sorted(translation_columns), "dictionary_path": str(args.dictionary.resolve()), "dictionary_sha256": sha256(args.dictionary.resolve())},
        "case_count_all": len(cases_all),
        "case_count_clean": len(clean_cases),
        "leakage_count_excluded": len(leaked_cases),
        "leakage_cases": leaked_cases,
        "source_counts_all": {source: sum(case["source"] == source for case in cases_all) for source in sorted({case["source"] for case in cases_all})},
        "source_counts_clean": {source: sum(case["source"] == source for case in clean_cases) for source in sorted({case["source"] for case in clean_cases})},
        "stability": {report["model"]: stability(report["variants"]["enhanced-existing"]["details"]) for report in reports},
        "performance": performance_report,
        "reports": reports,
        "case_sha256": sha256(cases_path),
        "runtime": {"numpy": np.__version__, "threads": args.threads, "provider": "CPUExecutionProvider"},
    }
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in summary.items() if key not in ("reports", "leakage_cases", "stability", "performance")}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
