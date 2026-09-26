"""Offline semantic retrieval experiment, never imported by the application.

Only existing catalog names and Chinese labels are encoded. No generated
translations, wiki prose, per-tag aliases, or query-dependent corpus selection.
"""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import time

os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')
os.environ.setdefault('OMP_NUM_THREADS', '2')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '2')

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer
import tokenizers

ROOT = Path(__file__).resolve().parents[2]


def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def verify_model(metadata, dimensions):
    profiles = json.loads(Path(__file__).with_name('models.json').read_text(encoding='utf-8'))
    for profile in profiles:
        if (profile['model_sha256'] == metadata['model']
                and profile['tokenizer_sha256'] == metadata['tokenizer']
                and profile['dimensions'] == dimensions):
            return profile
    raise ValueError('Model/tokenizer/dimension does not match models.json')


def corpus(catalog_path, dictionary_path):
    with closing(sqlite3.connect(dictionary_path.as_uri() + '?mode=ro', uri=True)) as db:
        labels = dict(db.execute('SELECT name,cn_name FROM tags'))
    with closing(sqlite3.connect(catalog_path.as_uri() + '?mode=ro', uri=True)) as db:
        for tag, label, mode in db.execute('SELECT tag,zh_cn,mode FROM zh_translations'):
            if mode == 1 or not labels.get(tag):
                labels[tag] = label
        rows = list(db.execute('SELECT name FROM tags WHERE category IN (0,7) ORDER BY name'))
    names = [row[0] for row in rows]
    texts = [name.replace('_', ' ') + ('; ' + labels[name] if labels.get(name) else '')
             for name in names]
    return names, texts


def summarize_case(case, names, scores):
    index = {name: i for i, name in enumerate(names)}
    order = np.argsort(-scores, kind='stable')
    ranks = np.empty(len(order), dtype=int)
    ranks[order] = np.arange(1, len(order) + 1)
    accepted = [case['target'], *case.get('alternatives', [])]
    return dict(case, rank=min(int(ranks[index[tag]]) for tag in accepted),
        opposite_rank=int(ranks[index[case['opposite']]]),
        top5=[{'tag': names[i], 'score': round(float(scores[i]), 5)} for i in order[:5]])


def encoding_order(texts):
    """Performance-only permutation; target cases cannot influence it."""
    return sorted(range(len(texts)), key=lambda i: (len(texts[i]), i))


class Encoder:
    def __init__(self, directory, threads=2):
        self.tokenizer = Tokenizer.from_file(str(directory / 'tokenizer.json'))
        self.tokenizer.enable_truncation(max_length=128)
        self.tokenizer.enable_padding(pad_id=1, pad_token='<pad>')
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(directory / 'model.onnx'),
            sess_options=options, providers=['CPUExecutionProvider'])

    def encode(self, texts, prefix):
        encoded = self.tokenizer.encode_batch([prefix + text for text in texts])
        values = {
            'input_ids': np.array([e.ids for e in encoded], dtype=np.int64),
            'attention_mask': np.array([e.attention_mask for e in encoded], dtype=np.int64),
            'token_type_ids': np.array([e.type_ids for e in encoded], dtype=np.int64),
        }
        inputs = {item.name: values[item.name] for item in self.session.get_inputs()}
        hidden = self.session.run(None, inputs)[0]
        mask = values['attention_mask'][..., None]
        if hidden.ndim != 3:
            raise ValueError(f'Expected last_hidden_state, got {hidden.shape}')
        pooled = (hidden * mask).sum(axis=1) / mask.sum(axis=1)
        norm = np.linalg.norm(pooled, axis=1, keepdims=True)
        if not np.isfinite(pooled).all() or (norm == 0).any():
            raise ValueError('Invalid embedding')
        return (pooled / norm).astype(np.float32)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=ROOT / 'tool/.tmp/semantic-search')
    parser.add_argument('--dictionary', type=Path,
        default=ROOT / 'tool/.tmp/translation-audit/ffdkj.sqlite')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--dimensions', type=int, default=384)
    parser.add_argument('--threads', type=int, choices=[1, 2, 4], default=2)
    args = parser.parse_args()
    directory = args.directory.resolve()
    # Cache/report writes must remain inside the project's designated temp tree.
    if not directory.is_relative_to((ROOT / 'tool/.tmp').resolve()):
        raise ValueError('Output directory must be under tool/.tmp')
    if not 1 <= args.timeout <= 600:
        raise ValueError('timeout must be 1..600 seconds')
    started = time.monotonic()
    catalog_path = ROOT / 'assets/databases/tag_catalog.db'
    dictionary_path = args.dictionary.resolve()
    names, texts = corpus(catalog_path, dictionary_path)
    cases = json.loads(Path(__file__).with_name('cases.json').read_text(encoding='utf-8'))
    index = {name: i for i, name in enumerate(names)}
    for case in cases:
        if any(tag not in index for tag in [case['target'], case['opposite'], *case.get('alternatives', [])]):
            raise ValueError(f'Missing evaluation tag: {case}')
    metadata = {name: sha256(path) for name, path in {
        'catalog': catalog_path, 'dictionary': dictionary_path,
        'model': directory / 'model.onnx', 'tokenizer': directory / 'tokenizer.json',
    }.items()}
    metadata['corpus'] = hashlib.sha256(json.dumps(texts, ensure_ascii=False).encode()).hexdigest()
    metadata['encoding'] = 'e5-query-passage-mean-l2-max128-length-batches-v2'
    profile = verify_model(metadata, args.dimensions)
    key = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()
    cache = directory / f'vectors-{key}.npy'
    encoder = Encoder(directory, args.threads)
    cache_reused = cache.exists()
    if cache_reused:
        vectors = np.load(cache, allow_pickle=False)
        if vectors.shape != (len(names), args.dimensions) or not np.isfinite(vectors).all():
            raise ValueError('Invalid vector cache')
    else:
        # Group similar input lengths to avoid padding every short tag to an
        # unrelated long label. Scatter back to stable canonical-name order.
        order = encoding_order(texts)
        partial = directory / f'vectors-{key}.partial.npy'
        progress = directory / f'vectors-{key}.progress.json'
        resume = partial.exists() and progress.exists()
        completed = json.loads(progress.read_text(encoding='utf-8')) if resume else 0
        if not isinstance(completed, int) or not 0 <= completed <= len(texts):
            raise ValueError('Invalid checkpoint')
        vectors = np.lib.format.open_memmap(partial, mode='r+' if resume else 'w+',
            dtype=np.float32, shape=(len(texts), args.dimensions))
        if vectors.shape != (len(texts), args.dimensions) or vectors.dtype != np.float32:
            raise ValueError('Checkpoint shape or dtype mismatch')
        for start in range(completed, len(texts), 32):
            if time.monotonic() - started > args.timeout:
                raise TimeoutError('Corpus encoding time budget exceeded')
            positions = order[start:start + 32]
            vectors[positions] = encoder.encode([texts[i] for i in positions], 'passage: ')
            vectors.flush()
            checkpoint = progress.with_suffix('.tmp')
            checkpoint.write_text(str(start + len(positions)), encoding='utf-8')
            checkpoint.replace(progress)
            if start % 2048 == 0:
                print(f'Encoded {start}/{len(texts)} in {time.monotonic()-started:.1f}s', flush=True)
        if vectors.shape != (len(names), args.dimensions) or not np.isfinite(vectors).all():
            raise ValueError('Invalid completed embeddings')
        np.save(cache, vectors, allow_pickle=False)
        del vectors
        partial.unlink()
        progress.unlink()
        vectors = np.load(cache, allow_pickle=False)
    results = []
    for case in cases:
        begin = time.monotonic()
        query = encoder.encode([case['query']], 'query: ')[0]
        scores = vectors @ query
        result = summarize_case(case, names, scores)
        result['query_ms'] = round((time.monotonic()-begin)*1000, 2)
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    recall20 = sum(r['rank'] <= 20 for r in results) / len(results)
    inversions = sum(r['opposite_rank'] < r['rank'] for r in results)
    report = dict(sources=metadata, model=profile, corpus_size=len(names), cases=results,
        cases_sha256=sha256(Path(__file__).with_name('cases.json')),
        runtime={'onnxruntime':ort.__version__, 'tokenizers':tokenizers.__version__,
                 'numpy':np.__version__, 'threads':args.threads, 'provider':'CPUExecutionProvider'},
        cache_reused=cache_reused, recall20=recall20, opposite_above_target=inversions,
        gate_passed=recall20 >= .8 and inversions == 0,
        elapsed_seconds=round(time.monotonic()-started, 2))
    (directory / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('cases','sources')}, ensure_ascii=False))
    return 0 if report['gate_passed'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
