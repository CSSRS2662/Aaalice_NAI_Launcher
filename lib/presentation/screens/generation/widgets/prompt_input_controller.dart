import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/nai_prompt_parser.dart';
import '../../../widgets/prompt/nai_syntax_controller.dart';
import 'prompt_group_controller.dart';

/// Owns the long-lived editor objects used by [PromptInputWidget].
///
/// Keeping these objects outside the view widgets preserves controller identity
/// when the responsive layout or prompt type changes.
class PromptInputController extends ChangeNotifier {
  PromptInputController({
    required String prompt,
    required String negativePrompt,
    ValueNotifier<bool>? negativeModeNotifier,
    LocalStorageService? storage,
  }) : promptController = NaiSyntaxController(text: prompt),
       negativeController = NaiSyntaxController(text: negativePrompt),
       promptFocusNode = FocusNode(),
       negativeFocusNode = FocusNode(),
       _storage = storage,
       _negativeModeNotifier = negativeModeNotifier,
       _isNegativeMode = negativeModeNotifier?.value ?? false {
    _restoreGroupState(prompt: prompt, negativePrompt: negativePrompt);
    positiveGroups.addListener(_onGroupStateChanged);
    negativeGroups.addListener(_onGroupStateChanged);
    promptFocusNode.addListener(_notifyFocusChanged);
    negativeFocusNode.addListener(_notifyFocusChanged);
    _negativeModeNotifier?.addListener(_onExternalNegativeModeChanged);
  }

  final NaiSyntaxController promptController;
  final NaiSyntaxController negativeController;
  final FocusNode promptFocusNode;
  final FocusNode negativeFocusNode;
  late final PromptGroupCollection positiveGroups;
  late final PromptGroupCollection negativeGroups;

  final LocalStorageService? _storage;
  ValueNotifier<bool>? _negativeModeNotifier;
  bool _isNegativeMode;
  PromptEditorMode _editorMode = PromptEditorMode.single;

  bool get isNegativeMode => _isNegativeMode;
  PromptEditorMode get editorMode => _editorMode;
  bool get isGroupedMode => _editorMode == PromptEditorMode.grouped;

  PromptGroupCollection groupsFor(bool negative) =>
      negative ? negativeGroups : positiveGroups;

  PromptGroupCollection get activeGroups => groupsFor(_isNegativeMode);

  void bindNegativeModeNotifier(ValueNotifier<bool>? notifier) {
    if (identical(notifier, _negativeModeNotifier)) return;
    _negativeModeNotifier?.removeListener(_onExternalNegativeModeChanged);
    _negativeModeNotifier = notifier;
    _negativeModeNotifier?.addListener(_onExternalNegativeModeChanged);
    final next = notifier?.value;
    if (next != null && next != _isNegativeMode) {
      _isNegativeMode = next;
      notifyListeners();
    }
  }

  void setNegativeMode(bool value) {
    if (value == _isNegativeMode) return;
    _isNegativeMode = value;
    if (_negativeModeNotifier?.value != value) {
      _negativeModeNotifier?.value = value;
    }
    notifyListeners();
  }

  void setEditorMode(PromptEditorMode value) {
    if (value == _editorMode) return;
    if (value == PromptEditorMode.grouped) {
      _alignGroupsWithPrompt(negative: false, prompt: promptController.text);
      _alignGroupsWithPrompt(negative: true, prompt: negativeController.text);
    }
    _editorMode = value;
    _persistGroupState();
    notifyListeners();
  }

  void syncPrompt(String prompt) {
    _alignGroupsWithPrompt(negative: false, prompt: prompt);
    if (promptController.text != prompt) promptController.text = prompt;
    _persistGroupState();
  }

  void syncNegativePrompt(String prompt) {
    _alignGroupsWithPrompt(negative: true, prompt: prompt);
    if (negativeController.text != prompt) negativeController.text = prompt;
    _persistGroupState();
  }

  String commitGroupedPrompt({required bool negative}) {
    final text = groupsFor(negative).effectiveText;
    final target = negative ? negativeController : promptController;
    if (target.text != text) {
      target.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _persistGroupState();
    notifyListeners();
    return text;
  }

  void replacePrompt(String prompt, {required bool negative}) {
    final groups = groupsFor(negative);
    if (groups.effectiveText != prompt || groups.sections.length != 1) {
      groups.replaceWith(prompt);
    }
    final target = negative ? negativeController : promptController;
    if (target.text != prompt) target.text = prompt;
    _persistGroupState();
  }

  void clearPrompt({required bool negative}) =>
      replacePrompt('', negative: negative);

  void configureHighlighting({
    required bool enabled,
    required bool numericEmphasisEnabled,
  }) {
    promptController.highlightEnabled = enabled;
    negativeController.highlightEnabled = enabled;
    promptController.numericEmphasisEnabled = numericEmphasisEnabled;
    negativeController.numericEmphasisEnabled = numericEmphasisEnabled;
    positiveGroups.configureHighlighting(
      enabled: enabled,
      numericEmphasisEnabled: numericEmphasisEnabled,
    );
    negativeGroups.configureHighlighting(
      enabled: enabled,
      numericEmphasisEnabled: numericEmphasisEnabled,
    );
  }

  int get promptCount => _tagCount(promptController.text);
  int get negativePromptCount => _tagCount(negativeController.text);

  static int _tagCount(String value) =>
      NaiPromptParser.splitSegments(value).length;

  void _notifyFocusChanged() => notifyListeners();

  void _onGroupStateChanged() {
    _persistGroupState();
    notifyListeners();
  }

  void _alignGroupsWithPrompt({
    required bool negative,
    required String prompt,
  }) {
    final groups = groupsFor(negative);
    if (groups.effectiveText != prompt) groups.replaceWith(prompt);
  }

  void _restoreGroupState({
    required String prompt,
    required String negativePrompt,
  }) {
    Map<String, Object?>? decoded;
    final raw = _storage?.getSetting<String>(
      StorageKeys.promptGroupEditorState,
    );
    if (raw != null && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) decoded = Map<String, Object?>.from(value);
      } catch (_) {
        decoded = null;
      }
    }

    final positiveMatches = decoded?['positivePrompt'] == prompt;
    final negativeMatches = decoded?['negativePrompt'] == negativePrompt;
    positiveGroups = PromptGroupCollection.fromJson(
      positiveMatches ? decoded!['positiveSections'] : null,
      fallbackText: prompt,
    );
    negativeGroups = PromptGroupCollection.fromJson(
      negativeMatches ? decoded!['negativeSections'] : null,
      fallbackText: negativePrompt,
    );
    if (decoded?['mode'] == PromptEditorMode.grouped.name) {
      _editorMode = PromptEditorMode.grouped;
    }
  }

  void _persistGroupState() {
    final storage = _storage;
    if (storage == null) return;
    final value = jsonEncode({
      'version': 1,
      'mode': _editorMode.name,
      'positivePrompt': promptController.text,
      'negativePrompt': negativeController.text,
      'positiveSections': positiveGroups.toJson(),
      'negativeSections': negativeGroups.toJson(),
    });
    unawaited(storage.setSetting(StorageKeys.promptGroupEditorState, value));
  }

  void _onExternalNegativeModeChanged() {
    final value = _negativeModeNotifier?.value;
    if (value == null || value == _isNegativeMode) return;
    _isNegativeMode = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _negativeModeNotifier?.removeListener(_onExternalNegativeModeChanged);
    promptFocusNode.removeListener(_notifyFocusChanged);
    negativeFocusNode.removeListener(_notifyFocusChanged);
    promptController.dispose();
    negativeController.dispose();
    positiveGroups.removeListener(_onGroupStateChanged);
    negativeGroups.removeListener(_onGroupStateChanged);
    positiveGroups.dispose();
    negativeGroups.dispose();
    promptFocusNode.dispose();
    negativeFocusNode.dispose();
    super.dispose();
  }
}
