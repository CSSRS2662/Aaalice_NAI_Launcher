"""Small deterministic checks; no model inference or network access."""
import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

import numpy as np
from evaluate import ROOT, corpus, summarize_case, verify_model, encoding_order


class CorpusTests(unittest.TestCase):
    def test_length_batching_preserves_canonical_row_identity(self):
        texts = ['long text', 'b', 'aa', 'c']
        order = encoding_order(texts)
        self.assertEqual(order, [1, 3, 2, 0])
        restored = [None] * len(texts)
        for index in order:
            restored[index] = texts[index]
        self.assertEqual(restored, texts)

    def test_unverified_model_is_rejected_before_inference(self):
        with self.assertRaises(ValueError):
            verify_model({'model': 'unknown', 'tokenizer': 'unknown'}, 384)

    def test_equivalent_tag_counts_but_conflicting_tag_does_not(self):
        case = {'query': 'test', 'target': 'closed_eyes',
                'alternatives': ['eyes_closed'], 'opposite': 'one_eye_closed'}
        names = ['closed_eyes', 'eyes_closed', 'one_eye_closed']
        good = summarize_case(case, names, np.array([.1, .9, .5]))
        self.assertEqual((good['rank'], good['opposite_rank']), (1, 2))
        bad = summarize_case(case, names, np.array([.1, .5, .9]))
        self.assertEqual((bad['rank'], bad['opposite_rank']), (2, 1))

    def test_readonly_general_scope_and_existing_label_precedence(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'tool/.tmp') as directory:
            catalog = Path(directory) / 'catalog.db'
            dictionary = Path(directory) / 'dictionary.db'
            with closing(sqlite3.connect(catalog)) as db:
                db.executescript('''
                    CREATE TABLE tags(name TEXT, category INTEGER);
                    CREATE TABLE zh_translations(tag TEXT, zh_cn TEXT, mode INTEGER);
                    INSERT INTO tags VALUES ('no_socks',0),('socks',7),('artist',1);
                    INSERT INTO zh_translations VALUES ('no_socks','未穿袜',1),('socks','袜子',0);
                ''')
            with closing(sqlite3.connect(dictionary)) as db:
                db.executescript('''
                    CREATE TABLE tags(name TEXT, cn_name TEXT);
                    INSERT INTO tags VALUES ('no_socks','没有袜子'),('socks','袜');
                ''')
            before = catalog.read_bytes(), dictionary.read_bytes()
            names, texts = corpus(catalog, dictionary)
            self.assertEqual(names, ['no_socks', 'socks'])
            self.assertEqual(texts, ['no socks; 未穿袜', 'socks; 袜'])
            self.assertEqual(before, (catalog.read_bytes(), dictionary.read_bytes()))

    def test_case_targets_and_conflicts_are_distinct(self):
        cases = json.loads(Path(__file__).with_name('cases.json').read_text(encoding='utf-8'))
        self.assertEqual(len({case['query'] for case in cases}), len(cases))
        for case in cases:
            self.assertNotIn(case['opposite'], [case['target'], *case.get('alternatives', [])])


if __name__ == '__main__':
    unittest.main()
