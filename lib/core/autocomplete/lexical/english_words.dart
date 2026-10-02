import 'dart:math' as math;

/// Small English helpers for tag-token matching. Tags are short noun and
/// participle phrases, so a light suffix stemmer suffices: its stems are only
/// used as search prefixes, never shown.
abstract final class EnglishWords {
  static final RegExp _consonantPair = RegExp(r'([bcdfgklmnprstvz])\1$');

  /// `socks` → sock, `dresses` → dress, `sitting` → sit, `curled` → curl.
  /// Stems shorter than three letters keep the original word.
  static String stem(String word) {
    final w = word.toLowerCase();
    String? stemmed;
    if (w.length > 4 && w.endsWith('ies')) {
      stemmed = '${w.substring(0, w.length - 3)}y';
    } else if (w.endsWith('sses') ||
        w.endsWith('ches') ||
        w.endsWith('shes') ||
        w.endsWith('xes')) {
      stemmed = w.substring(0, w.length - 2);
    } else if (w.endsWith('s') &&
        !w.endsWith('ss') &&
        !w.endsWith('us') &&
        !w.endsWith('is')) {
      stemmed = w.substring(0, w.length - 1);
    } else if (w.length > 5 && w.endsWith('ing')) {
      stemmed = _undouble(w.substring(0, w.length - 3));
    } else if (w.length > 4 && w.endsWith('ed')) {
      stemmed = _undouble(w.substring(0, w.length - 2));
    }
    return stemmed != null && stemmed.length >= 3 ? stemmed : w;
  }

  static String _undouble(String base) =>
      _consonantPair.hasMatch(base) ? base.substring(0, base.length - 1) : base;

  /// Restricted Damerau–Levenshtein (optimal string alignment) distance.
  static int distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous2 = List<int>.filled(b.length + 1, 0);
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var value = math.min(
          math.min(previous[j] + 1, current[j - 1] + 1),
          previous[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          value = math.min(value, previous2[j - 2] + 1);
        }
        current[j] = value;
      }
      final recycled = previous2;
      previous2 = previous;
      previous = current;
      current = recycled;
    }
    return previous[b.length];
  }

  /// [word] with one letter removed, every way (the word itself excluded).
  static Set<String> deletes1(String word) => {
    for (var i = 0; i < word.length; i++)
      word.substring(0, i) + word.substring(i + 1),
  };

  /// Deletion neighbourhood up to [depth] letters, including [word] itself.
  /// Against an index of words plus their single deletions it finds words one
  /// substitution, transposition or missing letter away, and, with depth 2,
  /// typos where [word] also has an extra letter. Callers confirm candidates
  /// with [distance].
  static Set<String> deleteNeighbourhood(String word, {required int depth}) {
    final result = <String>{word};
    var frontier = <String>{word};
    for (var level = 0; level < depth; level++) {
      final next = <String>{};
      for (final value in frontier) {
        if (value.length <= 2) continue;
        next.addAll(deletes1(value));
      }
      result.addAll(next);
      frontier = next;
    }
    return result;
  }

  /// Largest edit distance tolerated for a token of [length] letters.
  static int allowedDistance(int length) => length >= 7 ? 2 : 1;
}
