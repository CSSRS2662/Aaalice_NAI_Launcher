import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_version.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/adaptive_layout.dart';
import '../../providers/warmup_provider.dart';
import '../../utils/warmup_message_localizer.dart';

/// 启动画面
/// 显示应用品牌和预加载进度
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _backgroundTop = Color(0xFF2B182D);
  static const _backgroundMiddle = Color(0xFF211424);
  static const _backgroundBottom = Color(0xFF120E19);
  static const _brandPink = Color(0xFFFF7F9F);
  static const _brandPeach = Color(0xFFFFB07C);
  static const _brandTeal = Color(0xFF73E2DD);

  late final AnimationController _introController;
  late final Animation<double> _artOpacity;
  late final Animation<Offset> _artOffset;
  late final Animation<double> _titleOpacity;
  bool? _motionEnabled;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _artOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, 0.42, curve: Curves.easeOut),
    );
    _artOffset = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _introController,
            curve: const Interval(0, 0.64, curve: Curves.easeOutCubic),
          ),
        );
    _titleOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.28, 0.76, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionEnabled = !MediaQuery.disableAnimationsOf(context);
    if (_motionEnabled == motionEnabled) return;
    _motionEnabled = motionEnabled;
    if (motionEnabled) {
      if (_introController.isDismissed) {
        _introController.forward();
      }
    } else {
      _introController.value = 1;
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warmupState = ref.watch(warmupNotifierProvider);
    final progress = warmupState.progress;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _backgroundBottom,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: AdaptiveSlotLayout(
              builder: (context, areas) => SingleChildScrollView(
                key: const ValueKey('splash_scroll_view'),
                padding: EdgeInsets.fromLTRB(
                  areas.horizontalPadding,
                  16,
                  areas.horizontalPadding,
                  48,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (areas.constraints.maxHeight - 64)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
                  ),
                  child: AdaptiveContentBounds(
                    maxWidth: 640,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBrandArt(),
                        const SizedBox(height: 18),
                        _buildTitle(theme),
                        const SizedBox(height: 42),
                        _buildProgressSection(
                          theme,
                          _brandPink,
                          progress,
                          warmupState.subTaskMessage,
                          warmupState.error,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16 + MediaQuery.paddingOf(context).right,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: Text(
              AppVersion.versionName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.34),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, child) {
        final reveal = Curves.easeOut.transform(_introController.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _backgroundTop,
                    _backgroundMiddle,
                    _backgroundBottom,
                  ],
                  stops: [0, 0.52, 1],
                ),
              ),
            ),
            Opacity(
              opacity: 0.28 + reveal * 0.32,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.34),
                    radius: 0.82,
                    colors: [Color(0x66FF718F), Color(0x0017101F)],
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: CustomPaint(painter: _PixelBackdropPainter()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBrandArt() {
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, child) {
        return FadeTransition(
          key: const ValueKey('splash-brand-art-transition'),
          opacity: _artOpacity,
          child: SlideTransition(
            position: _artOffset,
            child: SizedBox(
              width: 220,
              height: 190,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 156,
                    height: 156,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(46),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66FF708F),
                          blurRadius: 44,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Color(0x4073E2DD),
                          blurRadius: 24,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                    key: const ValueKey('splash-brand-art'),
                    width: 176,
                    height: 176,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    excludeFromSemantics: true,
                  ),
                  Positioned(
                    left: 8,
                    top: 34,
                    child: _PixelSpark(
                      opacity: _introInterval(0.34, 0.58),
                      color: _brandPeach,
                      pixelSize: 4,
                    ),
                  ),
                  Positioned(
                    right: 5,
                    top: 56,
                    child: _PixelSpark(
                      opacity: _introInterval(0.48, 0.72),
                      color: _brandTeal,
                      pixelSize: 3,
                    ),
                  ),
                  Positioned(
                    right: 22,
                    bottom: 9,
                    child: _PixelSpark(
                      opacity: _introInterval(0.62, 0.88),
                      color: _brandPink,
                      pixelSize: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _introInterval(double begin, double end) {
    final progress = ((_introController.value - begin) / (end - begin))
        .clamp(0.0, 1.0)
        .toDouble();
    return Curves.easeOut.transform(progress);
  }

  Widget _buildTitle(ThemeData theme) {
    return FadeTransition(
      opacity: _titleOpacity,
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_brandPink, _brandPeach],
            ).createShader(bounds),
            child: const Text(
              'Aaalice Pocket',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'NovelAI Image Generation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.58),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(
    ThemeData theme,
    Color primaryColor,
    WarmupProgress progress,
    String? subTaskMessage,
    String? error,
  ) {
    final l10n = context.l10n;
    final translatedTask = WarmupMessageLocalizer.localizeTask(
      l10n,
      progress.currentTask,
    );
    final percentage = (progress.progress * 100).toInt();

    return AdaptiveContentBounds(
      maxWidth: 520,
      child: Column(
        children: [
          if (error != null) ...[
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 28),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                WarmupMessageLocalizer.localizeError(l10n, error),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('warmup_retry'),
              onPressed: () {
                ref.read(warmupNotifierProvider.notifier).retry();
              },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.common_retry),
            ),
          ] else ...[
            // 进度条 + 百分比
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: _buildProgressBar(
                      theme,
                      primaryColor,
                      progress.progress,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 百分比文字（使用等宽数字特性）
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 42),
                  child: Text(
                    '$percentage%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 当前任务（带加载指示器）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Row(
                key: ValueKey(progress.currentTask),
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!progress.isComplete) ...[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      translatedTask,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 子任务进度（如"下载中... 50%"）
            if (subTaskMessage != null && !progress.isComplete) ...[
              const SizedBox(height: 8),
              Text(
                WarmupMessageLocalizer.localizeSubTask(l10n, subTaskMessage),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme, Color primaryColor, double value) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 进度填充
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * value,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(colors: [primaryColor, _brandPeach]),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PixelSpark extends StatelessWidget {
  const _PixelSpark({
    required this.opacity,
    required this.color,
    required this.pixelSize,
  });

  final double opacity;
  final Color color;
  final double pixelSize;

  @override
  Widget build(BuildContext context) {
    final extent = pixelSize * 3;
    return Opacity(
      opacity: opacity,
      child: SizedBox.square(
        dimension: extent,
        child: Stack(
          children: [
            Positioned(
              left: pixelSize,
              child: ColoredBox(
                color: color,
                child: SizedBox(width: pixelSize, height: extent),
              ),
            ),
            Positioned(
              top: pixelSize,
              child: ColoredBox(
                color: color,
                child: SizedBox(width: extent, height: pixelSize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelBackdropPainter extends CustomPainter {
  const _PixelBackdropPainter();

  static const _pixels = <({double x, double y, double size, Color color})>[
    (x: 0.08, y: 0.16, size: 3, color: Color(0x36FF7F9F)),
    (x: 0.16, y: 0.27, size: 2, color: Color(0x2E73E2DD)),
    (x: 0.88, y: 0.18, size: 3, color: Color(0x32FFB07C)),
    (x: 0.78, y: 0.32, size: 2, color: Color(0x2673E2DD)),
    (x: 0.1, y: 0.72, size: 2, color: Color(0x24FFB07C)),
    (x: 0.9, y: 0.66, size: 3, color: Color(0x28FF7F9F)),
    (x: 0.2, y: 0.9, size: 2, color: Color(0x2073E2DD)),
    (x: 0.82, y: 0.88, size: 2, color: Color(0x20FFB07C)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final pixel in _pixels) {
      paint.color = pixel.color;
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * pixel.x,
          size.height * pixel.y,
          pixel.size,
          pixel.size,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBackdropPainter oldDelegate) => false;
}
