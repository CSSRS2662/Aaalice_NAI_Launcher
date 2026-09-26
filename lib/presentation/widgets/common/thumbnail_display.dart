import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:image/image.dart' as img;

import 'image_viewport_surface.dart';

/// 缩略图显示组件
///
/// 使用与裁剪对话框相同的正方形焦点区域。无论最终容器是横向、
/// 方形还是纵向，该区域都会完整显示在容器中心；区域外的原图内容
/// 只用于填充当前容器剩余空间。
class ThumbnailDisplay extends StatefulWidget {
  final String imagePath;
  final double offsetX;
  final double offsetY;
  final double scale;

  /// 显示区域的宽度
  final double width;

  /// 显示区域的高度
  final double height;

  final BorderRadius? borderRadius;

  const ThumbnailDisplay({
    super.key,
    required this.imagePath,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.width = 200,
    this.height = 80,
    this.borderRadius,
  });

  @override
  State<ThumbnailDisplay> createState() => _ThumbnailDisplayState();
}

class _ThumbnailDisplayState extends State<ThumbnailDisplay> {
  Size? _imageSize;
  int _imageSizeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(ThumbnailDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImageSize();
    }
  }

  Future<void> _loadImageSize() async {
    final requestId = ++_imageSizeRequestId;
    final imageSize = await _readImageSize(widget.imagePath);

    if (!mounted || requestId != _imageSizeRequestId) return;
    setState(() => _imageSize = imageSize);
  }

  Future<Size?> _readImageSize(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null) return null;
      return Size(info.width.toDouble(), info.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _imageSizeRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 尺寸加载完成前先完整显示图像，避免短暂裁掉用户选中的焦点。
    if (_imageSize == null) {
      return _buildSimpleImage();
    }

    final ox = widget.offsetX.clamp(-1.0, 1.0);
    final oy = widget.offsetY.clamp(-1.0, 1.0);
    final s = widget.scale.clamp(1.0, 3.0);
    final containerWidth = widget.width;
    final containerHeight = widget.height;
    final imageWidth = _imageSize!.width;
    final imageHeight = _imageSize!.height;

    // scale 表示正方形焦点框相对“图像可容纳的最大正方形”的缩放。
    final cropSide = math.min(imageWidth, imageHeight) / s;
    final maxCenterOffsetX = (imageWidth - cropSide) / 2;
    final maxCenterOffsetY = (imageHeight - cropSide) / 2;
    final cropCenter = Offset(
      imageWidth / 2 + ox * maxCenterOffsetX,
      imageHeight / 2 + oy * maxCenterOffsetY,
    );

    // 让焦点正方形完整适配容器的短边，然后把它的中心固定到容器中心。
    final viewportScale = math.min(containerWidth, containerHeight) / cropSide;
    final renderedWidth = imageWidth * viewportScale;
    final renderedHeight = imageHeight * viewportScale;
    final renderedLeft = containerWidth / 2 - cropCenter.dx * viewportScale;
    final renderedTop = containerHeight / 2 - cropCenter.dy * viewportScale;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    Widget image = ClipRect(
      child: SizedBox(
        width: containerWidth,
        height: containerHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: renderedLeft,
              top: renderedTop,
              width: renderedWidth,
              height: renderedHeight,
              child: Image.file(
                File(widget.imagePath),
                width: renderedWidth,
                height: renderedHeight,
                cacheWidth: _decodeCacheExtent(renderedWidth, devicePixelRatio),
                cacheHeight: _decodeCacheExtent(
                  renderedHeight,
                  devicePixelRatio,
                ),
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => _buildError(),
              ),
            ),
          ],
        ),
      ),
    );

    image = ImageViewportSurface(child: image);

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }

    return image;
  }

  Widget _buildSimpleImage() {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    Widget image = ClipRect(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Image.file(
          File(widget.imagePath),
          cacheWidth: _decodeCacheExtent(widget.width, devicePixelRatio),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildError(),
        ),
      ),
    );

    image = ImageViewportSurface(child: image);

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }

    return image;
  }

  Widget _buildError() => Container(
    width: widget.width,
    height: widget.height,
    color: ImageViewportSurface.background,
    child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
  );

  static int? _decodeCacheExtent(
    double logicalExtent,
    double devicePixelRatio,
  ) {
    if (!logicalExtent.isFinite ||
        !devicePixelRatio.isFinite ||
        logicalExtent <= 0 ||
        devicePixelRatio <= 0) {
      return null;
    }

    return (logicalExtent * devicePixelRatio).ceil().clamp(1, 1 << 30);
  }
}
