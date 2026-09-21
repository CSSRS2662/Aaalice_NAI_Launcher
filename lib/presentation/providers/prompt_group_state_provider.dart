import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/gallery/prompt_group_snapshot.dart';

final currentPromptGroupSnapshotProvider = StateProvider<PromptGroupSnapshot?>(
  (ref) => null,
);

class PromptGroupRestoreRequest {
  const PromptGroupRestoreRequest({
    required this.snapshot,
    required this.restorePositive,
    required this.restoreNegative,
  });

  final PromptGroupSnapshot snapshot;
  final bool restorePositive;
  final bool restoreNegative;
}

/// The latest import request is retained so a generation page opened after the
/// import can still consume it. Consumers validate its prompt text first, so a
/// stale request cannot overwrite unrelated edits.
final promptGroupRestoreRequestProvider =
    StateProvider<PromptGroupRestoreRequest?>((ref) => null);
