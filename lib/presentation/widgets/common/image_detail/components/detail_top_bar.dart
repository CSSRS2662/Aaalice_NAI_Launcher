import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/mosaic/mosaic_derivative_registry.dart';
import '../../../../../core/storage/local_storage_service.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../core/watermark/watermark_derivative_registry.dart';
import '../../../../../data/models/gallery/local_image_record.dart';
import '../../../../providers/local_gallery_provider.dart';
import '../../../../providers/mosaic_settings_provider.dart';
import '../../../../providers/watermark_settings_provider.dart';
import '../../animated_favorite_button.dart';
import '../../image_card_action.dart';
import '../../image_card_context_menu.dart';
import '../file_image_detail_data.dart';
import '../image_detail_data.dart';

/// 顶部控制栏
///
/// 显示关闭按钮、图片索引信息和操作按钮
class DetailTopBar extends StatelessWidget {
  final int currentIndex;
  final int totalImages;
  final ImageDetailData currentImage;
  final VoidCallback onClose;
  final VoidCallback? onShowMetadata;
  final VoidCallback? onReuseMetadata;
  final VoidCallback? onReuseSeed;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onSave;
  final VoidCallback? onCopyImage;
  final VoidCallback? onShare;
  final VoidCallback? onWatermark;
  final VoidCallback? onMosaic;
  final VoidCallback? onSendToImg2Img;
  final VoidCallback? onSendToReversePrompt;

  const DetailTopBar({
    super.key,
    required this.currentIndex,
    required this.totalImages,
    required this.currentImage,
    required this.onClose,
    this.onShowMetadata,
    this.onReuseMetadata,
    this.onReuseSeed,
    this.onFavoriteToggle,
    this.onSave,
    this.onCopyImage,
    this.onShare,
    this.onWatermark,
    this.onMosaic,
    this.onSendToImg2Img,
    this.onSendToReversePrompt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metadata = currentImage.metadata;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // 关闭按钮
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onClose,
              tooltip: l10n.common_close,
            ),

            const SizedBox(width: 16),

            // 图片信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${currentIndex + 1} / $totalImages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (metadata?.model != null)
                    Text(
                      metadata!.model!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),

            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: _DetailTopBarActions(
                currentImage: currentImage,
                hasMetadata: metadata != null,
                onShowMetadata: onShowMetadata,
                onReuseMetadata: onReuseMetadata,
                onReuseSeed: onReuseSeed,
                onFavoriteToggle: onFavoriteToggle,
                onSave: onSave,
                onCopyImage: onCopyImage,
                onShare: onShare,
                onWatermark: onWatermark,
                onMosaic: onMosaic,
                onSendToImg2Img: onSendToImg2Img,
                onSendToReversePrompt: onSendToReversePrompt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTopBarActions extends ConsumerWidget {
  const _DetailTopBarActions({
    required this.currentImage,
    required this.hasMetadata,
    this.onShowMetadata,
    this.onReuseMetadata,
    this.onReuseSeed,
    this.onFavoriteToggle,
    this.onSave,
    this.onCopyImage,
    this.onShare,
    this.onWatermark,
    this.onMosaic,
    this.onSendToImg2Img,
    this.onSendToReversePrompt,
  });

  final ImageDetailData currentImage;
  final bool hasMetadata;
  final VoidCallback? onShowMetadata;
  final VoidCallback? onReuseMetadata;
  final VoidCallback? onReuseSeed;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onSave;
  final VoidCallback? onCopyImage;
  final VoidCallback? onShare;
  final VoidCallback? onWatermark;
  final VoidCallback? onMosaic;
  final VoidCallback? onSendToImg2Img;
  final VoidCallback? onSendToReversePrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final compact =
            constraints.maxWidth < 720 || textScaler.scale(1) >= 1.3;
        final veryCompact =
            constraints.maxWidth < 420 || textScaler.scale(1) >= 2;
        return _buildActions(context, ref, compact, veryCompact);
      },
    );
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    bool compact,
    bool veryCompact,
  ) {
    final l10n = context.l10n;
    final watermarkEnabled = ref.watch(
      watermarkSettingsProvider.select((state) => state.configuration.enabled),
    );
    final isWatermarkDerivative =
        currentImage is LocalImageDetailData &&
        WatermarkDerivativeRegistry(
          ref.read(localStorageServiceProvider),
        ).isDerivative(currentImage.identifier);
    final watermarkLabel = isWatermarkDerivative
        ? l10n.watermark_actionRegenerate
        : l10n.watermark_actionCreate;
    final mosaicEnabled = ref.watch(
      mosaicSettingsProvider.select((state) => state.configuration.enabled),
    );
    final isMosaicDerivative =
        currentImage is LocalImageDetailData &&
        MosaicDerivativeRegistry(
          ref.read(localStorageServiceProvider),
        ).isDerivative(currentImage.identifier);
    final mosaicLabel = isMosaicDerivative
        ? l10n.mosaic_actionRegenerate
        : l10n.mosaic_actionCreate;
    final favorite = currentImage.showFavoriteButton && onFavoriteToggle != null
        ? _buildFavorite(ref)
        : null;

    if (compact) {
      final isFavorite = _resolveFavorite(ref);
      final overflowActions = <ImageCardAction>[
        if (onSave != null)
          ImageCardAction(
            id: ImageCardActionId.save,
            icon: Icons.save_alt,
            label: l10n.shortcut_action_save_image,
            invoke: onSave!,
          ),
        if (hasMetadata && onReuseMetadata != null)
          ImageCardAction(
            id: ImageCardActionId.reuseParameters,
            icon: Icons.input_rounded,
            label: l10n.shortcut_action_reuse_params,
            invoke: onReuseMetadata!,
          ),
        if (onReuseSeed != null)
          ImageCardAction(
            id: ImageCardActionId.reuseSeed,
            icon: Icons.eco_outlined,
            label: l10n.shortcut_action_reuse_seed,
            invoke: onReuseSeed!,
          ),
        if (onFavoriteToggle != null)
          ImageCardAction(
            id: ImageCardActionId.favorite,
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            label: isFavorite ? l10n.common_unfavorite : l10n.common_favorite,
            invoke: onFavoriteToggle!,
          ),
        if (onShare != null)
          ImageCardAction(
            id: ImageCardActionId.share,
            icon: Icons.share_rounded,
            label: l10n.common_share,
            invoke: onShare!,
          ),
        if (onSendToImg2Img != null)
          ImageCardAction(
            id: ImageCardActionId.imageToImage,
            icon: Icons.image_search,
            label: l10n.detail_sendToImg2Img,
            invoke: onSendToImg2Img!,
          ),
        if (onSendToReversePrompt != null)
          ImageCardAction(
            id: ImageCardActionId.reversePrompt,
            icon: Icons.auto_fix_high,
            label: l10n.detail_sendToReversePrompt,
            invoke: onSendToReversePrompt!,
          ),
        if (onCopyImage != null)
          ImageCardAction(
            id: ImageCardActionId.copy,
            icon: Icons.copy,
            label: l10n.shortcut_action_copy_image,
            invoke: onCopyImage!,
          ),
        if (watermarkEnabled && onWatermark != null)
          ImageCardAction(
            id: ImageCardActionId.createWatermark,
            icon: Icons.branding_watermark_outlined,
            label: watermarkLabel,
            invoke: onWatermark!,
          ),
        if (mosaicEnabled && onMosaic != null)
          ImageCardAction(
            id: ImageCardActionId.createMosaic,
            icon: Icons.grid_on_rounded,
            label: mosaicLabel,
            invoke: onMosaic!,
          ),
      ];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!veryCompact && onSave != null)
            IconButton(
              icon: const Icon(Icons.save_alt, color: Colors.white),
              onPressed: onSave,
              tooltip: l10n.common_save,
            ),
          if (!veryCompact && onShare != null)
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              onPressed: onShare,
              tooltip: l10n.common_share,
            ),
          if (!veryCompact && favorite != null) favorite,
          if (onShowMetadata != null)
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: onShowMetadata,
              tooltip: l10n.detail_imageDetails,
            ),
          if (overflowActions.isNotEmpty)
            Builder(
              builder: (buttonContext) => IconButton(
                key: const ValueKey('image-detail-more-actions'),
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: l10n.nav_more,
                onPressed: () async {
                  final anchor = buttonContext.findRenderObject()! as RenderBox;
                  await ImageCardContextMenu.show(
                    context: buttonContext,
                    position: anchor.localToGlobal(
                      Offset(0, anchor.size.height),
                    ),
                    actions: overflowActions,
                  );
                },
              ),
            ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onSave != null)
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.white),
            onPressed: onSave,
            tooltip: l10n.common_save,
          ),
        if (onShare != null)
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: onShare,
            tooltip: l10n.common_share,
          ),
        if (watermarkEnabled && onWatermark != null)
          IconButton(
            icon: const Icon(
              Icons.branding_watermark_outlined,
              color: Colors.white,
            ),
            onPressed: onWatermark,
            tooltip: watermarkLabel,
          ),
        if (mosaicEnabled && onMosaic != null)
          IconButton(
            icon: const Icon(Icons.grid_on_rounded, color: Colors.white),
            onPressed: onMosaic,
            tooltip: mosaicLabel,
          ),
        if (hasMetadata && onReuseMetadata != null)
          IconButton(
            icon: const Icon(Icons.input, color: Colors.white),
            onPressed: onReuseMetadata,
            tooltip: l10n.shortcut_action_reuse_params,
          ),
        if (onSendToImg2Img != null)
          IconButton(
            icon: const Icon(Icons.image_search, color: Colors.white),
            onPressed: onSendToImg2Img,
            tooltip: l10n.detail_sendToImg2Img,
          ),
        if (onSendToReversePrompt != null)
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Colors.white),
            onPressed: onSendToReversePrompt,
            tooltip: l10n.detail_sendToReversePrompt,
          ),
        if (onCopyImage != null)
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            onPressed: onCopyImage,
            tooltip: l10n.shortcut_action_copy_image,
          ),
        if (favorite != null) favorite,
      ],
    );
  }

  Widget _buildFavorite(WidgetRef ref) {
    final isFavorite = _resolveFavorite(ref);

    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: AnimatedFavoriteButton(
          isFavorite: isFavorite,
          size: 24,
          inactiveColor: Colors.white,
          showBackground: true,
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          onToggle: onFavoriteToggle,
        ),
      ),
    );
  }

  bool _resolveFavorite(WidgetRef ref) {
    var isFavorite = currentImage.isFavorite;
    final favoritePath = currentImage is LocalImageDetailData
        ? (currentImage as LocalImageDetailData).record.path
        : currentImage is FileImageDetailData
        ? (currentImage as FileImageDetailData).filePath
        : null;
    if (favoritePath != null && favoritePath.isNotEmpty) {
      final galleryState = ref.watch(localGalleryNotifierProvider);
      final record = galleryState.currentImages
          .cast<LocalImageRecord?>()
          .firstWhere(
            (image) => image?.path == favoritePath,
            orElse: () => null,
          );
      isFavorite = record?.isFavorite ?? isFavorite;
    }

    return isFavorite;
  }
}
