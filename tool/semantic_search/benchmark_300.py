"""Closed-set 300-case comparison for the offline autocomplete experiment.

The queries are existing canonical tag names and existing Chinese labels. This
does not create translations or claim natural-language accuracy; it measures
whether each encoder retrieves a known target from the same 54k-tag corpus.
"""
import argparse
import hashlib
import json
import re
import time
from contextlib import closing
from pathlib import Path
import sqlite3

import numpy as np

from evaluate import Encoder, ROOT, corpus, sha256, verify_model


HAN = re.compile(r'[\u3400-\u9fff]')
FORCED = {
    'untucked_shirt', 'shirt_tucked_in', 'shirt_partially_tucked_in',
    'no_socks', 'socks', 'short_hair', 'long_hair', 'closed_eyes',
    'eyes_closed', 'one_eye_closed', 'open_mouth', 'closed_mouth',
}


def load_candidates(catalog_path, dictionary_path):
    with closing(sqlite3.connect(dictionary_path.as_uri() + '?mode=ro', uri=True)) as db:
        external = {name: label for name, label in db.execute('SELECT name,cn_name FROM tags')
                    if HAN.search(label or '')}
    with closing(sqlite3.connect(catalog_path.as_uri() + '?mode=ro', uri=True)) as db:
        bundled = {name: label for name, label, mode in db.execute(
            'SELECT tag,zh_cn,mode FROM zh_translations') if mode == 1 or name not in external}
        rows = list(db.execute(
            'SELECT name,category,post_count FROM tags WHERE category IN (0,7)'))
    labels = {**external, **bundled}
    return [(name, category, count, labels[name]) for name, category, count in rows
            if name in labels and HAN.search(labels[name] or '')]


def _hash(name):
    return hashlib.sha256(name.encode()).hexdigest()


def choose_cases(rows, per_category=75):
    by_category = {category: [row for row in rows if row[1] == category]
                   for category in (0, 7)}
    selected = []
    for category, candidates in by_category.items():
        if len(candidates) < per_category:
            raise ValueError(f'category {category} has only {len(candidates)} candidates')
        forced = [row for row in candidates if row[0] in FORCED]
        forced.sort(key=lambda row: _hash(row[0]))
        selected_names = {row[0] for row in forced}
        remaining = [row for row in candidates if row[0] not in selected_names]
        remaining.sort(key=lambda row: _hash(row[0]))
        selected.extend(forced[:per_category])
        selected.extend(remaining[:per_category - len(forced)])
    selected.sort(key=lambda row: (row[1], _hash(row[0])))
    cases = []
    for language in ('zh', 'en'):
        for name, category, count, label in selected:
            cases.append({
                'language': language,
                'tag': name,
                'category': category,
                'post_count': count,
                'query': label if language == 'zh' else name.replace('_', ' '),
                'label': label,
            })
    return cases


def current_cache(directory, catalog_path, dictionary_path, texts, dimensions):
    metadata = {name: sha256(path) for name, path in {
        'catalog': catalog_path, 'dictionary': dictionary_path,
        'model': directory / 'model.onnx', 'tokenizer': directory / 'tokenizer.json',
    }.items()}
    metadata['corpus'] = hashlib.sha256(json.dumps(texts, ensure_ascii=False).encode()).hexdigest()
    metadata['encoding'] = 'e5-query-passage-mean-l2-max128-length-batches-v2'
    verify_model(metadata, dimensions)
    key = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()
    cache = directory / f'vectors-{key}.npy'
    if not cache.exists():
        raise FileNotFoundError(f'Current vector cache is missing: {cache.name}; run evaluate.py first')
    vectors = np.load(cache, mmap_mode='r', allow_pickle=False)
    if vectors.shape != (len(texts), dimensions) or vectors.dtype != np.float32:
        raise ValueError(f'Invalid cache {cache}')
    if not np.isfinite(vectors).all():
        raise ValueError(f'Non-finite values in cache {cache}')
    return vectors, metadata, cache


def rank_batch(vectors, names, cases, encoder):
    target_indices = {name: index for index, name in enumerate(names)}
    ranks = []
    started = time.monotonic()
    for start in range(0, len(cases), 32):
        batch = cases[start:start + 32]
        queries = encoder.encode([case['query'] for case in batch], 'query: ')
        for case, query in zip(batch, queries):
            scores = vectors @ query
            order = np.argsort(-scores, kind='stable')
            target = target_indices[case['tag']]
            rank = int(np.flatnonzero(order == target)[0]) + 1
            ranks.append(rank)
    return ranks, time.monotonic() - started


def summarize(cases, ranks, model, metadata, cache, elapsed):
    by_language = {}
    for language in ('zh', 'en'):
        values = [rank for case, rank in zip(cases, ranks) if case['language'] == language]
        by_language[language] = {
            'count': len(values),
            'top1': sum(rank <= 1 for rank in values) / len(values),
            'top5': sum(rank <= 5 for rank in values) / len(values),
            'top20': sum(rank <= 20 for rank in values) / len(values),
            'mrr10': sum(1 / rank if rank <= 10 else 0 for rank in values) / len(values),
            'median_rank': int(np.median(values)),
            'mean_rank': round(float(np.mean(values)), 2),
        }
    details = [
        {'language': case['language'], 'tag': case['tag'], 'query': case['query'], 'rank': rank}
        for case, rank in zip(cases, ranks)
    ]
    return {
        'model': model,
        'cache': cache.name,
        'sources': metadata,
        'count': len(cases),
        'by_language': by_language,
        'overall': {
            'top1': sum(rank <= 1 for rank in ranks) / len(ranks),
            'top5': sum(rank <= 5 for rank in ranks) / len(ranks),
            'top20': sum(rank <= 20 for rank in ranks) / len(ranks),
        },
        'query_elapsed_seconds': round(elapsed, 3),
        'details': details,
    }


def lexical_baseline(cases, rows):
    """Exact canonical/label lookup baseline for the same closed-set cases."""
    by_label = {}
    for name, category, count, label in rows:
        by_label.setdefault(label, []).append((count, name))
    for values in by_label.values():
        values.sort(key=lambda item: (-item[0], item[1]))
    ranks = []
    for case in cases:
        if case['language'] == 'en':
            ranks.append(1)  # canonical names are UNIQUE in tag_catalog.db.
        else:
            ranks.append(next(i for i, (_, name) in enumerate(by_label[case['label']], 1)
                              if name == case['tag']))
    result = {}
    for language in ('zh', 'en'):
        values = [rank for case, rank in zip(cases, ranks) if case['language'] == language]
        result[language] = {
            'count': len(values),
            'top1': sum(rank <= 1 for rank in values) / len(values),
            'top5': sum(rank <= 5 for rank in values) / len(values),
            'top20': sum(rank <= 20 for rank in values) / len(values),
            'median_rank': int(np.median(values)),
        }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dictionary', type=Path,
        default=ROOT / 'tool/.tmp/translation-audit/ffdkj.sqlite')
    parser.add_argument('--output', type=Path,
        default=ROOT / 'tool/.tmp/semantic-search/benchmark-300')
    parser.add_argument('--threads', type=int, choices=[1, 2, 4], default=2)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / 'tool/.tmp').resolve()):
        raise ValueError('Output directory must be under tool/.tmp')
    output.mkdir(parents=True, exist_ok=True)
    catalog_path = ROOT / 'assets/databases/tag_catalog.db'
    dictionary_path = args.dictionary.resolve()
    names, texts = corpus(catalog_path, dictionary_path)
    rows = load_candidates(catalog_path, dictionary_path)
    cases = choose_cases(rows)
    if len(cases) != 300 or len({case['tag'] for case in cases}) != 150:
        raise AssertionError('Benchmark must contain 300 cases over 150 tags')
    cases_path = output / 'cases.json'
    cases_path.write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding='utf-8')
    common = {
        'case_count': len(cases),
        'tag_count': len({case['tag'] for case in cases}),
        'case_sha256': sha256(cases_path),
        'corpus_size': len(names),
        'selection': 'sha256-name-stratified-category0/7-75-each-forced-known-cases-v1',
        'lexical_baseline': lexical_baseline(cases, rows),
    }
    reports = []
    models = [
        ('intfloat/multilingual-e5-small', output.parent, 384),
        ('intfloat/multilingual-e5-base', output.parent / 'e5-base', 768),
    ]
    for model, directory, dimensions in models:
        vectors, metadata, cache = current_cache(directory, catalog_path, dictionary_path, texts, dimensions)
        encoder = Encoder(directory, args.threads)
        ranks, elapsed = rank_batch(vectors, names, cases, encoder)
        reports.append(summarize(cases, ranks, model, metadata, cache, elapsed))
        del vectors
        (output / (model.rsplit('/', 1)[-1] + '.json')).write_text(
            json.dumps(reports[-1], ensure_ascii=False, indent=2), encoding='utf-8')
    summary = dict(common, reports=[{
        'model': report['model'], 'by_language': report['by_language'],
        'overall': report['overall'], 'query_elapsed_seconds': report['query_elapsed_seconds']
    } for report in reports])
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
