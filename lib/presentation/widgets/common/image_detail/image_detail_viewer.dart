import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../image_viewport_surface.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/services/native_share_service.dart';
import '../../../../core/shortcuts/shortcuts.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/image_share_sanitizer.dart';
import '../../../../core/utils/window_focus_tracker.dart';
import '../../../../core/windowing/workspace_side_panel_contract.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../providers/share_image_settings_provider.dart';
import '../../../providers/copy_drag_watermark_provider.dart';
import '../../../screens/mosaic/mosaic_editor_launcher.dart';
import '../../../screens/watermark/watermark_editor_launcher.dart';
import '../../../utils/clipboard_image.dart';
import '../../shortcuts/shortcuts.dart';
import '../app_toast.dart';
import '../horizontal_resize_handle.dart';
import '../resizable_pane.dart';
import 'components/detail_image_page.dart';
import 'components/detail_metadata_panel.dart';
import 'components/detail_swipe_dismiss.dart';
import 'components/prompt_copy_dialog.dart';
import 'components/detail_thumbnail_bar.dart';
import 'components/detail_top_bar.dart';
import 'image_detail_data.dart';

/// 图像详情查看器回调函数
class ImageDetailCallbacks {
  /// 收藏切换回调
  final void Function(ImageDetailData image)? onFavoriteToggle;

  /// 复用元数据回调
  final Future<void> Function(ImageDetailData image)? onReuseMetadata;

  /// 只把图片的种子写回生成参数。
  final Future<void> Function(ImageDetailData image)? onReuseSeed;

  /// 本轮生成图的参数就是当前参数，此时只提供复用种子、不提供复用参数。
  final bool Function(ImageDetailData image)? parametersAreCurrent;

  /// 保存回调
  final Future<void> Function(ImageDetailData image)? onSave;

  /// 复制图像回调
  final Future<void> Function(ImageDetailData image)? onCopyImage;

  /// 发送到图生图回调
  final Future<void> Function(ImageDetailData image)? onSendToImg2Img;

  /// 发送到反推模块回调
  final Future<void> Function(ImageDetailData image)? onSendToReversePrompt;

  const ImageDetailCallbacks({
    this.onFavoriteToggle,
    this.onReuseMetadata,
    this.onReuseSeed,
    this.parametersAreCurrent,
    this.onSave,
    this.onCopyImage,
    this.onSendToImg2Img,
    this.onSendToReversePrompt,
  });
}

/// 通用图像详情查看器
///
/// 支持两种使用模式:
/// 1. 单图模式: 显示单张图片 + 元数据
/// 2. 多图模式: 支持翻页、缩略图导航
///
/// 功能特性:
/// - 左右滑动/箭头切换图片
/// - 支持缩放平移和双击缩放
/// - 底部缩略图条快速跳转
/// - 键盘导航支持
/// - 桌面端右侧元数据面板
class ImageDetailViewer extends ConsumerStatefulWidget {
  /// 图像数据列表
  final List<ImageDetailData> images;

  /// 初始显示索引
  final int initialIndex;

  /// 是否显示元数据面板（桌面端）
  final bool showMetadataPanel;

  /// 是否显示缩略图条
  final bool showThumbnails;

  /// 回调函数
  final ImageDetailCallbacks? callbacks;

  /// Hero 标签前缀
  final String? heroTagPrefix;

  const ImageDetailViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.showMetadataPanel = true,
    this.showThumbnails = true,
    this.callbacks,
    this.heroTagPrefix,
  });

  /// 打开图像详情查看器
  static Future<void> show(
    BuildContext context, {
    required List<ImageDetailData> images,
    int initialIndex = 0,
    bool showMetadataPanel = true,
    bool showThumbnails = true,
    ImageDetailCallbacks? callbacks,
    String? heroTagPrefix,
  }) {
    final isWindows = PlatformCapabilities.current.isWindows;
    final transitionDuration = isWindows
        ? Duration.zero
        : const Duration(milliseconds: 300);
    final reverseTransitionDuration = isWindows
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Navigator.of(context).push(
      PageRouteBuilder(
        // Windows + 外部截图工具 + 焦点切换下，透明路由和快照过渡更容易触发
        // Flutter 引擎原生崩溃；Windows 走纯黑不透明且无动画路径。
        opaque: isWindows,
        // 背景由查看器自己绘制，下滑关闭时才能淡出、露出下层页面。
        barrierColor: isWindows
            ? ImageViewportSurface.background
            : Colors.transparent,
        allowSnapshotting: !isWindows,
        transitionDuration: transitionDuration,
        reverseTransitionDuration: reverseTransitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          final viewer = ImageDetailViewer(
            images: images,
            initialIndex: initialIndex,
            showMetadataPanel: showMetadataPanel,
            showThumbnails: showThumbnails,
            callbacks: callbacks,
            heroTagPrefix: heroTagPrefix,
          );
          if (isWindows) {
            return viewer;
          }
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: viewer,
          );
        },
      ),
    );
  }

  /// 打开单图模式（无缩略图条）
  static Future<void> showSingle(
    BuildContext context, {
    required ImageDetailData image,
    bool showMetadataPanel = true,
    ImageDetailCallbacks? callbacks,
    String? heroTag,
  }) {
    return show(
      context,
      images: [image],
      initialIndex: 0,
      showMetadataPanel: showMetadataPanel,
      showThumbnails: false,
      callbacks: callbacks,
      heroTagPrefix: heroTag,
    );
  }

  @override
  ConsumerState<ImageDetailViewer> createState() => _ImageDetailViewerState();
}

class _ImageDetailViewerState extends ConsumerState<ImageDetailViewer>
    with SingleTickerProviderStateMixin {
  static const Duration _windowsEscFocusCooldown = Duration(milliseconds: 1200);
  static const Duration _windowsEscBounceCooldown = Duration(seconds: 4);
  static const Duration _closeRequestThrottle = Duration(milliseconds: 700);
  static const double _initialMetadataPanelWidth = 420;
  static const double _minimumMetadataPanelWidth = 320;
  static const double _minimumImagePaneWidth = 480;

  late PageController _pageController;
  late ScrollController _thumbnailController;
  late int _currentIndex;
  // 鼠标下控制栏常驻；触屏单击图片切换显隐。
  bool _showControls = true;
  late final DetailSwipeDismissController _swipeDismiss;
  final _focusNode = FocusNode();
  final Map<String, TransformationController> _transformationControllers = {};
  bool _isClosing = false;
  DateTime? _lastCloseRequestedAt;
  late final ResizablePaneController _metadataPanelWidthController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _swipeDismiss = DetailSwipeDismissController(
      vsync: this,
      onDismiss: () => _requestClose('swipe-down'),
    );
    _thumbnailController = ScrollController();
    _metadataPanelWidthController = ResizablePaneController(
      initialWidth: _initialMetadataPanelWidth,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToThumbnail(_currentIndex, animate: false);
      _focusNode.requestFocus();
    });
  }

  void _scrollToThumbnail(int index, {bool animate = true}) {
    if (!_thumbnailController.hasClients) return;

    const thumbnailWidth = 80.0;
    const thumbnailMargin = 8.0;
    const totalWidth = thumbnailWidth + thumbnailMargin;

    final viewportWidth = _thumbnailController.position.viewportDimension;
    final targetOffset =
        (index * totalWidth) - (viewportWidth / 2) + (totalWidth / 2);
    final maxOffset = _thumbnailController.position.maxScrollExtent;

    final offset = targetOffset.clamp(0.0, maxOffset);

    if (animate) {
      _thumbnailController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _thumbnailController.jumpTo(offset);
    }
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.images.length) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _jumpToPage(int index) {
    if (index < 0 || index >= widget.images.length) return;
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _scrollToThumbnail(index);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _goToPage(_currentIndex - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _goToPage(_currentIndex + 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _handleKeyboardCloseRequest();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _goToPage(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _goToPage(widget.images.length - 1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _handleKeyboardCloseRequest() {
    if (_shouldSuppressEscCloseOnWindows()) {
      final elapsedFocus = WindowFocusTracker.elapsedSinceFocus();
      final elapsedBlur = WindowFocusTracker.elapsedSinceBlur();
      AppLogger.w(
        'Suppressed ESC close after focus bounce '
            '(focus=${elapsedFocus?.inMilliseconds ?? -1}ms, '
            'blur=${elapsedBlur?.inMilliseconds ?? -1}ms)',
        'ImageDetailViewer',
      );
      return;
    }
    _requestClose('keyboard-escape');
  }

  bool _shouldSuppressEscCloseOnWindows() {
    if (!PlatformCapabilities.current.isWindows) return false;
    if (WindowFocusTracker.isWithinCooldown(_windowsEscFocusCooldown)) {
      return true;
    }
    return WindowFocusTracker.hadRecentFocusBounce(
      maxSinceFocus: _windowsEscBounceCooldown,
    );
  }

  /// Returns whether the close was started.
  bool _requestClose(String reason) {
    if (!mounted || _isClosing) return false;
    final now = DateTime.now();
    final lastCloseAt = _lastCloseRequestedAt;
    if (lastCloseAt != null &&
        now.difference(lastCloseAt) <= _closeRequestThrottle) {
      AppLogger.d(
        'Ignored duplicated close request: $reason',
        'ImageDetailViewer',
      );
      return false;
    }
    _lastCloseRequestedAt = now;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      AppLogger.d(
        'Ignored close request on non-current route: $reason',
        'ImageDetailViewer',
      );
      return false;
    }

    _isClosing = true;
    AppLogger.d('Viewer close requested: $reason', 'ImageDetailViewer');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop().whenComplete(() {
        if (mounted) {
          _isClosing = false;
        }
      });
    });
    return true;
  }

  ImageDetailData get _currentImage => widget.images[_currentIndex];

  /// 获取当前图片的 TransformationController
  TransformationController get _currentTransformController {
    final identifier = _currentImage.identifier;
    return _transformationControllers.putIfAbsent(
      identifier,
      TransformationController.new,
    );
  }

  /// 放大
  void _zoomIn() {
    final controller = _currentTransformController;
    final currentScale = controller.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.2).clamp(0.5, 4.0);

    final screenSize = MediaQuery.of(context).size;
    final centerX = screenSize.width / 2;
    final centerY = screenSize.height / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(
        centerX - centerX * newScale,
        centerY - centerY * newScale,
        0,
        1,
      )
      ..scaleByDouble(newScale, newScale, newScale, 1);

    controller.value = matrix;
  }

  /// 缩小
  void _zoomOut() {
    final controller = _currentTransformController;
    final currentScale = controller.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.2).clamp(0.5, 4.0);

    final screenSize = MediaQuery.of(context).size;
    final centerX = screenSize.width / 2;
    final centerY = screenSize.height / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(
        centerX - centerX * newScale,
        centerY - centerY * newScale,
        0,
        1,
      )
      ..scaleByDouble(newScale, newScale, newScale, 1);

    controller.value = matrix;
  }

  /// 重置缩放
  void _resetZoom() {
    _currentTransformController.value = Matrix4.identity();
  }

  /// 切换全屏
  void _toggleFullscreen() {
    // 使用窗口管理器切换全屏
    // 由于查看器是弹窗形式，关闭查看器即可
    _requestClose('toggle-fullscreen');
  }

  /// 切换收藏
  void _toggleFavorite() {
    if (widget.callbacks?.onFavoriteToggle != null) {
      widget.callbacks!.onFavoriteToggle!(_currentImage);
      // 触发重建以更新收藏按钮状态
      setState(() {});
    }
  }

  /// 复制 Prompt
  Future<void> _copyPrompt() async {
    final metadata = _currentImage.metadata;
    if (metadata == null || metadata.fullPrompt.isEmpty) {
      if (context.mounted) {
        AppToast.warning(context, context.l10n.toast_imageHasNoPrompt);
      }
      return;
    }

    final prompt = await PromptCopyDialog.show(context, metadata: metadata);
    if (prompt == null || !mounted) return;

    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) {
      AppToast.success(context, context.l10n.toast_imagePromptCopied);
    }
  }

  Future<void> _showMetadataPanel() {
    return AdaptivePresenter.showPanel<void>(
      context: context,
      title: context.l10n.detail_imageDetails,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (panelContext, _) => LayoutBuilder(
        builder: (context, constraints) => DetailMetadataPanel(
          currentImage: _currentImage,
          expandedWidth: constraints.maxWidth,
          collapsible: false,
        ),
      ),
    );
  }

  /// 复用参数
  void _reuseGalleryParams() {
    if (widget.callbacks?.onReuseMetadata != null) {
      _handleReuseMetadata(context);
    }
  }

  /// 删除图片
  void _deleteImage() {
    // 查看器本身不直接处理删除，通过回调通知父组件
    // 这里显示一个提示，实际删除由调用方处理
    if (context.mounted) {
      AppToast.info(context, context.l10n.toast_useDeleteButton);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 定义快捷键映射
    final shortcuts = <String, VoidCallback>{
      // 上一张
      ShortcutIds.previousImage: () => _goToPage(_currentIndex - 1),
      // 下一张
      ShortcutIds.nextImage: () => _goToPage(_currentIndex + 1),
      // 放大
      ShortcutIds.zoomIn: _zoomIn,
      // 缩小
      ShortcutIds.zoomOut: _zoomOut,
      // 重置缩放
      ShortcutIds.resetZoom: _resetZoom,
      // 全屏切换
      ShortcutIds.toggleFullscreen: _toggleFullscreen,
      // 关闭查看器
      ShortcutIds.closeViewer: _handleKeyboardCloseRequest,
      // 收藏切换
      ShortcutIds.toggleFavorite: _toggleFavorite,
      // 复制 Prompt
      ShortcutIds.copyPrompt: _copyPrompt,
      // 复用参数
      ShortcutIds.reuseGalleryParams: _reuseGalleryParams,
      // 删除图片
      ShortcutIds.deleteImage: _deleteImage,
    };

    return PageShortcuts(
      contextType: ShortcutContext.viewer,
      shortcuts: shortcuts,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: _SwipeDismissBackdrop(
            controller: _swipeDismiss,
            // 不透明路由下层不绘制，淡出只会露出空白。
            canFade: !PlatformCapabilities.current.isWindows,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSideMetadata = constraints.maxWidth >= 1100;
                if (!showSideMetadata || !widget.showMetadataPanel) {
                  return _buildMainContent(
                    showMetadataAction: widget.showMetadataPanel,
                  );
                }

                final maximumPanelWidth =
                    WorkspaceSidePanelContract.constrainedWorkspaceWidth(
                      workspaceWidth: constraints.maxWidth,
                      preferredWidth: WorkspaceSidePanelContract.maximumWidth,
                      occupiedWidth: ResizeHandle.defaultWidth,
                      minimumPrimaryWidth: _minimumImagePaneWidth,
                      minimumWidth: _minimumMetadataPanelWidth,
                    );
                return Row(
                  children: [
                    Expanded(
                      child: _buildMainContent(showMetadataAction: false),
                    ),
                    ResizeHandle(
                      key: const ValueKey(
                        'image-detail-metadata-resize-handle',
                      ),
                      onDrag: (delta) =>
                          _metadataPanelWidthController.resizeBy(-delta),
                    ),
                    ResizablePane(
                      controller: _metadataPanelWidthController,
                      minimumWidth: _minimumMetadataPanelWidth,
                      maximumWidth: maximumPanelWidth,
                      child: DetailMetadataPanel(
                        currentImage: _currentImage,
                        initialExpanded: true,
                        collapsible: false,
                        fillAvailableWidth: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent({required bool showMetadataAction}) {
    final showThumbnails = widget.showThumbnails && widget.images.length > 1;
    final callbacks = widget.callbacks;
    final parametersAreCurrent =
        callbacks?.parametersAreCurrent?.call(_currentImage) ?? false;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        // 主图预览区域：鼠标下控制栏常驻；手指单击切换控制栏，未放大时下滑关闭。
        ListenableBuilder(
          listenable: _swipeDismiss,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _swipeDismiss.offset),
            child: Transform.scale(
              scale: 1 - _swipeDismiss.progress * 0.15,
              child: child,
            ),
          ),
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final data = widget.images[index];
              final heroTag =
                  widget.heroTagPrefix != null && index == _currentIndex
                  ? '${widget.heroTagPrefix}_${data.identifier}'
                  : null;
              final transformationController = _transformationControllers
                  .putIfAbsent(data.identifier, TransformationController.new);
              return DetailImagePage(
                key: ValueKey(data.identifier),
                data: data,
                heroTag: heroTag,
                transformationController: transformationController,
                onTouchTap: () =>
                    setState(() => _showControls = !_showControls),
                onDismissDragUpdate: _swipeDismiss.update,
                onDismissDragEnd: (velocity) =>
                    _swipeDismiss.end(velocity, reduceMotion: reduceMotion),
              );
            },
          ),
        ),

        // 顶部控制栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _HideableBar(
            visible: _showControls,
            hiddenOffset: const Offset(0, -1),
            dismiss: _swipeDismiss,
            child: DetailTopBar(
              currentIndex: _currentIndex,
              totalImages: widget.images.length,
              currentImage: _currentImage,
              onClose: () => _requestClose('top-bar-close'),
              onShowMetadata: showMetadataAction ? _showMetadataPanel : null,
              onReuseMetadata:
                  !parametersAreCurrent && callbacks?.onReuseMetadata != null
                  ? () => _handleReuseMetadata(context)
                  : null,
              onReuseSeed: callbacks?.onReuseSeed != null
                  ? () => callbacks!.onReuseSeed!(_currentImage)
                  : null,
              onFavoriteToggle: widget.callbacks?.onFavoriteToggle != null
                  ? () => widget.callbacks!.onFavoriteToggle!(_currentImage)
                  : null,
              onSave: widget.callbacks?.onSave != null
                  ? () => widget.callbacks!.onSave!(_currentImage)
                  : null,
              onCopyImage: _currentImage.showCopyButton
                  ? () => _copyImageToClipboard(context)
                  : null,
              onShare: PlatformCapabilities.current.supportsNativeShare
                  ? () => _shareImage(context)
                  : null,
              onWatermark: () => _openWatermarkEditor(context),
              onMosaic: () => _openMosaicEditor(context),
              onSendToImg2Img: widget.callbacks?.onSendToImg2Img != null
                  ? () => widget.callbacks!.onSendToImg2Img!(_currentImage)
                  : null,
              onSendToReversePrompt:
                  widget.callbacks?.onSendToReversePrompt != null
                  ? () =>
                        widget.callbacks!.onSendToReversePrompt!(_currentImage)
                  : null,
            ),
          ),
        ),

        // 底部缩略图栏
        if (showThumbnails)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _HideableBar(
              visible: _showControls,
              hiddenOffset: const Offset(0, 1),
              dismiss: _swipeDismiss,
              child: _buildBottomBar(),
            ),
          ),

        // 左右导航按钮：触屏直接左右滑动切图，按钮只会遮挡画面
        if (_showControls &&
            widget.images.length > 1 &&
            context.interactionPolicy.precisePointerAvailable) ...[
          if (_currentIndex > 0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavigationButton(
                  icon: Icons.chevron_left,
                  onPressed: () => _goToPage(_currentIndex - 1),
                ),
              ),
            ),
          if (_currentIndex < widget.images.length - 1)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavigationButton(
                  icon: Icons.chevron_right,
                  onPressed: () => _goToPage(_currentIndex + 1),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 100,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: DetailThumbnailBar(
        images: widget.images,
        currentIndex: _currentIndex,
        scrollController: _thumbnailController,
        onTap: _jumpToPage,
      ),
    );
  }

  /// 复制图像到剪贴板
  Future<void> _copyImageToClipboard(BuildContext context) async {
    final l10n = context.l10n;
    final transform = ref.read(copyDragWatermarkProvider);
    final stripMetadata = ref
        .read(shareImageSettingsProvider)
        .effectiveStripMetadataForCopyAndDrag;
    try {
      final imageBytes = await _currentImage.getImageBytes();
      final fileName = _currentImage.fileInfo?.fileName ?? 'shared.png';
      final shareImage =
          await ImageShareSanitizer.prepareForCopyOrDragInBackground(
            imageBytes,
            fileName: fileName,
            stripMetadata: stripMetadata,
            transform: transform,
          );

      // 跨平台复制到剪贴板（原 Windows 端走 PowerShell + System.Drawing，
      // macOS/Linux 不可用）。统一规范化为 PNG，避免 jpg/webp 原始字节被当成
      // PNG 导致粘贴失败。
      await writeImageBytesToClipboardAsPng(shareImage.bytes);

      if (context.mounted) {
        AppToast.success(context, l10n.image_copiedToClipboard);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, l10n.image_copyFailed(e.toString()));
      }
    }
  }

  Future<void> _openWatermarkEditor(BuildContext context) async {
    final fileInfo = _currentImage.fileInfo;
    if (fileInfo != null) {
      await WatermarkEditorLauncher.openForLocalPath(
        context: context,
        path: fileInfo.path,
      );
      return;
    }
    final bytes = await _currentImage.getImageBytes();
    if (!context.mounted) return;
    await WatermarkEditorLauncher.open(
      context: context,
      sourceBytes: bytes,
      sourceFileName: 'image.png',
    );
  }

  Future<void> _openMosaicEditor(BuildContext context) async {
    final fileInfo = _currentImage.fileInfo;
    if (fileInfo != null) {
      await MosaicEditorLauncher.openForLocalPath(
        context: context,
        path: fileInfo.path,
      );
      return;
    }
    final bytes = await _currentImage.getImageBytes();
    if (!context.mounted) return;
    await MosaicEditorLauncher.open(
      context: context,
      sourceBytes: bytes,
      sourceFileName: 'image.png',
    );
  }

  Future<void> _shareImage(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final imageBytes = await _currentImage.getImageBytes();
      final fileName = _currentImage.fileInfo?.fileName ?? 'shared.png';
      final stripMetadata = ref
          .read(shareImageSettingsProvider)
          .effectiveStripMetadataForCopyAndDrag;
      final shareImage = await ImageShareSanitizer.prepareForCopyOrDrag(
        imageBytes,
        fileName: fileName,
        stripMetadata: stripMetadata,
      );
      if (!context.mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      final origin = renderBox == null
          ? null
          : renderBox.localToGlobal(Offset.zero) & renderBox.size;
      await NativeShareService.shareImage(
        bytes: shareImage.bytes,
        fileName: shareImage.fileName,
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, l10n.image_shareFailed(error.toString()));
      }
    }
  }

  /// 处理复用元数据
  Future<void> _handleReuseMetadata(BuildContext context) async {
    final metadata = _currentImage.metadata;
    if (metadata == null || !metadata.hasData) {
      AppToast.warning(context, context.l10n.toast_imageHasNoMetadata);
      return;
    }

    await widget.callbacks?.onReuseMetadata?.call(_currentImage);
    if (!context.mounted) return;

    // 关闭图像详情页
    if (context.mounted) {
      _requestClose('reuse-metadata');
    }
  }

  @override
  void dispose() {
    _swipeDismiss.dispose();
    _metadataPanelWidthController.dispose();
    for (final controller in _transformationControllers.values) {
      controller.dispose();
    }
    _transformationControllers.clear();
    _pageController.dispose();
    _thumbnailController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

/// 导航按钮
class _NavigationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavigationButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

/// Paints the viewer backdrop; it fades while the image is swiped down so the
/// page underneath shows through.
class _SwipeDismissBackdrop extends StatelessWidget {
  const _SwipeDismissBackdrop({
    required this.controller,
    required this.canFade,
    required this.child,
  });

  final DetailSwipeDismissController controller;
  final bool canFade;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => ColoredBox(
      color: ImageViewportSurface.background.withValues(
        alpha: canFade ? 1 - controller.progress : 1,
      ),
      child: child,
    ),
    child: child,
  );
}

/// A top or bottom bar that slides out when the controls are hidden and fades
/// while the image is swiped down.
class _HideableBar extends StatelessWidget {
  const _HideableBar({
    required this.visible,
    required this.hiddenOffset,
    required this.dismiss,
    required this.child,
  });

  final bool visible;
  final Offset hiddenOffset;
  final DetailSwipeDismissController dismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: duration,
        curve: Curves.easeOut,
        child: ListenableBuilder(
          listenable: dismiss,
          builder: (context, child) => Opacity(
            opacity: (1 - dismiss.progress * 4).clamp(0.0, 1.0),
            child: child,
          ),
          child: child,
        ),
      ),
    );
  }
}
