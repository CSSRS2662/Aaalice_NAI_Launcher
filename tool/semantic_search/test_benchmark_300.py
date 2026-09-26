import unittest
from benchmark_300 import choose_cases, lexical_baseline, summarize


class BenchmarkTests(unittest.TestCase):
    def test_exact_lookup_baseline_is_deterministic(self):
        rows = [('a', 0, 100, '甲'), ('b', 0, 200, '甲'), ('c', 7, 1, '丙')]
        cases = [
            {'language': 'zh', 'tag': 'a', 'label': '甲', 'query': '甲'},
            {'language': 'zh', 'tag': 'b', 'label': '甲', 'query': '甲'},
            {'language': 'en', 'tag': 'c', 'label': '丙', 'query': 'c'},
        ]
        baseline = lexical_baseline(cases, rows)
        self.assertEqual(baseline['zh']['top1'], .5)
        self.assertEqual(baseline['en']['top1'], 1.0)

    def test_selection_is_300_cases_with_two_languages_and_category_balance(self):
        rows = [(f'tag_{category}_{i}', category, i, f'标签{category}{i}')
                for category in (0, 7) for i in range(200)]
        cases = choose_cases(rows)
        self.assertEqual(len(cases), 300)
        self.assertEqual(len({case['tag'] for case in cases}), 150)
        self.assertEqual({case['language'] for case in cases}, {'zh', 'en'})
        for language in ('zh', 'en'):
            self.assertEqual(sum(case['category'] == 0 for case in cases
                                 if case['language'] == language), 75)
            self.assertEqual(sum(case['category'] == 7 for case in cases
                                 if case['language'] == language), 75)

    def test_summary_uses_rank_thresholds_not_model_scores(self):
        cases = [
            {'language': 'zh', 'tag': 'a', 'query': '甲'},
            {'language': 'en', 'tag': 'b', 'query': 'b'},
            {'language': 'zh', 'tag': 'c', 'query': '丙'},
            {'language': 'en', 'tag': 'd', 'query': 'd'},
        ]
        report = summarize(cases, [1, 5, 20, 21], 'test', {}, type('Cache', (), {'name': 'x'})(), 1.0)
        self.assertEqual(report['by_language']['zh']['top1'], .5)
        self.assertEqual(report['by_language']['en']['top5'], .5)
        self.assertEqual(report['overall']['top20'], .75)


if __name__ == '__main__':
    unittest.main()
