"""Offline, read-only horizontal test of compact Chinese retrieval models.

This script intentionally lives outside the Flutter build.  It reuses the
clean case manifest from the previous benchmark, the unchanged category 0+7
catalog, and only existing Chinese labels.  Model/corpus vectors are cached
under ``tool/.tmp`` so an interrupted run can be resumed without touching
application data.
"""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import statistics
import time
from typing import Iterable

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("OMP_NUM_THREADS", "2")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

from semantic_paraphrase_benchmark import load_catalog, sha256

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets/databases/tag_catalog.db"
DICTIONARY = ROOT / "tool/.tmp/translation-audit/ffdkj.sqlite"
MANIFEST = ROOT / "tool/.tmp/semantic-search/paraphrase/cases.json"
WORK = ROOT / "tool/.tmp/semantic-model-comparison"

# These are the small, manually reviewed set of “I don't want X, therefore
# retrieve X's opposite” cases excluded from the production-facing score.
# Absence-state targets (no_socks, no_shoes, untucked_shirt, etc.) stay in.
REVERSE_NEGATION_EXCLUDE_IDS = {
    "hard-005-4", "hard-006-5", "hard-009-2", "hard-010-3",
    "hard-011-2", "hard-011-4", "hard-012-3", "hard-013-2",
    "hard-013-5", "hard-014-2", "hard-014-4", "hard-015-4",
    "hard-016-4", "hard-018-4", "hard-019-1", "hard-019-4",
    # This one is the required negative phrasing but its requested target is
    # an opposite state; keep it out of the primary score while retaining it
    # in the raw case inventory and case appendix.
    "r-017",
}

MODEL_SPECS = {
    "e5-small": {
        "label": "E5-small",
        "model_id": "intfloat/multilingual-e5-small",
        "directory": ROOT / "tool/.tmp/semantic-search",
        "dimensions": 384,
        "query_prefix": "query: ",
        "document_prefix": "passage: ",
        "revision": "614241f622f53c4eeff9890bdc4f31cfecc418b3",
        "encoding": "E5 query:/passage: prefixes; mean pooling; L2",
    },
    "m3e-small": {
        "label": "M3E-small",
        "model_id": "moka-ai/m3e-small",
        "directory": WORK / "m3e-small-onnx",
        "dimensions": 512,
        "query_prefix": "",
        "document_prefix": "",
        "revision": "main (downloaded model files; SHA-256 recorded below)",
        "encoding": "plain text; mean pooling; L2 (SentenceTransformers-compatible)",
    },
    "bge-small": {
        "label": "BGE-small-zh-v1.5",
        "model_id": "BAAI/bge-small-zh-v1.5 (Xenova ONNX conversion)",
        "directory": WORK / "bge-small-zh-v1.5",
        "dimensions": 512,
        # BGE's model card recommends this instruction for short retrieval
        # queries; passages do not receive an instruction.
        "query_prefix": "为这个句子生成表示以用于检索相关文章：",
        "document_prefix": "",
        "revision": "main (Xenova conversion; SHA-256 recorded below)",
        "encoding": "BGE Chinese retrieval instruction on queries; mean pooling; L2",
    },
}


def _rss_mb() -> float | None:
    """Return this process' working set on Windows, when available."""
    try:
        import psutil
        return psutil.Process().memory_info().rss / (1024 * 1024)
    except Exception:
        pass
    try:
        import ctypes
        from ctypes import wintypes
        class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]
        counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        handle = ctypes.windll.kernel32.GetCurrentProcess()
        if ctypes.windll.psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return counters.WorkingSetSize / (1024 * 1024)
    except Exception:
        return None
    return None


def _tokenizer_pad_id(tokenizer: Tokenizer) -> int:
    for token in ("[PAD]", "<pad>", "<PAD>"):
        found = tokenizer.token_to_id(token)
        if found is not None:
            return int(found)
    return 0


class OnnxEncoder:
    def __init__(self, directory: Path, threads: int = 2):
        self.directory = directory
        self.tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
        self.pad_id = _tokenizer_pad_id(self.tokenizer)
        self.tokenizer.enable_truncation(max_length=128)
        pad_token = self.tokenizer.id_to_token(self.pad_id) or "[PAD]"
        self.tokenizer.enable_padding(pad_id=self.pad_id, pad_token=pad_token)
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(
            str(directory / "model.onnx"), sess_options=options,
            providers=["CPUExecutionProvider"],
        )

    def encode(self, texts: Iterable[str], prefix: str = "") -> np.ndarray:
        texts = list(texts)
        encoded = self.tokenizer.encode_batch([prefix + text for text in texts])
        values = {
            "input_ids": np.asarray([e.ids for e in encoded], dtype=np.int64),
            "attention_mask": np.asarray([e.attention_mask for e in encoded], dtype=np.int64),
            "token_type_ids": np.asarray([e.type_ids for e in encoded], dtype=np.int64),
        }
        inputs = {item.name: values[item.name] for item in self.session.get_inputs()
                  if item.name in values}
        hidden = self.session.run(None, inputs)[0]
        if hidden.ndim != 3:
            raise ValueError(f"Expected last_hidden_state, got {hidden.shape}")
        mask = values["attention_mask"][..., None].astype(np.float32)
        pooled = (hidden * mask).sum(axis=1) / np.maximum(mask.sum(axis=1), 1.0)
        norm = np.linalg.norm(pooled, axis=1, keepdims=True)
        if not np.isfinite(pooled).all() or (norm == 0).any():
            raise ValueError("Invalid embedding")
        return (pooled / norm).astype(np.float32)


def _load_records() -> list[dict]:
    records, _metadata, _columns = load_catalog(CATALOG, DICTIONARY)
    return records


def _document_texts(records: list[dict], variant: str) -> list[str]:
    texts = []
    for record in records:
        if variant == "bge-zh":
            # The only allowed fallback is the canonical English tag.  No
            # aliases, generated translations, or descriptions are added.
            texts.append(record["zh_cn"] or record["tag"])
        else:
            fields = [record["tag"]]
            if record["zh_cn"]:
                fields.append(record["zh_cn"])
            texts.append("; ".join(fields))
    return texts


def _cache_vectors(spec: dict, records: list[dict], variant: str, threads: int, batch: int) -> tuple[np.ndarray, dict]:
    texts = _document_texts(records, variant)
    directory = Path(spec["directory"])
    metadata = {
        "model_id": spec["model_id"],
        "revision": spec["revision"],
        "model_sha256": sha256(directory / "model.onnx"),
        "tokenizer_sha256": sha256(directory / "tokenizer.json"),
        "candidate_variant": variant,
        "candidate_sha256": hashlib.sha256(json.dumps(texts, ensure_ascii=False).encode()).hexdigest(),
        "candidate_count": len(texts),
        "dimensions": spec["dimensions"],
    }
    key = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()[:24]
    cache = WORK / f"vectors-{spec['model_id'].replace('/', '_')}-{variant}-{key}.npy"
    if cache.exists():
        vectors = np.load(cache, mmap_mode="r", allow_pickle=False)
        if vectors.shape != (len(texts), spec["dimensions"]):
            raise ValueError(f"Invalid vector cache shape: {cache}")
        return vectors, {**metadata, "cache": str(cache), "cache_reused": True}

    started = time.perf_counter()
    partial = cache.with_suffix(".partial.npy")
    progress = cache.with_suffix(".progress")
    completed = int(progress.read_text(encoding="utf-8")) if progress.exists() else 0
    if not 0 <= completed <= len(texts):
        raise ValueError("Invalid vector checkpoint")
    encoder = OnnxEncoder(directory, threads)
    vectors = np.lib.format.open_memmap(
        partial, mode="r+" if completed else "w+", dtype=np.float32,
        shape=(len(texts), spec["dimensions"]),
    )
    # Grouping is intentionally deterministic and independent of target cases.
    order = sorted(range(len(texts)), key=lambda i: (len(texts[i]), i))
    for start in range(completed, len(texts), batch):
        positions = order[start:start + batch]
        vectors[positions] = encoder.encode([texts[i] for i in positions], spec["document_prefix"])
        vectors.flush()
        progress.write_text(str(start + len(positions)), encoding="utf-8")
        if start % (batch * 32) == 0:
            print(f"{spec['label']} {variant}: encoded {start}/{len(texts)} ({time.perf_counter()-started:.1f}s)", flush=True)
    np.save(cache, vectors, allow_pickle=False)
    del vectors
    partial.unlink(missing_ok=True)
    progress.unlink(missing_ok=True)
    return np.load(cache, mmap_mode="r", allow_pickle=False), {
        **metadata, "cache": str(cache), "cache_reused": False,
        "encode_seconds": round(time.perf_counter() - started, 2),
    }


def _top_indices(scores: np.ndarray, limit: int = 5) -> np.ndarray:
    take = min(limit, len(scores))
    idx = np.argpartition(-scores, take - 1)[:take]
    return idx[np.argsort(-scores[idx], kind="stable")]


def _rank(scores: np.ndarray, index: int) -> int:
    value = float(scores[index])
    # Stable tie handling: candidates appearing earlier in catalog order win.
    return 1 + int(np.count_nonzero(scores > value)) + int(np.count_nonzero(scores[:index] == value))


def _evaluate(spec: dict, vectors: np.ndarray, records: list[dict], cases: list[dict], variant: str) -> tuple[list[dict], dict]:
    names = [r["tag"] for r in records]
    index = {name: i for i, name in enumerate(names)}
    encoder = OnnxEncoder(Path(spec["directory"]))
    results = []
    for case in cases:
        query = encoder.encode([case["query"]], spec["query_prefix"])[0]
        scores = vectors @ query
        accepted = [case["target"], *case.get("alternatives", [])]
        ranks = [_rank(scores, index[tag]) for tag in accepted if tag in index]
        if not ranks:
            continue
        order = _top_indices(scores, 5)
        results.append({
            "id": case["id"], "source": case["source"], "query": case["query"],
            "target": case["target"], "rank": min(ranks), "variant": variant,
            "top5": [{"tag": names[i], "score": round(float(scores[i]), 6)} for i in order],
        })
    ranks = [int(r["rank"]) for r in results]
    return results, _metrics(ranks, len(results))


def _metrics(ranks: list[int], n: int | None = None) -> dict:
    n = len(ranks) if n is None else n
    if not ranks:
        return {"n": n, "top1": 0.0, "top5": 0.0, "top20": 0.0, "top50": 0.0, "mrr10": 0.0, "median_rank": None}
    return {
        "n": n,
        "top1": round(sum(r <= 1 for r in ranks) / n, 6),
        "top5": round(sum(r <= 5 for r in ranks) / n, 6),
        "top20": round(sum(r <= 20 for r in ranks) / n, 6),
        "top50": round(sum(r <= 50 for r in ranks) / n, 6),
        "mrr10": round(sum((1 / r if r <= 10 else 0) for r in ranks) / n, 6),
        "median_rank": int(statistics.median(ranks)),
    }


def _performance(spec: dict, vectors: np.ndarray, threads: int, samples: int = 20) -> dict:
    directory = Path(spec["directory"])
    # Cold-load timings are intentionally separate from the warmed encoder.
    cold = []
    for _ in range(samples):
        begin = time.perf_counter()
        OnnxEncoder(directory, threads)
        cold.append((time.perf_counter() - begin) * 1000)
    rss_before = _rss_mb()
    encoder = OnnxEncoder(directory, threads)
    rss_after = _rss_mb()
    query = "衣服不要塞进裙子"
    warm = []
    sim = []
    total = []
    for _ in range(samples):
        begin = time.perf_counter()
        q = encoder.encode([query], spec["query_prefix"])[0]
        warm.append((time.perf_counter() - begin) * 1000)
        begin = time.perf_counter()
        _ = vectors @ q
        sim.append((time.perf_counter() - begin) * 1000)
        begin = time.perf_counter()
        q = encoder.encode([query], spec["query_prefix"])[0]
        _ = vectors @ q
        total.append((time.perf_counter() - begin) * 1000)
    return {
        "model_file_bytes": (directory / "model.onnx").stat().st_size,
        "tokenizer_bytes": (directory / "tokenizer.json").stat().st_size,
        "dimensions": spec["dimensions"],
        "samples": samples,
        "cold_load_ms": _distribution(cold),
        "warm_query_embedding_ms": _distribution(warm),
        "full_corpus_similarity_ms": _distribution(sim),
        "total_query_ms": _distribution(total),
        "rss_before_mb": None if rss_before is None else round(rss_before, 1),
        "rss_after_load_mb": None if rss_after is None else round(rss_after, 1),
        "rss_delta_mb": None if rss_before is None or rss_after is None else round(rss_after - rss_before, 1),
    }


def _distribution(values: list[float]) -> dict:
    return {"median": round(statistics.median(values), 3), "p95": round(float(np.percentile(values, 95)), 3)}


def _production_cases(all_cases: list[dict]) -> tuple[list[dict], list[dict]]:
    clean = [c for c in all_cases if not c.get("leakage")]
    excluded = [c for c in clean if c["id"] in REVERSE_NEGATION_EXCLUDE_IDS]
    production = [c for c in clean if c["id"] not in REVERSE_NEGATION_EXCLUDE_IDS]
    return production, excluded


def _important_cases(cases: list[dict]) -> list[dict]:
    targets = ["untucked_shirt", "no_socks", "hands_on_hips", "hand_on_hip", "v_sign",
               "double_ponytail", "clothing_lift", "unbuttoned_shirt", "one_eye_closed",
               "closed_eyes", "looking_at_viewer", "from_behind"]
    # Keep every clean required-case row so the five untucked-shirt and five
    # no-socks utterances remain visible in the final comparison.  Then add a
    # single representative from the other user-facing targets requested in
    # the brief.
    selected = [case for case in cases if case["source"] == "required-case"]
    seen = {case["id"] for case in selected}
    for target in targets:
        for case in cases:
            if case["target"] == target and case["id"] not in seen:
                selected.append(case)
                seen.add(case["id"])
                break
    return selected


def _render_report(data: dict, report_path: Path) -> None:
    lines = ["# Semantic Model Comparison", "", "## 1. Executive Summary", ""]
    summary = data["summary"]
    lines += [summary, "", "## 2. Dataset", "",
              f"- Reused clean manifest: `{data['dataset']['manifest']}`; original clean cases: **{data['dataset']['clean_count']}**.",
              f"- Production-relevant subset: **{data['dataset']['production_count']}** (excluded **{data['dataset']['excluded_count']}** manually reviewed reverse-negation cases).",
              f"- Candidates unchanged: category 0 + 7, **{data['dataset']['candidate_count']}** tags.",
              "- Document A: canonical English tag + existing `zh_cn`; no aliases, generated translations, or online calls.",
              "", "Excluded IDs: " + ", ".join(data["dataset"]["excluded_ids"]), ""]
    lines += ["## 3. Models", "", "| Model | Revision | Dim | ONNX bytes | Model SHA-256 | Encoding |", "|---|---|---:|---:|---|---|"]
    for key, spec in MODEL_SPECS.items():
        profile = data["models"][key]
        file_bytes = profile.get("performance", {}).get("model_file_bytes")
        if file_bytes is None:
            file_bytes = (Path(spec["directory"]) / "model.onnx").stat().st_size
        model_sha = profile.get("vector", {}).get("model_sha256", "—")
        lines.append(f"| {spec['label']} | `{spec['revision']}` | {spec['dimensions']} | {file_bytes:,} | `{model_sha}` | {spec['encoding']} |")
    lines += ["", "## 4. Main Results", "", "| Model | N | Top-1 | Top-5 | Top-20 | Top-50 | MRR@10 | Median rank |", "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for key in MODEL_SPECS:
        m = data["models"][key]["metrics"]["production"]
        lines.append(f"| {MODEL_SPECS[key]['label']} | {m['n']} | {m['top1']:.1%} | {m['top5']:.1%} | {m['top20']:.1%} | {m['top50']:.1%} | {m['mrr10']:.1%} | {m['median_rank']} |")
    lines += ["", "### By subset", "", "| Subset | E5 Top20 | M3E Top20 | BGE Top20 | N |", "|---|---:|---:|---:|---:|"]
    for subset in ("paraphrase", "real-world-holdout", "required-case"):
        row = [data["models"][k]["metrics"].get(subset, {}).get("top20", 0) for k in MODEL_SPECS]
        n = data["models"]["e5-small"]["metrics"].get(subset, {}).get("n", 0)
        lines.append(f"| {subset} | {row[0]:.1%} | {row[1]:.1%} | {row[2]:.1%} | {n} |")
    lines += ["", "## 5. Required Case Comparison", "", "| Query | Expected | E5 rank / Top-5 | M3E rank / Top-5 | BGE rank / Top-5 |", "|---|---|---|---|---|"]
    for case in data["important_cases"]:
        cells = []
        for key in MODEL_SPECS:
            item = data["case_results"][key].get(case["id"])
            cells.append("—" if not item else f"{item['rank']} / " + ", ".join(x["tag"] for x in item["top5"]))
        lines.append(f"| {case['query']} | `{case['target']}` | {cells[0]} | {cells[1]} | {cells[2]} |")
    lines += ["", "## 6. BGE Chinese-only Ablation", "", "| Variant | Top-1 | Top-5 | Top-20 | Top-50 | MRR@10 | Median rank |", "|---|---:|---:|---:|---:|---:|---:|"]
    for variant, m in data["bge_ablation"].items():
        lines.append(f"| {variant} | {m['top1']:.1%} | {m['top5']:.1%} | {m['top20']:.1%} | {m['top50']:.1%} | {m['mrr10']:.1%} | {m['median_rank']} |")
    lines += ["", "## 7. Performance", "", "| Model | File | RSS delta MB | Cold load median/P95 ms | Query embedding median/P95 ms | Similarity median/P95 ms | Total median/P95 ms |", "|---|---:|---:|---:|---:|---:|---:|"]
    for key, model in data["models"].items():
        p = model["performance"]
        if not p:
            continue
        f = lambda x: f"{x['median']:.1f}/{x['p95']:.1f}"
        rss = "—" if p.get("rss_delta_mb") is None else f"{p['rss_delta_mb']:.1f}"
        lines.append(f"| {MODEL_SPECS[key]['label']} | {p['model_file_bytes'] / 1e6:.1f} MB | {rss} | {f(p['cold_load_ms'])} | {f(p['warm_query_embedding_ms'])} | {f(p['full_corpus_similarity_ms'])} | {f(p['total_query_ms'])} |")
    lines += ["", "RSS is the process working-set change after loading the ONNX session; it is approximate and includes runtime overhead. Windows CPU timings are not Snapdragon 8 Gen 3 Android timings.", "", "## Reproduction", "", "```powershell", "tool/.tmp/semantic-search/venv/Scripts/python.exe tool/semantic_search/semantic_model_comparison.py --threads 2 --batch 64", "```", "", "## 8. Recommendation", "", data["recommendation"], ""]
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threads", type=int, choices=[1, 2, 4], default=2)
    parser.add_argument("--batch", type=int, choices=[16, 32, 64, 128], default=64)
    parser.add_argument("--skip-performance", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    records = _load_records()
    all_cases = json.loads(MANIFEST.read_text(encoding="utf-8"))
    production, excluded = _production_cases(all_cases)
    previous = {}
    previous_path = WORK / "comparison.json"
    if args.skip_performance and previous_path.exists():
        previous = json.loads(previous_path.read_text(encoding="utf-8"))
    report_data = {
        "dataset": {
            "manifest": str(MANIFEST), "all_count": len(all_cases),
            "clean_count": len([c for c in all_cases if not c.get("leakage")]),
            "production_count": len(production), "excluded_count": len(excluded),
            "excluded_ids": [c["id"] for c in excluded], "candidate_count": len(records),
        },
        "models": {}, "case_results": {}, "bge_ablation": {},
        "important_cases": _important_cases(production),
    }
    for key, spec in MODEL_SPECS.items():
        variant = "bge-a" if key == "bge-small" else "canonical-a"
        vectors, vector_meta = _cache_vectors(spec, records, variant, args.threads, args.batch)
        metrics = {}
        case_results = {}
        for subset, subset_cases in {
            "production": production,
            "paraphrase": [c for c in production if c["source"] == "paraphrase"],
            "real-world-holdout": [c for c in production if c["source"] == "real-world-holdout"],
            "required-case": [c for c in production if c["source"] == "required-case"],
        }.items():
            rows, m = _evaluate(spec, vectors, records, subset_cases, variant)
            metrics[subset] = m
            if subset == "production":
                case_results = {row["id"]: row for row in rows}
        performance = _performance(spec, vectors, args.threads) if not args.skip_performance else previous.get("models", {}).get(key, {}).get("performance", {})
        report_data["models"][key] = {"vector": vector_meta, "metrics": metrics, "performance": performance}
        report_data["case_results"][key] = case_results
        print(f"{spec['label']}: {metrics['production']}", flush=True)

        if key == "bge-small":
            zh_vectors, zh_meta = _cache_vectors(spec, records, "bge-zh", args.threads, args.batch)
            _rows, zh_metrics = _evaluate(spec, zh_vectors, records, production, "bge-zh")
            report_data["bge_ablation"] = {"BGE-A (tag + zh_cn)": metrics["production"],
                                           "BGE-ZH (zh_cn only; English fallback)": zh_metrics}
            report_data["models"][key]["bge_zh_vector"] = zh_meta

    e5 = report_data["models"]["e5-small"]["metrics"]["production"]
    m3e = report_data["models"]["m3e-small"]["metrics"]["production"]
    bge = report_data["models"]["bge-small"]["metrics"]["production"]
    candidates = [(m3e["top20"] - e5["top20"], "M3E-small", m3e), (bge["top20"] - e5["top20"], "BGE-small-zh-v1.5", bge), (0.0, "E5-small", e5)]
    best_gain, best_name, best = max(candidates, key=lambda x: x[0])
    if best_name == "E5-small" or best_gain < 0.04:
        report_data["summary"] = f"E5-small remains the practical baseline. Best Top-20 gain is {best_gain * 100:+.1f} pp ({best_name}); this is below the 4 pp meaningful-advantage threshold, so there is no evidence to replace E5-small yet."
        report_data["recommendation"] = "Keep E5-small as the Android prototype baseline. Neither M3E nor BGE shows a meaningful enough Top-20 improvement on the production-relevant subset to justify a model switch; continue only with targeted Android profiling if a Chinese-only BGE path is otherwise attractive. Continued horizontal swapping among same-size embedding models may have limited returns."
    else:
        report_data["summary"] = f"{best_name} is best on the production-relevant subset, improving Top-20 by {best_gain * 100:+.1f} pp over E5-small."
        report_data["recommendation"] = f"Continue Android prototyping with {best_name}, then confirm on-device quality and latency before replacing E5-small."
    report_data["runtime"] = {"onnxruntime": ort.__version__, "threads": args.threads, "provider": "CPUExecutionProvider"}
    report_path = ROOT / "tool/semantic_search/semantic_model_comparison_report.md"
    _render_report(report_data, report_path)
    (WORK / "comparison.json").write_text(json.dumps(report_data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(report_path), "production_count": len(production), "e5": e5, "m3e": m3e, "bge": bge}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
