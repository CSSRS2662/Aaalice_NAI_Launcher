import 'dart:math' as math;

import '../../constants/storage_keys.dart';
import '../../storage/local_storage_service.dart';

/// Tags this device accepted from autocomplete, with how often and when. The
/// record stays on the device: it reflects one person's habits on one
/// device, is not in the portable settings list and is never synced.
class TagUsageHistory {
  TagUsageHistory(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LocalStorageService _storage;
  final DateTime Function() _now;
  Map<String, _Usage>? _cache;

  static const int maxEntries = 600;

  /// Half-life of a past use, in days.
  static const double halfLifeDays = 45;

  Map<String, _Usage> get _entries => _cache ??= _load();

  Map<String, _Usage> _load() {
    final stored = _storage.getSetting<dynamic>(
      StorageKeys.autocompleteTagUsageHistory,
    );
    if (stored is! Map) return {};
    final result = <String, _Usage>{};
    for (final entry in stored.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! List || value.length < 2) continue;
      final count = value[0];
      final day = value[1];
      if (count is int && day is int) {
        result[entry.key as String] = _Usage(count, day);
      }
    }
    return result;
  }

  int get _today => _now().toUtc().millisecondsSinceEpoch ~/ 86400000;

  Future<void> record(String canonicalTag) async {
    final tag = canonicalTag.trim().toLowerCase();
    if (tag.isEmpty) return;
    final entries = _entries;
    final previous = entries[tag];
    entries[tag] = _Usage((previous?.count ?? 0) + 1, _today);
    if (entries.length > maxEntries) {
      final weakest = entries.keys.toList()
        ..sort((a, b) => score(a).compareTo(score(b)));
      for (final key in weakest.take(entries.length - maxEntries)) {
        entries.remove(key);
      }
    }
    await _storage.setSetting<Map<String, Object>>(
      StorageKeys.autocompleteTagUsageHistory,
      {
        for (final entry in entries.entries)
          entry.key: [entry.value.count, entry.value.day],
      },
    );
  }

  /// 0 for unused tags; grows with uses and fades with time since the last.
  double score(String canonicalTag) {
    final usage = _entries[canonicalTag.toLowerCase()];
    if (usage == null) return 0;
    final age = math.max(0, _today - usage.day);
    final decay = math.pow(0.5, age / halfLifeDays).toDouble();
    return math.log(1 + usage.count) / math.ln2 * decay;
  }

  bool get isEmpty => _entries.isEmpty;

  Iterable<String> get tags => _entries.keys;

  Future<void> clear() async {
    _cache = {};
    await _storage.deleteSetting(StorageKeys.autocompleteTagUsageHistory);
  }
}

class _Usage {
  const _Usage(this.count, this.day);

  final int count;

  /// Days since the epoch (UTC) of the last use.
  final int day;
}
