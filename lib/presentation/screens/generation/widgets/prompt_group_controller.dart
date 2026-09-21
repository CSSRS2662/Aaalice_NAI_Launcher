import 'package:flutter/material.dart';

import '../../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../../widgets/prompt/nai_syntax_controller.dart';

enum PromptEditorMode { single, grouped }

/// One user-defined prompt partition.
///
/// Partitions deliberately have no title or category: their meaning belongs to
/// the user, while the editor only owns ordering and inclusion in the request.
class PromptGroupSection {
  PromptGroupSection({
    required this.id,
    required String text,
    this.enabled = true,
    this.collapsed = false,
  }) : controller = NaiSyntaxController(text: text),
       focusNode = FocusNode();

  final String id;
  final NaiSyntaxController controller;
  final FocusNode focusNode;
  bool enabled;
  bool collapsed;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': controller.text,
    'enabled': enabled,
    'collapsed': collapsed,
  };

  PromptGroupSectionSnapshot toSnapshot() => PromptGroupSectionSnapshot(
    id: id,
    text: controller.text,
    enabled: enabled,
    collapsed: collapsed,
  );

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class PromptGroupCollection extends ChangeNotifier {
  PromptGroupCollection.single(String text) {
    _insert(PromptGroupSection(id: _newId(), text: text));
  }

  PromptGroupCollection.fromJson(Object? raw, {required String fallbackText}) {
    if (raw is List) {
      for (final value in raw.take(64)) {
        if (value is! Map) continue;
        final text = value['text'];
        if (text is! String) continue;
        final rawId = value['id'];
        final id = rawId is String && rawId.trim().isNotEmpty
            ? rawId
            : _newId();
        _insert(
          PromptGroupSection(
            id: id,
            text: text,
            enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
            collapsed: value['collapsed'] is bool
                ? value['collapsed'] as bool
                : false,
          ),
        );
      }
    }
    if (_sections.isEmpty) {
      _insert(PromptGroupSection(id: _newId(), text: fallbackText));
    }
  }

  static int _nextId = 0;
  final List<PromptGroupSection> _sections = [];

  List<PromptGroupSection> get sections => List.unmodifiable(_sections);

  String get effectiveText => joinPromptSections(
    _sections
        .where((section) => section.enabled)
        .map((section) => section.controller.text),
  );

  void _insert(PromptGroupSection section, [int? index]) {
    if (index == null) {
      _sections.add(section);
    } else {
      _sections.insert(index, section);
    }
  }

  static String _newId() {
    _nextId++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_nextId';
  }

  PromptGroupSection add() {
    final section = PromptGroupSection(id: _newId(), text: '');
    _insert(section);
    notifyListeners();
    return section;
  }

  void remove(String id) {
    final index = _sections.indexWhere((section) => section.id == id);
    if (index < 0) return;
    final removed = _sections.removeAt(index);
    removed.dispose();
    notifyListeners();
  }

  void setEnabled(String id, bool enabled) {
    final section = _find(id);
    if (section == null || section.enabled == enabled) return;
    section.enabled = enabled;
    notifyListeners();
  }

  void toggleCollapsed(String id) {
    final section = _find(id);
    if (section == null) return;
    section.collapsed = !section.collapsed;
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sections.length) return;
    var target = newIndex;
    if (target > oldIndex) target--;
    target = target.clamp(0, _sections.length - 1).toInt();
    if (target == oldIndex) return;
    final section = _sections.removeAt(oldIndex);
    _sections.insert(target, section);
    notifyListeners();
  }

  void replaceWith(String text) {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    _insert(PromptGroupSection(id: _newId(), text: text));
    notifyListeners();
  }

  void restore(Iterable<PromptGroupSectionSnapshot> snapshots) {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    for (final snapshot in snapshots.take(64)) {
      _insert(
        PromptGroupSection(
          id: snapshot.id.trim().isEmpty ? _newId() : snapshot.id,
          text: snapshot.text,
          enabled: snapshot.enabled,
          collapsed: snapshot.collapsed,
        ),
      );
    }
    if (_sections.isEmpty) {
      _insert(PromptGroupSection(id: _newId(), text: ''));
    }
    notifyListeners();
  }

  void configureHighlighting({
    required bool enabled,
    required bool numericEmphasisEnabled,
  }) {
    for (final section in _sections) {
      section.controller.highlightEnabled = enabled;
      section.controller.numericEmphasisEnabled = numericEmphasisEnabled;
    }
  }

  List<Map<String, Object?>> toJson() => [
    for (final section in _sections) section.toJson(),
  ];

  List<PromptGroupSectionSnapshot> toSnapshot() => [
    for (final section in _sections) section.toSnapshot(),
  ];

  PromptGroupSection? _find(String id) {
    for (final section in _sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  @override
  void dispose() {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    super.dispose();
  }
}

@visibleForTesting
String joinPromptSections(Iterable<String> values) {
  final parts = <String>[];
  for (final value in values) {
    final normalized = value
        .trim()
        .replaceFirst(RegExp(r'^[,，\s]+'), '')
        .replaceFirst(RegExp(r'[,，\s]+$'), '');
    if (normalized.isNotEmpty) parts.add(normalized);
  }
  return parts.join(', ');
}
