"""Prepare the verified multi-view E5 pack.

Every general tag keeps its reviewed baseline document ("tag; zh_cn") as view 1.
When the pinned amenorira/danbooru-tags-data-zh (MIT) row exists, its Chinese
name, Chinese aliases and one-line note become extra views; a query scores a tag
by its best view (offline evaluation: tool/.tmp/doc-swap, variant BAV). Vectors
are stored as int8 rows with one float32 scale per row.

Run from the repository root. Network access only happens with --fetch (AME
source); the model/tokenizer and ffdkj snapshot must already match the manifest.
Output that differs from assets/semantic_search/manifest.json is refused unless
--write-manifest is given after review.
"""
import argparse
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np
from tokenizers import Tokenizer

from semantic_model_comparison import OnnxEncoder
from semantic_paraphrase_benchmark import load_catalog, sha256

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/zh_lexicon'))
import ame_source  # noqa: E402

PACK = ROOT / 'assets/semantic_search'
WORK = ROOT / 'tool/.tmp/e5-pack'
COMPARISON = ROOT / 'tool/.tmp/semantic-model-comparison/comparison.json'
GENERATED = ['vectors.i8', 'scales.f32', 'tags.json']
BATCH = 64


def base_doc(record):
    return '; '.join([record['tag']] + ([record['zh_cn']] if record['zh_cn'] else []))


def encode(encoder_factory, texts, started, limit=900):
    """Deterministic length-ordered batches, as in the reviewed baseline matrix."""
    vectors = np.empty((len(texts), 384), dtype=np.float32)
    order = sorted(range(len(texts)), key=lambda i: (len(texts[i]), texts[i]))
    encoder = encoder_factory()
    for start in range(0, len(order), BATCH):
        if time.monotonic() - started > limit:
            raise TimeoutError(f'E5 pack encoding exceeded {limit} seconds')
        positions = order[start:start + BATCH]
        vectors[positions] = encoder.encode([texts[i] for i in positions], 'passage: ')
    return vectors


def base_vectors(source, records, build, threads, started):
    texts = [base_doc(r) for r in records]
    corpus_hash = hashlib.sha256(json.dumps(texts, ensure_ascii=False).encode()).hexdigest()
    if COMPARISON.exists():
        meta = json.loads(COMPARISON.read_text(encoding='utf8'))['models']['e5-small']['vector']
        cache = Path(meta['cache'])
        if (cache.is_file() and cache.resolve().is_relative_to(ROOT / 'tool/.tmp')
                and meta['candidate_sha256'] == corpus_hash
                and meta['model_sha256'] == sha256(source / 'model.onnx')
                and meta['tokenizer_sha256'] == sha256(source / 'tokenizer.json')):
            return np.load(cache, allow_pickle=False)
    if not build:
        raise ValueError('No verified baseline matrix cache. Use --build-vectors for an explicit CPU build.')
    return encode(lambda: OnnxEncoder(source, threads), texts, started)


def ame_views(records, source_dir):
    """Per-record extra view texts from the pinned AME general table."""
    index = {r['tag']: i for i, r in enumerate(records)}
    _tags, aliases = ame_source.catalog_tables()
    mapped = ame_source.map_rows(
        ame_source.read_table('general', source_dir), aliases,
        exact_ok=lambda name: name in index,
        alias_ok=lambda name: name in index and records[index[name]]['category'] == 0,
    )
    views = [[] for _ in records]
    for tag, row in mapped.items():
        i = index[tag]
        seen = {base_doc(records[i])}
        for text in (row['zh'], ', '.join(row['aliases']), row['notes']):
            text = ame_source.clean(text)
            if text and text not in seen:
                seen.add(text)
                views[i].append(text)
    return views, len(mapped)


def ame_vectors(source, texts, threads, started):
    digest = hashlib.sha256(json.dumps([sha256(source / 'model.onnx'), texts], ensure_ascii=False).encode()).hexdigest()
    cache = WORK / f'ame-views-{digest[:16]}.npy'
    if cache.is_file():
        vectors = np.load(cache, allow_pickle=False)
        if vectors.shape == (len(texts), 384):
            return vectors
    vectors = encode(lambda: OnnxEncoder(source, threads), texts, started)
    WORK.mkdir(parents=True, exist_ok=True)
    np.save(cache, vectors, allow_pickle=False)
    return vectors


def quantize(matrix):
    """Symmetric int8 per row; score = scale * dot(int8_row, query)."""
    scales = (np.abs(matrix).max(axis=1) / 127.0).astype(np.float32)
    if not (scales > 0).all():
        raise ValueError('Zero E5 vector row')
    values = np.clip(np.rint(matrix / scales[:, None]), -127, 127).astype(np.int8)
    return values, scales


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path, default=ROOT / 'tool/.tmp/semantic-search')
    parser.add_argument('--dictionary', type=Path, default=ROOT / 'tool/.tmp/translation-audit/ffdkj.sqlite')
    parser.add_argument('--ame-source', type=Path, default=ame_source.DEFAULT_SOURCE)
    parser.add_argument('--fetch', action='store_true', help='download the locked AME files first')
    parser.add_argument('--build-vectors', action='store_true')
    parser.add_argument('--threads', type=int, default=4)
    parser.add_argument('--write-manifest', action='store_true', help='accept reviewed new output')
    parser.add_argument('--tokenizer-fixtures', action='store_true')
    args = parser.parse_args()
    started = time.monotonic()
    source = args.source.resolve()
    lock = json.loads((PACK / 'manifest.json').read_text(encoding='utf8'))
    catalog = ROOT / 'assets/databases/tag_catalog.db'
    if sha256(catalog) != lock['catalog_sha256'] or sha256(args.dictionary) != lock['dictionary_sha256']:
        raise ValueError('Catalog or dictionary differs from the frozen E5 pack inputs')
    for name in ['model.onnx', 'tokenizer.json']:
        if sha256(source / name) != lock['files'][name]['sha256']:
            raise ValueError(f'Unverified E5 artifact: {name}')
    if args.fetch:
        ame_source.fetch(args.ame_source)

    records, _, _ = load_catalog(catalog, args.dictionary)
    base = base_vectors(source, records, args.build_vectors, args.threads, started)
    if base.shape != (len(records), 384) or not np.isfinite(base).all():
        raise ValueError('Invalid E5 baseline matrix')
    views, mapped = ame_views(records, args.ame_source)
    texts = sorted({t for per in views for t in per}, key=lambda t: (len(t), t))
    extra = ame_vectors(source, texts, args.threads, started)
    row = {text: i for i, text in enumerate(texts)}
    counts, parts = [], []
    for i, per in enumerate(views):
        counts.append(1 + len(per))
        parts.append(base[i:i + 1])
        if per:
            parts.append(extra[[row[t] for t in per]])
    matrix = np.ascontiguousarray(np.vstack(parts), dtype=np.float32)
    if not np.allclose(np.linalg.norm(matrix, axis=1), 1, atol=1e-4):
        raise ValueError('E5 view rows must be L2 normalized')
    values, scales = quantize(matrix)

    staging = WORK / 'pack'
    staging.mkdir(parents=True, exist_ok=True)
    (staging / 'vectors.i8').write_bytes(values.tobytes())
    (staging / 'scales.f32').write_bytes(scales.astype('<f4').tobytes())
    (staging / 'tags.json').write_text(json.dumps([
        [r['tag'], r['post_count'], r['zh_cn'], counts[i]] for i, r in enumerate(records)
    ], ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    ame_lock = ame_source.load_lock()
    manifest = {
        'model': lock['model'],
        'revision': lock['revision'],
        'dimensions': 384,
        'count': len(records),
        'views': int(sum(counts)),
        'vector_format': 'int8 rows, one float32 scale per row; a tag scores by its best view',
        'document': 'view 1: canonical tag; existing zh_cn. Extra views: AME zh name, zh aliases, note',
        'catalog_sha256': lock['catalog_sha256'],
        'dictionary_sha256': lock['dictionary_sha256'],
        'ame': {
            'repository': ame_lock['repository'],
            'commit': ame_lock['commit'],
            'general_csv_sha256': ame_lock['files']['tags/general.csv']['sha256'],
            'mapped_tags': mapped,
        },
        'files': {
            **{name: lock['files'][name] for name in ['model.onnx', 'tokenizer.json']},
            **{name: {'sha256': sha256(staging / name), 'bytes': (staging / name).stat().st_size} for name in GENERATED},
        },
    }
    if not args.write_manifest:
        for name in GENERATED:
            if lock['files'].get(name) != manifest['files'][name]:
                raise ValueError(f'{name} differs from the deployment lock; review it, then rerun with --write-manifest')
    for name in ['model.onnx', 'tokenizer.json']:
        target = PACK / name
        if not target.exists() or sha256(target) != lock['files'][name]['sha256']:
            shutil.copyfile(source / name, target)
    for name in GENERATED:
        shutil.copyfile(staging / name, PACK / name)
    (PACK / 'vectors.f32').unlink(missing_ok=True)  # single-view format before multi-view
    (PACK / 'LICENSE.amenorira.txt').write_bytes(ame_source.read_verified('LICENSE', args.ame_source))
    if args.write_manifest:
        (PACK / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    if args.tokenizer_fixtures:
        cases = json.loads((source / 'paraphrase/cases.json').read_text(encoding='utf8'))
        tokenizer = Tokenizer.from_file(str(source / 'tokenizer.json'))
        tokenizer.enable_truncation(max_length=128)
        queries = [c['query'] for c in cases] + ['短发', '不穿袜子', 'ＡＢＣ　袜子', '中文\n测试', 'café', '😀角色', 'hello  world']
        fixtures = [{'query': q, 'ids': tokenizer.encode('query: ' + q.strip()).ids} for q in queries]
        (source / 'e5-tokenizer-fixtures.json').write_text(json.dumps(fixtures, ensure_ascii=False), encoding='utf8')
    print(f"Prepared {len(records)} tags / {manifest['views']} views ({mapped} AME rows) in {time.monotonic() - started:.0f}s")


if __name__ == '__main__':
    main()
