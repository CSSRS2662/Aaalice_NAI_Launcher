import 'package:flutter/material.dart';

import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';

/// Dialog-local view state: search text, filters, the visible tab and whether
/// the grid is replaced by the reorder list. Entries themselves stay in
/// `fixedTagsNotifierProvider`.
class FixedTagsDialogController extends ChangeNotifier {
  final positiveSearchController = TextEditingController();
  final negativeSearchController = TextEditingController();
  final positiveListController = ScrollController();
  final negativeListController = ScrollController();

  String positiveSearchQuery = '';
  String negativeSearchQuery = '';
  bool enabledOnly = false;
  bool reordering = false;
  FixedTagPromptType mobilePromptType = FixedTagPromptType.positive;

  String searchQueryFor(FixedTagPromptType promptType) =>
      promptType == FixedTagPromptType.positive
      ? positiveSearchQuery
      : negativeSearchQuery;

  TextEditingController searchControllerFor(FixedTagPromptType promptType) =>
      promptType == FixedTagPromptType.positive
      ? positiveSearchController
      : negativeSearchController;

  ScrollController listControllerFor(FixedTagPromptType promptType) =>
      promptType == FixedTagPromptType.positive
      ? positiveListController
      : negativeListController;

  void setSearchQuery(FixedTagPromptType promptType, String value) {
    if (promptType == FixedTagPromptType.positive) {
      positiveSearchQuery = value;
    } else {
      negativeSearchQuery = value;
    }
    notifyListeners();
  }

  void clearSearch(FixedTagPromptType promptType) {
    searchControllerFor(promptType).clear();
    setSearchQuery(promptType, '');
  }

  void toggleEnabledOnly() {
    enabledOnly = !enabledOnly;
    notifyListeners();
  }

  void setReordering(bool value) {
    if (reordering == value) return;
    reordering = value;
    notifyListeners();
  }

  void selectMobilePromptType(FixedTagPromptType promptType) {
    if (mobilePromptType == promptType) return;
    mobilePromptType = promptType;
    notifyListeners();
  }

  @override
  void dispose() {
    positiveSearchController.dispose();
    negativeSearchController.dispose();
    positiveListController.dispose();
    negativeListController.dispose();
    super.dispose();
  }
}
