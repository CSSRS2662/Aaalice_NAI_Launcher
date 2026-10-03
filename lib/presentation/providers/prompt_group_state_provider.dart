import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/nai_prompt_parser.dart';
import '../../core/utils/prompt_edit_document.dart';
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

  /// Whether an imported prompt carries the same tags as stored partitions.
  ///
  /// Reused prompts come back rebuilt: fixed and quality tags stripped, tags
  /// rejoined with ", ", disabled fragments gone. Comparing tag by tag keeps
  /// the guard against unrelated edits without demanding identical text.
  static bool samePromptTags(String imported, String stored) =>
      listEquals(_tags(imported), _tags(stored));

  static List<String> _tags(String prompt) => [
    for (final segment in NaiPromptParser.splitSegments(
      PromptEditDocument.effectiveText(prompt),
    ))
      if (NaiPromptParser.normalizeSegment(segment) case final tag
          when tag.isNotEmpty)
        tag,
  ];
}

/// The latest import request is retained so a generation page opened after the
/// import can still consume it. Consumers validate its prompt text first, so a
/// stale request cannot overwrite unrelated edits.
final promptGroupRestoreRequestProvider =
    StateProvider<PromptGroupRestoreRequest?>((ref) => null);
