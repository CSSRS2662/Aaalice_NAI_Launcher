"""Unit tests for AME source mapping, lexicon rows and E5 pack quantization."""
import sys
import unittest
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "semantic_search"))

import ame_source  # noqa: E402
from build_lexicon import lexicon_entry  # noqa: E402


def row(name, count=1, zh="", aliases=()):
    return {"name": name, "category": 0, "count": count, "zh": zh, "aliases": list(aliases), "notes": ""}


class MapRowsTest(unittest.TestCase):
    def test_exact_beats_catalog_alias_and_source_alias(self):
        known = {"china_dress", "twintails"}
        aliases = {"qipao": ["china_dress"]}
        mapped = ame_source.map_rows(
            [row("qipao", 50, "旗袍"), row("china_dress", 10, "中式裙"), row("twin_tails", 5, "双马尾", ["twintails"])],
            aliases, exact_ok=known.__contains__, alias_ok=known.__contains__)
        self.assertEqual(mapped["china_dress"]["zh"], "中式裙")
        self.assertEqual(mapped["twintails"]["zh"], "双马尾")

    def test_same_priority_keeps_the_most_used_row(self):
        mapped = ame_source.map_rows(
            [row("a", 5, "少"), row("b", 9, "多")], {"a": ["t"], "b": ["t"]},
            exact_ok=lambda _: False, alias_ok=lambda name: name == "t")
        self.assertEqual(mapped["t"]["zh"], "多")


class LexiconEntryTest(unittest.TestCase):
    def test_keeps_only_cjk_label_and_distinct_short_aliases(self):
        entry = lexicon_entry("braid", 0, 7, row("braid", zh="辫子", aliases=["braids", "辫子", "麻花辫", "长" * 41]))
        self.assertEqual(entry, ["braid", 0, 7, "辫子", ["麻花辫"]])

    def test_drops_rows_without_any_chinese(self):
        self.assertIsNone(lexicon_entry("x", 1, 0, row("x", zh="romaji", aliases=["other"])))
        self.assertEqual(lexicon_entry("y", 4, 0, row("y", zh="Romaji", aliases=["別名"]))[3:], ["", ["別名"]])


class QuantizeTest(unittest.TestCase):
    def test_int8_rows_round_trip_within_half_a_step(self):
        from prepare_e5_pack import quantize
        rng = np.random.default_rng(3)
        matrix = rng.normal(size=(20, 384)).astype(np.float32)
        matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
        values, scales = quantize(matrix)
        self.assertEqual(values.dtype, np.int8)
        restored = values.astype(np.float32) * scales[:, None]
        self.assertLessEqual(float(np.abs(restored - matrix).max()), float(scales.max()) / 2 + 1e-7)
        with self.assertRaises(ValueError):
            quantize(np.zeros((1, 384), dtype=np.float32))


if __name__ == "__main__":
    unittest.main()
