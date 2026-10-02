import 'package:flutter/foundation.dart';

/// Lets an enclosing editor consume Back before ending the active edit, and
/// ask for related tags without a keyboard shortcut.
class AutocompleteOverlayHandle extends ChangeNotifier {
  VoidCallback? _dismiss;
  VoidCallback? _showRelated;
  bool get isOpen => _dismiss != null;

  /// Whether an autocomplete wrapper can show related tags right now.
  bool get canShowRelated => _showRelated != null;

  /// Shows tags related to the one at the caret, like Ctrl+Shift+Space.
  void showRelated() => _showRelated?.call();

  void bindRelated(VoidCallback show) => _showRelated = show;

  void unbindRelated(VoidCallback show) {
    if (_showRelated == show) _showRelated = null;
  }
  void attach(VoidCallback dismiss) {
    _dismiss = dismiss;
    notifyListeners();
  }

  void detach(VoidCallback dismiss) {
    if (_dismiss != dismiss) return;
    _dismiss = null;
    notifyListeners();
  }

  void dismiss() => _dismiss?.call();
}
