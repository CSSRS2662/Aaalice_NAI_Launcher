class PromptGroupSectionSnapshot {
  const PromptGroupSectionSnapshot({
    required this.id,
    required this.text,
    this.enabled = true,
    this.collapsed = false,
  });

  final String id;
  final String text;
  final bool enabled;
  final bool collapsed;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'enabled': enabled,
    'collapsed': collapsed,
  };

  static PromptGroupSectionSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String) return null;
    final rawId = raw['id'];
    return PromptGroupSectionSnapshot(
      id: rawId is String && rawId.trim().isNotEmpty ? rawId : '',
      text: text,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      collapsed: raw['collapsed'] is bool ? raw['collapsed'] as bool : false,
    );
  }
}

/// Launcher-only prompt editor state stored alongside NovelAI metadata.
///
/// NovelAI still receives the normal flattened prompt. This snapshot only lets
/// Aaalice Pocket reconstruct the user's untitled prompt partitions later.
class PromptGroupSnapshot {
  const PromptGroupSnapshot({
    required this.groupedMode,
    required this.positiveSections,
    required this.negativeSections,
  });

  static const metadataKey = 'aaalice_prompt_groups';
  static const version = 1;

  final bool groupedMode;
  final List<PromptGroupSectionSnapshot> positiveSections;
  final List<PromptGroupSectionSnapshot> negativeSections;

  String get positivePrompt => _joinEnabled(positiveSections);
  String get negativePrompt => _joinEnabled(negativeSections);

  Map<String, Object?> toJson() => {
    'version': version,
    'mode': groupedMode ? 'grouped' : 'single',
    'positivePrompt': positivePrompt,
    'negativePrompt': negativePrompt,
    'positiveSections': [
      for (final section in positiveSections) section.toJson(),
    ],
    'negativeSections': [
      for (final section in negativeSections) section.toJson(),
    ],
  };

  static PromptGroupSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final positive = _readSections(raw['positiveSections']);
    final negative = _readSections(raw['negativeSections']);
    if (positive.isEmpty && negative.isEmpty) return null;
    return PromptGroupSnapshot(
      groupedMode: raw['mode'] == 'grouped',
      positiveSections: positive.isEmpty
          ? _fallbackSections(raw['positivePrompt'])
          : positive,
      negativeSections: negative.isEmpty
          ? _fallbackSections(raw['negativePrompt'])
          : negative,
    );
  }

  static List<PromptGroupSectionSnapshot> _readSections(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .take(64)
        .map(PromptGroupSectionSnapshot.fromJson)
        .whereType<PromptGroupSectionSnapshot>()
        .toList(growable: false);
  }

  static List<PromptGroupSectionSnapshot> _fallbackSections(Object? prompt) {
    return [
      PromptGroupSectionSnapshot(id: '', text: prompt is String ? prompt : ''),
    ];
  }

  static String _joinEnabled(Iterable<PromptGroupSectionSnapshot> sections) {
    final parts = <String>[];
    for (final section in sections) {
      if (!section.enabled) continue;
      final normalized = section.text
          .trim()
          .replaceFirst(RegExp(r'^[,，\s]+'), '')
          .replaceFirst(RegExp(r'[,，\s]+$'), '');
      if (normalized.isNotEmpty) parts.add(normalized);
    }
    return parts.join(', ');
  }
}
