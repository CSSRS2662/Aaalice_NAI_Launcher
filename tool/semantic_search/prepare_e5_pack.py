"""Prepare verified E5 assets, reusing a matching matrix when available.

Run from the repository root. Inputs are local, pinned model files and an
existing ffdkj dictionary. Network downloads and translation are never implicit.
"""
import argparse
import hashlib
import json
import shutil
import time
from pathlib import Path

import numpy as np
from tokenizers import Tokenizer
from semantic_paraphrase_benchmark import load_catalog, sha256
from evaluate import Encoder

ROOT = Path(__file__).resolve().parents[2]


def candidate_vectors(source, records, build):
    texts = ['; '.join([r['tag']] + ([r['zh_cn']] if r['zh_cn'] else [])) for r in records]
    corpus_hash = hashlib.sha256(json.dumps(texts, ensure_ascii=False).encode()).hexdigest()
    report_path = ROOT / 'tool/.tmp/semantic-model-comparison/comparison.json'
    if report_path.exists():
        report = json.loads(report_path.read_text(encoding='utf8'))
        meta = report['models']['e5-small']['vector']
        cache = Path(meta['cache'])
        if (cache.is_file() and cache.resolve().is_relative_to(ROOT / 'tool/.tmp')
                and meta['candidate_sha256'] == corpus_hash
                and meta['model_sha256'] == sha256(source / 'model.onnx')
                and meta['tokenizer_sha256'] == sha256(source / 'tokenizer.json')):
            return np.load(cache, allow_pickle=False)
    if not build:
        raise ValueError('No verified matrix cache. Use --build-vectors for an explicit CPU build.')
    encoder = Encoder(source, threads=2)
    vectors = np.empty((len(records), 384), dtype=np.float32)
    order = sorted(range(len(texts)), key=lambda i: (len(texts[i]), i))
    started = time.monotonic()
    for start in range(0, len(order), 64):
        if time.monotonic() - started > 540:
            raise TimeoutError('E5 pack encoding exceeded 540 seconds')
        positions = order[start:start + 64]
        vectors[positions] = encoder.encode([texts[i] for i in positions], 'passage: ')
    return vectors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'tool/.tmp/semantic-search')
    parser.add_argument('--dictionary', type=Path, default=ROOT / 'tool/.tmp/translation-audit/ffdkj.sqlite')
    parser.add_argument('--build-vectors', action='store_true')
    parser.add_argument('--tokenizer-fixtures', action='store_true')
    args = parser.parse_args()
    source = args.source.resolve()
    pack = ROOT / 'assets/semantic_search'
    lock = json.loads((pack / 'manifest.json').read_text(encoding='utf8'))
    dictionary = args.dictionary.resolve()
    catalog = ROOT / 'assets/databases/tag_catalog.db'
    if sha256(catalog) != lock['catalog_sha256'] or sha256(dictionary) != lock['dictionary_sha256']:
        raise ValueError('Catalog or dictionary differs from the frozen E5 pack inputs')
    for name in ['model.onnx', 'tokenizer.json']:
        if sha256(source / name) != lock['files'][name]['sha256']:
            raise ValueError(f'Unverified E5 artifact: {name}')
    records, _, _ = load_catalog(catalog, dictionary)
    vectors = candidate_vectors(source, records, args.build_vectors)
    if vectors.shape != (len(records), 384) or not np.isfinite(vectors).all():
        raise ValueError('Invalid E5 matrix')
    if not np.allclose(np.linalg.norm(vectors, axis=1), 1, atol=1e-4):
        raise ValueError('E5 matrix rows must be L2 normalized')
    staging = ROOT / 'tool/.tmp/e5-pack'
    staging.mkdir(parents=True, exist_ok=True)
    vectors.astype('<f4').tofile(staging / 'vectors.f32')
    (staging / 'tags.json').write_text(json.dumps([
        [r['tag'], r['post_count'], r['zh_cn']] for r in records
    ], ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    # A changed runtime or corpus must not silently replace the reviewed pack.
    for name in ['vectors.f32', 'tags.json']:
        if sha256(staging / name) != lock['files'][name]['sha256']:
            raise ValueError(f'{name} differs from the deployment lock; review it before updating the lock')
    pack.mkdir(exist_ok=True)
    for name in ['model.onnx', 'tokenizer.json']:
        shutil.copyfile(source / name, pack / name)
    for name in ['vectors.f32', 'tags.json']:
        shutil.copyfile(staging / name, pack / name)
    if args.tokenizer_fixtures:
        cases = json.loads((source / 'paraphrase/cases.json').read_text(encoding='utf8'))
        tokenizer = Tokenizer.from_file(str(source / 'tokenizer.json'))
        tokenizer.enable_truncation(max_length=128)
        queries = [c['query'] for c in cases] + ['短发', '不穿袜子', 'ＡＢＣ　袜子', '中文\n测试', 'café', '😀角色', 'hello  world']
        fixtures = [{'query': q, 'ids': tokenizer.encode('query: ' + q.strip()).ids} for q in queries]
        (source / 'e5-tokenizer-fixtures.json').write_text(json.dumps(fixtures, ensure_ascii=False), encoding='utf8')
    print('Prepared', len(records), 'candidates')


if __name__ == '__main__':
    main()
