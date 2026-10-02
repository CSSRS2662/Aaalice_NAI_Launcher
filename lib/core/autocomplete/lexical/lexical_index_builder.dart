import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../completion_models.dart';
import 'english_words.dart';
import 'pinyin_syllables.dart';
import 'search_lexicon.dart';

/// Everything the background build needs; plain data so it can cross into
/// an isolate.
class LexicalIndexBuildInput {
  const LexicalIndexBuildInput({
    required this.outputPath,
    required this.fingerprint,
    required this.catalogPath,
    required this.ameLexiconGz,
    required this.pinyinGz,
    required this.crossLingualGz,
    this.zhDictionaryPath,
  });

  final String outputPath;
  final String fingerprint;
  final String catalogPath;
  final String? zhDictionaryPath;
  final Uint8List ameLexiconGz;
  final Uint8List pinyinGz;
  final Uint8List crossLingualGz;
}

/// Schema of the local index. Bump [LexicalIndexSchema.version] whenever a
/// table or column changes so stale files are rebuilt.
abstract final class LexicalIndexSchema {
  static const version = 2;

  static const statements = [
    '''CREATE TABLE entries(
      id INTEGER PRIMARY KEY,
      tag TEXT NOT NULL,
      label TEXT NOT NULL,
      post_count INTEGER NOT NULL,
      category INTEGER NOT NULL,
      syllables INTEGER NOT NULL
    )''',
    // One row per reading variant of a label; py is exact toneless pinyin,
    // pyf the same with every fuzzy pair folded.
    '''CREATE VIRTUAL TABLE label_py USING fts5(
      py, pyf, entry UNINDEXED, prefix='1 2', tokenize='unicode61'
    )''',
    '''CREATE VIRTUAL TABLE label_chars USING fts5(
      chars, entry UNINDEXED, tokenize='unicode61'
    )''',
    'CREATE TABLE en_vocab(token TEXT PRIMARY KEY, weight INTEGER NOT NULL) WITHOUT ROWID',
    // Keyed by the deletion itself: no separate index to store.
    'CREATE TABLE en_deletes(del TEXT NOT NULL, token TEXT NOT NULL, '
        'PRIMARY KEY(del, token)) WITHOUT ROWID',
    'CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID',
  ];
}

class _Label {
  _Label(this.tag, this.label, this.postCount, this.category);

  final String tag;
  final String label;
  final int postCount;
  final int category;
}

final RegExp _labelSeparators = RegExp(r'[,，、/;；|]+');
final RegExp _hanzi = RegExp(r'[㐀-鿿]');
final RegExp _nonLetters = RegExp(r'[^a-z]+');
const int _maxLabelLength = 24;
// Words below this summed post count are not correction targets: rare
// words are rarely typed, and their deletions were most of the index.
const int _spellMinWeight = 1000;

/// Builds the index at `outputPath` (replacing it). Safe to run in an
/// isolate: it only touches files and its own database connections.
Future<Map<String, int>> buildLexicalIndex(LexicalIndexBuildInput input) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
  }
  final factory = databaseFactoryFfiNoIsolate;
  final lexicon = SearchLexicon.decode(
    pinyinGz: input.pinyinGz,
    crossLingualGz: input.crossLingualGz,
  );

  final catalog = await factory.openDatabase(
    input.catalogPath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  final labels = <String, _Label>{};
  void addLabels(String tag, String raw, int postCount, int category) {
    final normalizedTag = tag.trim().toLowerCase();
    if (normalizedTag.isEmpty) return;
    for (final part in raw.split(_labelSeparators)) {
      final label = part.trim();
      if (label.isEmpty || label.length > _maxLabelLength) continue;
      if (!_hanzi.hasMatch(label)) continue;
      labels.putIfAbsent(
        '$normalizedTag\u0000$label',
        () => _Label(normalizedTag, label, postCount, category),
      );
    }
  }

  // Bundled AME lexicon (MIT): labels and Chinese aliases.
  final ame =
      (jsonDecode(utf8.decode(gzip.decode(input.ameLexiconGz)))
              as Map)['entries']
          as List;
  for (final row in ame.cast<List>()) {
    final category = TagCategory.fromCatalog(row[1] as int)?.value;
    if (category == null) continue;
    final count = row[2] as int;
    final label = row[3] as String;
    if (label.isNotEmpty) addLabels(row[0] as String, label, count, category);
    for (final alias in (row[4] as List).cast<String>()) {
      addLabels(row[0] as String, alias, count, category);
    }
  }

  // Reviewed bundled translations.
  for (final row in await catalog.rawQuery(
    'SELECT z.tag, z.zh_cn, t.post_count, t.category FROM zh_translations z '
    'LEFT JOIN tags t ON t.name = z.tag',
  )) {
    final category =
        TagCategory.fromCatalog((row['category'] as int?) ?? 0)?.value ?? 0;
    addLabels(
      row['tag'] as String,
      row['zh_cn'] as String,
      (row['post_count'] as int?) ?? 0,
      category,
    );
  }

  // The optional ffdkj dictionary, when installed. Artists are left out:
  // their Chinese names add noise to ordinary lookups.
  final dictionaryPath = input.zhDictionaryPath;
  if (dictionaryPath != null && File(dictionaryPath).existsSync()) {
    final dictionary = await factory.openDatabase(
      dictionaryPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      for (final row in await dictionary.rawQuery(
        "SELECT name, category, cn_name, post_count FROM tags "
        "WHERE cn_name IS NOT NULL AND TRIM(cn_name) <> '' AND category <> 1",
      )) {
        final category = TagCategory.fromDanbooru(
          (row['category'] as int?) ?? 0,
        )?.value;
        if (category == null) continue;
        addLabels(
          row['name'] as String,
          row['cn_name'] as String,
          (row['post_count'] as int?) ?? 0,
          category,
        );
      }
    } finally {
      await dictionary.close();
    }
  }

  // English tokens of tag names, weighted by post count.
  final weights = <String, int>{};
  for (final row in await catalog.rawQuery(
    'SELECT name, post_count FROM tags',
  )) {
    final count = (row['post_count'] as int?) ?? 0;
    for (final token in (row['name'] as String).toLowerCase().split(
      _nonLetters,
    )) {
      if (token.length >= 4) weights[token] = (weights[token] ?? 0) + count;
    }
  }
  await catalog.close();

  final temporary = '${input.outputPath}.building';
  File(input.outputPath).parent.createSync(recursive: true);
  await factory.deleteDatabase(temporary);
  final db = await factory.openDatabase(temporary);
  final stats = <String, int>{};
  try {
    for (final statement in LexicalIndexSchema.statements) {
      await db.execute(statement);
    }
    var entryId = 0;
    var pinyinRows = 0;
    const batchSize = 4000;
    final pending = labels.values.toList(growable: false);
    for (var offset = 0; offset < pending.length; offset += batchSize) {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final label in pending.skip(offset).take(batchSize)) {
          final variants = lexicon.pinyin.readingVariants(label.label);
          if (variants.isEmpty) continue;
          entryId++;
          batch.rawInsert('INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)', [
            entryId,
            label.tag,
            label.label,
            label.postCount,
            label.category,
            variants.first.length,
          ]);
          for (final variant in variants) {
            batch.rawInsert(
              'INSERT INTO label_py(py, pyf, entry) VALUES (?, ?, ?)',
              [
                variant.join(' '),
                variant.map(foldPinyinFully).join(' '),
                entryId,
              ],
            );
            pinyinRows++;
          }
          batch.rawInsert(
            'INSERT INTO label_chars(chars, entry) VALUES (?, ?)',
            [_charTokens(label.label), entryId],
          );
        }
        await batch.commit(noResult: true);
      });
    }
    stats['entries'] = entryId;
    stats['pinyinRows'] = pinyinRows;

    final tokens = weights.entries.toList(growable: false);
    var deleteRows = 0;
    for (var offset = 0; offset < tokens.length; offset += batchSize) {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final entry in tokens.skip(offset).take(batchSize)) {
          batch.rawInsert('INSERT INTO en_vocab VALUES (?, ?)', [
            entry.key,
            entry.value,
          ]);
          if (entry.value < _spellMinWeight) continue;
          for (final deletion in {
            entry.key,
            ...EnglishWords.deletes1(entry.key),
          }) {
            batch.rawInsert('INSERT OR IGNORE INTO en_deletes VALUES (?, ?)', [
              deletion,
              entry.key,
            ]);
            deleteRows++;
          }
        }
        await batch.commit(noResult: true);
      });
    }
    stats['englishTokens'] = tokens.length;
    stats['englishDeletes'] = deleteRows;
    await db.insert('metadata', {
      'key': 'fingerprint',
      'value': input.fingerprint,
    });
    await db.execute("INSERT INTO label_py(label_py) VALUES('optimize')");
    await db.execute("INSERT INTO label_chars(label_chars) VALUES('optimize')");
    // Segment merges leave free pages behind.
    await db.execute('VACUUM');
  } finally {
    await db.close();
  }
  final target = File(input.outputPath);
  if (target.existsSync()) target.deleteSync();
  File(temporary).renameSync(input.outputPath);
  return stats;
}

/// Hanzi as single tokens, ASCII runs as words: `V字手势` → `v 字 手 势`.
String _charTokens(String label) {
  final tokens = <String>[];
  final ascii = StringBuffer();
  for (final rune in label.toLowerCase().runes) {
    if (HanziPinyinTable.isHanzi(rune)) {
      if (ascii.isNotEmpty) {
        tokens.add(ascii.toString());
        ascii.clear();
      }
      tokens.add(String.fromCharCode(rune));
    } else if ((rune >= 0x61 && rune <= 0x7a) ||
        (rune >= 0x30 && rune <= 0x39)) {
      ascii.writeCharCode(rune);
    } else if (ascii.isNotEmpty) {
      tokens.add(ascii.toString());
      ascii.clear();
    }
  }
  if (ascii.isNotEmpty) tokens.add(ascii.toString());
  return tokens.join(' ');
}
