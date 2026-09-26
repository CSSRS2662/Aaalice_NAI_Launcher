"""Deterministic checks for the evaluation-only colloquial suite."""
import json
from pathlib import Path
import tempfile
import unittest

from colloquial_benchmark import TEMPLATES, build_cases, choose_labels


class ColloquialBenchmarkTests(unittest.TestCase):
    def test_selection_is_balanced_and_forced_tags_are_kept_when_available(self):
        rows = []
        for category in (0, 7):
            for index in range(40):
                name = f"tag_{category}_{index}"
                label = f"中文标签{category}{index}"
                rows.append((name, category, index, label))
        rows.extend([
            ("untucked_shirt", 0, 10, "衬衫下摆外露"),
            ("no_socks", 0, 10, "未穿袜"),
            ("socks", 7, 10, "袜子"),
        ])
        selected = choose_labels(rows, count=6)
        self.assertEqual(len(selected), 6)
        self.assertEqual({row[1] for row in selected}, {0, 7})
        self.assertIn("untucked_shirt", {row[0] for row in selected})

    def test_cases_only_wrap_existing_labels_and_keep_manual_holdout(self):
        rows = [
            (f"tag_{category}_{index}", category, 1, f"中文标签{category}{index}")
            for category in (0, 7) for index in range(10)
        ]
        with tempfile.TemporaryDirectory() as directory:
            manual = Path(directory) / "manual.json"
            manual.write_text(json.dumps([{
                "query": "之前的例句", "target": "tag_0_0",
                "opposite": "tag_0_1",
            }, {
                "query": "シャツの裾を出す", "target": "tag_0_0",
                "opposite": "tag_0_1",
            }], ensure_ascii=False), encoding="utf-8")
            cases = build_cases(rows, manual, label_count=6)
        self.assertEqual(len(cases), len(TEMPLATES) * 6 + 2)
        templated = [case for case in cases if case["source"] == "existing-label-template"]
        self.assertTrue(all(case["label"] in case["query"] for case in templated))
        self.assertEqual(cases[-2]["language"], "zh")
        self.assertEqual(cases[-1]["language"], "ja")
        self.assertEqual(cases[-1]["source"], "existing-manual-case")
        self.assertEqual(cases[-1]["tag"], "tag_0_0")


if __name__ == "__main__":
    unittest.main()
