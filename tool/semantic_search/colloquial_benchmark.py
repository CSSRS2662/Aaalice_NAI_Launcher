"""Complex colloquial-query robustness benchmark for the autocomplete corpus.

This is an evaluation-only artifact.  It deliberately reuses labels already
present in the checked-in/external dictionaries and wraps them in longer,
conversational Chinese sentences.  It does not add aliases, translations, or
runtime behaviour to the application.  The previous hand-written examples in
``cases.json`` are included as a small real-query holdout.
"""
import argparse
import hashlib
import json
import re
import time
from pathlib import Path

import numpy as np

from benchmark_300 import current_cache, load_candidates
from evaluate import Encoder, ROOT, corpus, sha256


HAN = re.compile(r"[\u3400-\u9fff]")
FORCED = {
    "untucked_shirt", "shirt_tucked_in", "shirt_partially_tucked_in",
    "no_socks", "socks", "short_hair", "long_hair", "closed_eyes",
    "eyes_closed", "one_eye_closed", "open_mouth", "closed_mouth",
}

# These are only used to measure whether a plausible opposite outranks the
# requested tag.  They are not aliases and are not written to the app catalog.
OPPOSITES = {
    "untucked_shirt": "shirt_tucked_in",
    "shirt_tucked_in": "untucked_shirt",
    "shirt_partially_tucked_in": "untucked_shirt",
    "no_socks": "socks",
    "socks": "no_socks",
    "short_hair": "long_hair",
    "long_hair": "short_hair",
    "closed_eyes": "one_eye_closed",
    "eyes_closed": "one_eye_closed",
    "one_eye_closed": "closed_eyes",
    "open_mouth": "closed_mouth",
    "closed_mouth": "open_mouth",
}

TEMPLATES = (
    "我想让画面里的角色呈现“{label}”这个效果",
    "请把这张图的重点放在“{label}”，其他条件保持不变",
    "我需要的是“{label}”这种状态，不是相近的另一种效果",
)


def _hash(name):
    return hashlib.sha256(name.encode()).hexdigest()


def choose_labels(rows, count=60):
    """Choose a deterministic, category-balanced set with existing labels."""
    candidates = [row for row in rows if len(HAN.findall(row[3] or "")) >= 3]
    by_category = {category: [row for row in candidates if row[1] == category]
                   for category in (0, 7)}
    selected = []
    per_category = count // 2
    for category in (0, 7):
        values = by_category[category]
        forced = [row for row in values if row[0] in FORCED]
        forced.sort(key=lambda row: _hash(row[0]))
        remaining = [row for row in values if row[0] not in {item[0] for item in forced}]
        remaining.sort(key=lambda row: _hash(row[0]))
        selected.extend((forced + remaining)[:per_category])
    if len(selected) != count:
        raise ValueError(f"could not select {count} labels")
    return sorted(selected, key=lambda row: (row[1], _hash(row[0])))


def build_cases(rows, manual_path, label_count=60):
    selected = choose_labels(rows, label_count)
    cases = []
    for name, category, post_count, label in selected:
        for template_index, template in enumerate(TEMPLATES, 1):
            cases.append({
                "source": "existing-label-template",
                "language": "zh",
                "template": template_index,
                "tag": name,
                "category": category,
                "post_count": post_count,
                "label": label,
                "query": template.format(label=label),
                "opposite": OPPOSITES.get(name),
            })
    # Existing hand-written cases are a holdout; no new translation is made.
    for item in json.loads(manual_path.read_text(encoding="utf-8")):
        cases.append({
            **item,
            "source": "existing-manual-case",
            # Check kana first because Japanese sentences commonly contain
            # CJK ideographs as well as hiragana/katakana.
            "language": "ja" if re.search(r"[\u3040-\u30ff]", item["query"]) else
                        ("zh" if re.search(r"[\u3400-\u9fff]", item["query"]) else "en"),
            "tag": item["target"],
        })
    return cases


def _accepted(case, index):
    return [index[case["tag"]], *(index[item] for item in case.get("alternatives", []))]


def rank_cases(vectors, names, cases, encoder):
    index = {name: i for i, name in enumerate(names)}
    for case in cases:
        if case["tag"] not in index:
            raise ValueError(f"missing target: {case}")
        if case.get("opposite") and case["opposite"] not in index:
            raise ValueError(f"missing opposite: {case}")
        for alternative in case.get("alternatives", []):
            if alternative not in index:
                raise ValueError(f"missing alternative: {case}")
    output = []
    started = time.monotonic()
    for start in range(0, len(cases), 32):
        batch = cases[start:start + 32]
        queries = encoder.encode([case["query"] for case in batch], "query: ")
        for case, query in zip(batch, queries):
            scores = vectors @ query
            order = np.argsort(-scores, kind="stable")
            accepted = _accepted(case, index)
            target_rank = min(int(np.flatnonzero(order == item)[0]) + 1 for item in accepted)
            opposite_rank = None
            if case.get("opposite"):
                opposite_rank = int(np.flatnonzero(order == index[case["opposite"]])[0]) + 1
            output.append({
                **case,
                "rank": target_rank,
                "opposite_rank": opposite_rank,
                "top5": [{"tag": names[i], "score": round(float(scores[i]), 5)}
                          for i in order[:5]],
            })
    return output, time.monotonic() - started


def metric(values):
    if not values:
        return {"count": 0, "top1": None, "top5": None, "top20": None,
                "mrr10": None, "median_rank": None, "mean_rank": None}
    return {
        "count": len(values),
        "top1": round(sum(rank <= 1 for rank in values) / len(values), 4),
        "top5": round(sum(rank <= 5 for rank in values) / len(values), 4),
        "top20": round(sum(rank <= 20 for rank in values) / len(values), 4),
        "mrr10": round(sum(1 / rank if rank <= 10 else 0 for rank in values) / len(values), 4),
        "median_rank": int(np.median(values)),
        "mean_rank": round(float(np.mean(values)), 2),
    }


def summarize(results):
    groups = {
        "overall": results,
        "existing-label-template": [item for item in results
                                     if item["source"] == "existing-label-template"],
        "existing-manual-case": [item for item in results
                                  if item["source"] == "existing-manual-case"],
        "zh": [item for item in results if item["language"] == "zh"],
        "en": [item for item in results if item["language"] == "en"],
        "ja": [item for item in results if item["language"] == "ja"],
    }
    metrics = {key: metric([item["rank"] for item in value])
              for key, value in groups.items()}
    conflicts = [item for item in results if item.get("opposite_rank") is not None]
    metrics["opposite_conflicts"] = {
        "with_opposite": len(conflicts),
        "opposite_above_target": sum(item["opposite_rank"] < item["rank"]
                                      for item in conflicts),
    }
    return metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dictionary", type=Path,
        default=ROOT / "tool/.tmp/translation-audit/ffdkj.sqlite")
    parser.add_argument("--output", type=Path,
        default=ROOT / "tool/.tmp/semantic-search/colloquial")
    parser.add_argument("--threads", type=int, choices=[1, 2, 4], default=2)
    parser.add_argument("--label-count", type=int, default=60)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "tool/.tmp").resolve()):
        raise ValueError("Output directory must be under tool/.tmp")
    output.mkdir(parents=True, exist_ok=True)
    catalog_path = ROOT / "assets/databases/tag_catalog.db"
    dictionary_path = args.dictionary.resolve()
    names, texts = corpus(catalog_path, dictionary_path)
    rows = load_candidates(catalog_path, dictionary_path)
    cases = build_cases(rows, Path(__file__).with_name("cases.json"), args.label_count)
    cases_path = output / "cases.json"
    cases_path.write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding="utf-8")
    reports = []
    models = [
        ("intfloat/multilingual-e5-small", output.parent, 384),
        ("intfloat/multilingual-e5-base", output.parent / "e5-base", 768),
    ]
    for model, directory, dimensions in models:
        vectors, metadata, cache = current_cache(directory, catalog_path, dictionary_path,
                                                 texts, dimensions)
        encoder = Encoder(directory, args.threads)
        results, elapsed = rank_cases(vectors, names, cases, encoder)
        report = {
            "model": model,
            "cache": cache.name,
            "sources": metadata,
            "corpus_size": len(names),
            "case_count": len(cases),
            "label_count": args.label_count,
            "case_sha256": sha256(cases_path),
            "metrics": summarize(results),
            "query_elapsed_seconds": round(elapsed, 3),
            "details": results,
        }
        reports.append(report)
        (output / (model.rsplit("/", 1)[-1] + ".json")).write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        del vectors
    summary = {
        "case_count": len(cases),
        "label_count": args.label_count,
        "template_count": len(cases) - len(json.loads(Path(__file__).with_name("cases.json").read_text(encoding="utf-8"))),
        "manual_case_count": len(json.loads(Path(__file__).with_name("cases.json").read_text(encoding="utf-8"))),
        "corpus_size": len(names),
        "reports": [{"model": item["model"], "metrics": item["metrics"],
                     "query_elapsed_seconds": item["query_elapsed_seconds"]}
                    for item in reports],
    }
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
