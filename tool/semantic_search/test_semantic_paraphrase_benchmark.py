"""Deterministic, read-only checks for the unseen-paraphrase benchmark."""
from collections import Counter
from pathlib import Path
import unittest

from semantic_paraphrase_benchmark import build_cases, candidate_texts, load_catalog


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets/databases/tag_catalog.db"
DICTIONARY = ROOT / "tool/.tmp/translation-audit/ffdkj.sqlite"
SEED = ROOT / "tool/semantic_search/semantic_paraphrase_cases.json"
HARD = ROOT / "tool/semantic_search/semantic_paraphrase_hard_cases.json"
HOLDOUT = ROOT / "tool/semantic_search/cases.json"


class SemanticParaphraseBenchmarkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        records, _, _ = load_catalog(CATALOG, DICTIONARY)
        cls.cases, cls.by_tag = build_cases(
            records, DICTIONARY, SEED, HARD, HOLDOUT
        )

    def test_suite_has_required_scale_and_sources(self):
        counts = Counter(case["source"] for case in self.cases)
        self.assertGreaterEqual(len({case["target"] for case in self.cases
                                     if case["source"] == "paraphrase"}), 100)
        self.assertGreaterEqual(counts["paraphrase"], 300)
        self.assertGreaterEqual(counts["hard"], 100)
        self.assertGreaterEqual(counts["paraphrase"] + counts["hard"], 400)

    def test_leakage_filter_keeps_hard_set_and_marks_only_known_labels(self):
        clean = [case for case in self.cases if not case["leakage"]]
        self.assertGreaterEqual(sum(case["source"] == "paraphrase" for case in clean), 300)
        self.assertGreaterEqual(sum(case["source"] == "hard" for case in clean), 100)
        for case in clean:
            label = case["zh_cn"].strip()
            if len(label) >= 2:
                self.assertNotIn(label, case["query"])

    def test_cases_resolve_to_production_candidates(self):
        for case in self.cases:
            self.assertIn(case["target"], self.by_tag)
            if case["conflict"]:
                self.assertIn(case["conflict"], self.by_tag)
            self.assertIn(case["language"], {"zh", "ja", "en"})

    def test_candidate_documents_do_not_invent_translation_data(self):
        records = [{
            "tag": "untucked_shirt", "zh_cn": "衬衫下摆外露", "aliases": ["shirttail"],
        }]
        self.assertEqual(candidate_texts(records, "minimal"), ["untucked_shirt; 衬衫下摆外露"])
        self.assertEqual(candidate_texts(records, "enhanced-existing"), [
            "untucked_shirt; untucked shirt; 衬衫下摆外露; shirttail"
        ])


if __name__ == "__main__":
    unittest.main()
