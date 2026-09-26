import '../../../selection/card_selection_scope.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';

import '../../../widgets/common/app_toast.dart';

import '../../../widgets/tag_library/tag_library_entry_hover_preview.dart';

import 'entry_avatar.dart';

enum _EntryAction { select, edit, favorite, classify, copy, delete }

/// 紧凑头像卡片，名称与更多操作始终可见。
class EntryCard extends StatefulWidget {
  final TagLibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onEdit;
  final VoidCallback? onSend;
  final VoidCallback? onClassify;

  /// 所属分类名称
  final String? categoryName;

  // ===== 批量选择相关属性 =====
  /// 是否处于选择模式
  final bool isSelectionMode;

  /// 是否被选中
  final bool isSelected;

  /// 切换选择状态回调
  final VoidCallback? onToggleSelection;

  const EntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onEdit,
    this.onSend,
    this.onClassify,
    this.categoryName,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
  });

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final cardVisual = Material(
      color: widget.isSelected
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (CardSelectionScope.handleTap(context, entry.id)) return;
          (widget.isSelectionMode ? widget.onToggleSelection : widget.onTap)
              ?.call();
        },
        onLongPress: widget.isSelectionMode
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onToggleSelection?.call();
              },
        child: Padding(
          padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
          child: Row(
            children: [
              EntryAvatar(entry: entry),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.isSelectionMode)
                SizedBox(
                  width: 48,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: widget.onToggleSelection == null
                        ? null
                        : (_) => widget.onToggleSelection!(),
                  ),
                )
              else
                _buildTouchActions(theme, entry),
            ],
          ),
        ),
      ),
    );
    return TagLibraryEntryHoverPreview(
      entry: entry,
      enabled: !widget.isSelectionMode,
      child: cardVisual,
    );
  }

  Widget _buildTouchActions(ThemeData theme, TagLibraryEntry entry) {
    final l10n = context.l10n;
    return SizedBox(
      width: 48,
      child: PopupMenuButton<_EntryAction>(
        tooltip: l10n.common_moreActions,
        constraints: const BoxConstraints(minWidth: 200),
        icon: Icon(
          Icons.more_vert_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onSelected: (action) {
          switch (action) {
            case _EntryAction.select:
              widget.onToggleSelection?.call();
            case _EntryAction.edit:
              widget.onEdit?.call();
            case _EntryAction.favorite:
              widget.onToggleFavorite();
            case _EntryAction.classify:
              widget.onClassify?.call();
            case _EntryAction.copy:
              _copyToClipboard(entry.content);
            case _EntryAction.delete:
              widget.onDelete();
          }
        },
        itemBuilder: (context) => [
          if (widget.onToggleSelection != null)
            PopupMenuItem(
              value: _EntryAction.select,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.common_select),
              ),
            ),
          if (widget.onEdit != null)
            PopupMenuItem(
              value: _EntryAction.edit,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.common_edit),
              ),
            ),
          PopupMenuItem(
            value: _EntryAction.favorite,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                entry.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: entry.isFavorite ? Colors.redAccent : null,
              ),
              title: Text(
                entry.isFavorite
                    ? l10n.common_unfavorite
                    : l10n.common_favorite,
              ),
            ),
          ),
          if (widget.onClassify != null)
            PopupMenuItem(
              value: _EntryAction.classify,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(l10n.tagLibrary_moveToCategoryTitle),
              ),
            ),
          PopupMenuItem(
            value: _EntryAction.copy,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_copy),
              title: Text(l10n.common_copy),
            ),
          ),
          PopupMenuItem(
            value: _EntryAction.delete,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(l10n.common_delete),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String content) {
    Clipboard.setData(ClipboardData(text: content));
    AppToast.success(context, context.l10n.common_copied);
  }
}
