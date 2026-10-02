/// Toneless Hanyu Pinyin syllables (ü written `v`), split into initial and
/// final, with Ziranma double-pinyin codes and fuzzy-sound folding.
///
/// The syllable inventory comes from the bundled character readings, so this
/// class never accepts a syllable no character can be read as.
class PinyinSyllables {
  PinyinSyllables(Iterable<String> syllables)
    : all = Set.unmodifiable(syllables.where(_isSyllable)) {
    final prefixes = <String>{};
    final ziranma = <String, String>{};
    for (final syllable in all) {
      for (var end = 1; end <= syllable.length; end++) {
        prefixes.add(syllable.substring(0, end));
      }
      final code = ziranmaCodeOf(syllable);
      if (code != null) ziranma.putIfAbsent(code, () => syllable);
    }
    _prefixes = prefixes;
    _fromZiranma = ziranma;
  }

  final Set<String> all;
  late final Set<String> _prefixes;
  late final Map<String, String> _fromZiranma;

  static const int longestSyllable = 6;

  /// Two-letter initials first so `zh` wins over `z`.
  static const List<String> initials = [
    'zh', 'ch', 'sh', //
    'b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k', 'h',
    'j', 'q', 'x', 'r', 'z', 'c', 's', 'y', 'w',
  ];

  static final RegExp _letters = RegExp(r'^[a-z]+$');
  static final RegExp _vowel = RegExp('[aeiouv]');

  // Interjection readings (m, ng, hm) would split ordinary letter runs.
  static bool _isSyllable(String value) =>
      _letters.hasMatch(value) && _vowel.hasMatch(value);

  bool isSyllable(String value) => all.contains(value);

  /// Whether some syllable starts with [value] (a partially typed syllable).
  bool isPrefix(String value) => _prefixes.contains(value);

  /// `(initial, final)`; the initial is empty for zero-initial syllables.
  static (String, String) split(String syllable) {
    for (final initial in initials) {
      if (syllable.length > initial.length && syllable.startsWith(initial)) {
        return (initial, syllable.substring(initial.length));
      }
    }
    return ('', syllable);
  }

  // ------------------------------------------------------------ Ziranma

  static const Map<String, String> _ziranmaInitials = {
    'zh': 'v',
    'ch': 'i',
    'sh': 'u',
  };

  static const Map<String, String> _ziranmaFinals = {
    'a': 'a', 'o': 'o', 'e': 'e', 'i': 'i', 'u': 'u', 'v': 'v', //
    'ai': 'l', 'ei': 'z', 'ui': 'v', 'ao': 'k', 'ou': 'b', 'iu': 'q',
    'ie': 'x', 've': 't', 'ue': 't', 'er': 'r',
    'an': 'j', 'en': 'f', 'in': 'n', 'un': 'p', 'vn': 'p',
    'ang': 'h', 'eng': 'g', 'ing': 'y', 'ong': 's',
    'ia': 'w', 'ua': 'w', 'uo': 'o', 'uai': 'y', 'iao': 'c', 'ian': 'm',
    'uan': 'r', 'van': 'r', 'iang': 'd', 'uang': 'd', 'iong': 's',
  };

  /// The two keys a Ziranma user types for [syllable], or null if unknown.
  static String? ziranmaCodeOf(String syllable) {
    final (initial, final_) = split(syllable);
    if (initial.isEmpty) {
      // Zero-initial: one-letter finals double, two-letter finals are typed
      // as spelled, and ang/eng take their final key.
      if (final_.length == 1) return '$final_$final_';
      if (final_.length == 2) return final_;
      final key = _ziranmaFinals[final_];
      return key == null ? null : '${final_[0]}$key';
    }
    final finalKey = _ziranmaFinals[final_];
    if (finalKey == null) return null;
    return '${_ziranmaInitials[initial] ?? initial}$finalKey';
  }

  String? fromZiranma(String code) => _fromZiranma[code];

  /// The initial a single Ziranma key stands for: `v`, `i`, `u` are zh, ch,
  /// sh; a, o, e start zero-initial syllables.
  static String ziranmaInitialOf(String key) => switch (key) {
    'v' => 'zh',
    'i' => 'ch',
    'u' => 'sh',
    _ => key,
  };

  /// Letters that may begin a syllable as a full-pinyin initial abbreviation.
  static bool isFullInitialLetter(String letter) =>
      !const {'i', 'u', 'v'}.contains(letter);

  // ------------------------------------------------------------ full pinyin

  /// Splits a letter run into syllables. The last piece may be a partial
  /// syllable (`chens` → chen + s…). Returns at most [maxResults] splits,
  /// fewest pieces first.
  List<PinyinSplit> splitFullPinyin(String letters, {int maxResults = 3}) {
    final text = letters.toLowerCase();
    if (!_letters.hasMatch(text)) return const [];
    final results = <PinyinSplit>[];
    void walk(int start, List<String> pieces) {
      if (results.length >= 16) return;
      if (start == text.length) {
        results.add(PinyinSplit(List.unmodifiable(pieces), partialLast: false));
        return;
      }
      final rest = text.length - start;
      for (var length = rest.clamp(0, longestSyllable); length >= 1; length--) {
        final piece = text.substring(start, start + length);
        if (all.contains(piece)) {
          walk(start + length, [...pieces, piece]);
        }
      }
      // A trailing partial syllable is only allowed at the very end.
      final tail = text.substring(start);
      if (tail.length <= longestSyllable &&
          !all.contains(tail) &&
          _prefixes.contains(tail)) {
        results.add(
          PinyinSplit(List.unmodifiable([...pieces, tail]), partialLast: true),
        );
      }
    }

    walk(0, const []);
    results.sort((a, b) {
      final partial = (a.partialLast ? 1 : 0).compareTo(b.partialLast ? 1 : 0);
      if (partial != 0) return partial;
      return a.pieces.length.compareTo(b.pieces.length);
    });
    return results.take(maxResults).toList(growable: false);
  }

  /// Decodes Ziranma keystrokes; an odd trailing key is a partial initial.
  PinyinSplit? splitZiranma(String letters) {
    final text = letters.toLowerCase();
    if (text.length < 2 || !_letters.hasMatch(text)) return null;
    final pieces = <String>[];
    var index = 0;
    for (; index + 1 < text.length; index += 2) {
      final syllable = _fromZiranma[text.substring(index, index + 2)];
      if (syllable == null) return null;
      pieces.add(syllable);
    }
    if (index < text.length) {
      pieces.add(ziranmaInitialOf(text[index]));
      return PinyinSplit(pieces, partialLast: true);
    }
    return PinyinSplit(pieces, partialLast: false);
  }
}

/// Syllables of a pinyin query; [partialLast] marks a prefix as last piece.
class PinyinSplit {
  const PinyinSplit(this.pieces, {required this.partialLast});

  final List<String> pieces;
  final bool partialLast;

  @override
  String toString() => '${pieces.join(' ')}${partialLast ? '*' : ''}';
}

/// Sound pairs a speaker may not distinguish. Folding maps each pair onto
/// one spelling so both sides of a comparison agree.
enum FuzzyPinyinRule {
  zZh('z-zh'),
  cCh('c-ch'),
  sSh('s-sh'),
  nL('n-l'),
  fH('f-h'),
  rL('r-l'),
  anAng('an-ang'),
  enEng('en-eng'),
  inIng('in-ing');

  const FuzzyPinyinRule(this.id);

  final String id;

  static FuzzyPinyinRule? fromId(String id) {
    for (final rule in values) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  /// Front and back nasals: the default for shuangpin users, whose initials
  /// zh/z etc. are distinct keys rather than sounds they might mix up.
  static const Set<FuzzyPinyinRule> defaults = {anAng, enEng, inIng};
}

String foldPinyin(String syllable, Set<FuzzyPinyinRule> rules) {
  if (rules.isEmpty) return syllable;
  var (initial, final_) = PinyinSyllables.split(syllable);
  if (rules.contains(FuzzyPinyinRule.zZh) && initial == 'zh') initial = 'z';
  if (rules.contains(FuzzyPinyinRule.cCh) && initial == 'ch') initial = 'c';
  if (rules.contains(FuzzyPinyinRule.sSh) && initial == 'sh') initial = 's';
  if (rules.contains(FuzzyPinyinRule.rL) && initial == 'r') initial = 'l';
  if (rules.contains(FuzzyPinyinRule.nL) && initial == 'l') initial = 'n';
  if (rules.contains(FuzzyPinyinRule.fH) && initial == 'h') initial = 'f';
  if (rules.contains(FuzzyPinyinRule.anAng) && final_.endsWith('ang')) {
    final_ = '${final_.substring(0, final_.length - 3)}an';
  }
  if (rules.contains(FuzzyPinyinRule.enEng) && final_.endsWith('eng')) {
    final_ = '${final_.substring(0, final_.length - 3)}en';
  }
  if (rules.contains(FuzzyPinyinRule.inIng) && final_.endsWith('ing')) {
    final_ = '${final_.substring(0, final_.length - 3)}in';
  }
  return '$initial$final_';
}

/// Folding used for the index column: every rule at once. Queries fold the
/// same way to find candidates, then check them against the enabled rules.
String foldPinyinFully(String syllable) =>
    foldPinyin(syllable, FuzzyPinyinRule.values.toSet());
