import 'package:flutter/material.dart';

import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../widgets/common/thumbnail_display.dart';

/// Shared circular preview; existing square focus coordinates remain compatible.
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({super.key, required this.entry, this.size = 44});

  final TagLibraryEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatar = SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: entry.hasThumbnail && entry.thumbnail != null
            ? ThumbnailDisplay(
                imagePath: entry.thumbnail!,
                offsetX: entry.thumbnailOffsetX,
                offsetY: entry.thumbnailOffsetY,
                scale: entry.thumbnailScale,
                width: size,
                height: size,
              )
            : ColoredBox(
                color: colors.secondaryContainer,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: size * 0.48,
                  color: colors.onSecondaryContainer,
                ),
              ),
      ),
    );
    return Stack(
      children: [
        avatar,
        if (entry.isFavorite)
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 12,
                  color: colors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
