import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';

import '../../../app.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/first_launch_detector.dart';
import '../../../core/windowing/windows_native_window_state.dart';
import '../../../core/utils/locale_provider.dart';
import '../../providers/warmup_provider.dart';
import '../../widgets/common/desktop_window_frame.dart';
import 'splash_screen.dart';

/// 应用启动引导器
/// 管理预加载流程和页面切换
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key, this.mainAppBuilder, this.onWarmupComplete});

  @visibleForTesting
  final WidgetBuilder? mainAppBuilder;
  final VoidCallback? onWarmupComplete;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  bool _showMainApp = false;
  bool _showSplashOverlay = true;
  bool _hasCheckedFirstLaunch = false;
  bool _mainAppMountScheduled = false;
  bool _warmupCompletionNotified = false;
  Widget? _mountedMainApp;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isWindows) {
      unawaited(_synchronizeWindowsViewMetrics());
    }
  }

  Future<void> _synchronizeWindowsViewMetrics() async {
    try {
      await const WindowsNativeWindowStatePlatform().synchronizeViewMetrics();
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to synchronize Windows view metrics after hot reload',
        error,
        stackTrace,
        'AppBootstrap',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppLogger.i(
        'Splash first frame rendered; starting warmup',
        'AppBootstrap',
      );
      ref.read(warmupNotifierProvider.notifier).start();
    });
  }

  void _scheduleMainAppMount() {
    if (_mainAppMountScheduled) return;
    _mainAppMountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showMainApp) return;
      setState(() {
        _showMainApp = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showSplashOverlay) return;
        setState(() {
          _showSplashOverlay = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _warmupCompletionNotified) return;
          _warmupCompletionNotified = true;
          AppLogger.i('Main application first frame rendered', 'AppBootstrap');
          widget.onWarmupComplete?.call();
        });
      });
    });
  }

  Widget _buildSplash() {
    final locale = ref.watch(localeNotifierProvider);
    return MaterialApp(
      title: 'Aaalice Pocket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => DesktopWindowFrame(child: child!),
      home: const SplashScreen(key: ValueKey('splash')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warmupState = ref.watch(warmupNotifierProvider);

    if (warmupState.isComplete && !_showMainApp) {
      _scheduleMainAppMount();
    }

    if (!_showMainApp) {
      return _buildSplash();
    }

    // Cache the complete mounted subtree. Recreating this widget while merely
    // removing Splash would update and rebuild the entire router hierarchy.
    final mountedMainApp = _mountedMainApp ??=
        widget.mainAppBuilder?.call(context) ??
        _MainAppWrapper(
          hasCheckedFirstLaunch: _hasCheckedFirstLaunch,
          onFirstLaunchChecked: () {
            _hasCheckedFirstLaunch = true;
          },
        );
    // Keep the root and both child identities stable while hiding Splash.
    // Removing the overlay would relayout the complete router tree; returning
    // mountedMainApp directly would additionally remount it.
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        mountedMainApp,
        Opacity(
          key: const ValueKey('splash_overlay'),
          opacity: _showSplashOverlay ? 1 : 0,
          child: TickerMode(
            enabled: _showSplashOverlay,
            child: IgnorePointer(
              ignoring: !_showSplashOverlay,
              child: ExcludeSemantics(
                excluding: !_showSplashOverlay,
                child: _buildSplash(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 主应用包装器，用于在应用启动后触发首次启动检测
class _MainAppWrapper extends ConsumerStatefulWidget {
  final bool hasCheckedFirstLaunch;
  final VoidCallback onFirstLaunchChecked;

  const _MainAppWrapper({
    required this.hasCheckedFirstLaunch,
    required this.onFirstLaunchChecked,
  });

  @override
  ConsumerState<_MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends ConsumerState<_MainAppWrapper> {
  @override
  void initState() {
    super.initState();

    // 在应用启动后检查首次启动
    if (!widget.hasCheckedFirstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkFirstLaunch();
      });
    }
  }

  Future<void> _checkFirstLaunch() async {
    if (!mounted) return;

    widget.onFirstLaunchChecked();

    // 执行首次启动检测和同步
    await ref.read(firstLaunchNotifierProvider.notifier).checkAndSync(context);
  }

  @override
  Widget build(BuildContext context) {
    return const NAILauncherApp(key: ValueKey('main'));
  }
}
