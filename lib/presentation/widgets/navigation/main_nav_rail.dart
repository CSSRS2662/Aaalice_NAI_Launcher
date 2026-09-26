import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../../../core/constants/app_version.dart';
import '../../../data/models/auth/saved_account.dart';
import '../../../data/services/account_manager_provider.dart';
import '../../providers/auth_mode_provider.dart';
import '../../../data/services/auth_provider.dart';
import '../../../core/services/auth_error_service.dart';
import '../../providers/layout_state_provider.dart';
import '../../providers/queue_execution_provider.dart';
import '../../providers/replication_queue_provider.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../router/app_branch.dart';
import '../../router/app_routes.dart';
import '../../themes/theme_extension.dart';
import '../auth/account_avatar.dart';
import '../auth/login_form_container.dart';

import '../common/app_toast.dart';

Duration _boundedMotionDuration(
  BuildContext context,
  Duration source, {
  required int minMilliseconds,
  required int maxMilliseconds,
}) {
  if (MediaQuery.disableAnimationsOf(context)) return Duration.zero;
  return Duration(
    milliseconds: source.inMilliseconds.clamp(minMilliseconds, maxMilliseconds),
  );
}

double _railItemMinHeight(BuildContext context) =>
    MediaQuery.textScalerOf(
      context,
    ).scale(14).clamp(36, double.infinity).toDouble() +
    12;

class MainNavRail extends ConsumerWidget {
  static const double collapsedWidth = 60;
  static const double expandedWidth = 196;

  static double expandedWidthFor(BuildContext context) {
    final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
    return (expandedWidth + (scaledBodySize - 14).clamp(0, 28) * 3)
        .clamp(expandedWidth, 280)
        .toDouble();
  }

  static const List<AppBranch> _railBranches = [
    AppBranch.generation,
    AppBranch.localGallery,
    AppBranch.onlineGallery,
    AppBranch.vibeLibrary,
    AppBranch.preciseRefLibrary,
    AppBranch.promptConfig,
    AppBranch.tagLibrary,
    AppBranch.statistics,
    AppBranch.settings,
  ];

  final StatefulNavigationShell navigationShell;
  final bool isAgentVisible;
  final bool isAgentRunning;
  final bool isQueueVisible;
  final bool allowExpansion;
  final FocusNode? agentFocusNode;
  final FocusNode? queueFocusNode;
  final ValueChanged<bool> onAgentVisibilityChanged;
  final ValueChanged<bool> onQueueVisibilityChanged;

  const MainNavRail({
    super.key,
    required this.navigationShell,
    this.isAgentVisible = false,
    this.isAgentRunning = false,
    this.isQueueVisible = false,
    this.allowExpansion = true,
    this.agentFocusNode,
    this.queueFocusNode,
    this.onAgentVisibilityChanged = _ignorePanelVisibilityChange,
    this.onQueueVisibilityChanged = _ignorePanelVisibilityChange,
  });

  static void _ignorePanelVisibilityChange(bool _) {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storedExpansion = ref.watch(
      layoutStateNotifierProvider.select((state) => state.mainNavRailExpanded),
    );
    final isExpanded = allowExpansion && storedExpansion;

    final queueCount = ref.watch(
      replicationQueueNotifierProvider.select((state) => state.count),
    );
    final queueExecutionStatus = ref.watch(
      queueExecutionNotifierProvider.select((state) => state.status),
    );
    final currentIndex = navigationShell.currentIndex;
    final selectedIndex = _railBranches.indexWhere(
      (branch) => branch.index == currentIndex,
    );
    final motion = theme.appTheme;
    final animationDuration = _boundedMotionDuration(
      context,
      motion.slowDuration,
      minMilliseconds: 180,
      maxMilliseconds: 240,
    );

    return _NavRailWidthTransition(
      isExpanded: isExpanded,
      expandedWidth: expandedWidthFor(context),
      duration: animationDuration,
      enterCurve: motion.enterCurve,
      exitCurve: motion.exitCurve,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // 账户头像区域
          _AccountAvatarButton(ref: ref),

          Expanded(
            child: SingleChildScrollView(
              key: const Key('main-nav-primary-scroll'),
              child: Column(
                children: [
                  // Navigation Items
                  _NavIcon(
                    key: const Key('nav-branch-0'),
                    icon: Icons.brush, // Canvas/Edit
                    label: context.l10n.nav_canvas,
                    isSelected: selectedIndex == 0,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.generation.index),
                  ),

                  // 本地图库（App生成的图片）
                  _NavIcon(
                    key: const Key('nav-branch-1'),
                    icon: Icons.folder, // Local Generated Images
                    label: context.l10n.nav_localGallery,
                    isSelected: selectedIndex == 1,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.localGallery.index),
                  ),

                  // 在线画廊
                  _NavIcon(
                    key: const Key('nav-branch-2'),
                    icon: Icons.photo_library, // Online Gallery
                    label: context.l10n.nav_onlineGallery,
                    isSelected: selectedIndex == 2,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.onlineGallery.index),
                  ),

                  // Vibe库
                  _NavIcon(
                    key: const Key('nav-branch-3'),
                    icon: Icons.auto_awesome, // Vibe Library
                    label: context.l10n.vibeLibrary_title,
                    isSelected: selectedIndex == 3,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.vibeLibrary.index),
                  ),

                  // 精准参考库
                  _NavIcon(
                    key: const Key('nav-branch-4'),
                    icon: Icons.center_focus_strong,
                    label: context.l10n.nav_preciseRefLibrary,
                    isSelected: selectedIndex == 4,
                    onTap: () => navigationShell.goBranch(
                      AppBranch.preciseRefLibrary.index,
                    ),
                  ),

                  // 词库
                  _NavIcon(
                    key: const Key('nav-branch-6'),
                    icon: Icons.book,
                    label: context.l10n.nav_dictionary,
                    isSelected: selectedIndex == 6,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.tagLibrary.index),
                  ),

                  // 随机配置
                  _NavIcon(
                    key: const Key('nav-branch-5'),
                    icon: Icons.casino, // Random prompt config
                    label: context.l10n.nav_randomConfig,
                    isSelected: selectedIndex == 5,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.promptConfig.index),
                  ),

                  // 统计
                  _NavIcon(
                    key: const Key('nav-branch-7'),
                    icon: Icons.bar_chart, // Gallery Statistics
                    label: context.l10n.nav_statistics,
                    isSelected: selectedIndex == 7,
                    onTap: () =>
                        navigationShell.goBranch(AppBranch.statistics.index),
                  ),
                ],
              ),
            ),
          ),

          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                key: const Key('main-nav-secondary-scroll'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _NavIcon(
                        key: const Key('agent-nav-item'),
                        focusNode: agentFocusNode,
                        icon: isAgentRunning
                            ? Icons.smart_toy_rounded
                            : Icons.smart_toy_outlined,
                        label: context.l10n.nav_agent,
                        isSelected: isAgentVisible,
                        showBadge: isAgentRunning,
                        onTap: () => onAgentVisibilityChanged(!isAgentVisible),
                      ),

                      _NavIcon(
                        key: const Key('queue-nav-item'),
                        focusNode: queueFocusNode,
                        icon: switch (queueExecutionStatus) {
                          QueueExecutionStatus.running =>
                            Icons.play_arrow_rounded,
                          QueueExecutionStatus.paused => Icons.pause_rounded,
                          _ => Icons.playlist_play_rounded,
                        },
                        label: context.l10n.queue_management,
                        isSelected: isQueueVisible,
                        badgeLabel: queueCount > 0
                            ? (queueCount > 99 ? '99+' : queueCount.toString())
                            : null,
                        onTap: () => onQueueVisibilityChanged(!isQueueVisible),
                      ),

                      // Bottom Settings
                      _NavIcon(
                        key: const Key('nav-branch-8'),
                        icon: Icons.settings,
                        label: context.l10n.nav_settings,
                        isSelected: selectedIndex == 8,
                        onTap: () =>
                            navigationShell.goBranch(AppBranch.settings.index),
                      ),
                      if (allowExpansion) ...[
                        const SizedBox(height: 2),
                        _NavRailToggle(
                          isExpanded: isExpanded,
                          onTap: () {
                            ref
                                .read(layoutStateNotifierProvider.notifier)
                                .toggleMainNavRail();
                          },
                        ),
                      ],
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRailWidthTransition extends StatefulWidget {
  const _NavRailWidthTransition({
    required this.isExpanded,
    required this.expandedWidth,
    required this.duration,
    required this.enterCurve,
    required this.exitCurve,
    required this.decoration,
    required this.child,
  });

  final bool isExpanded;
  final double expandedWidth;
  final Duration duration;
  final Curve enterCurve;
  final Curve exitCurve;
  final Decoration decoration;
  final Widget child;

  @override
  State<_NavRailWidthTransition> createState() =>
      _NavRailWidthTransitionState();
}

// 宽度与所有标签共享同一时间轴，避免高频切换同时启动多组 ticker。
class _NavRailWidthTransitionState extends State<_NavRailWidthTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _widthExpansion;
  late CurvedAnimation _contentReveal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.isExpanded ? 1 : 0,
      duration: widget.duration,
    );
    _updateAnimations();
  }

  @override
  void didUpdateWidget(_NavRailWidthTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.enterCurve != widget.enterCurve ||
        oldWidget.exitCurve != widget.exitCurve) {
      _widthExpansion.dispose();
      _contentReveal.dispose();
      _updateAnimations();
    }
    if (oldWidget.isExpanded != widget.isExpanded ||
        oldWidget.duration != widget.duration) {
      _animateToTarget();
    }
  }

  void _updateAnimations() {
    _widthExpansion = CurvedAnimation(
      parent: _controller,
      curve: _ClampedCurve(widget.enterCurve),
      reverseCurve: _ClampedCurve(widget.exitCurve),
    );
    // Labels appear only after the rail has made room and disappear before
    // contraction can clip them. Icons remain fixed on the leading edge.
    _contentReveal = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.32, 0.82, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.32, 0.82, curve: Curves.easeInCubic),
    );
  }

  void _animateToTarget() {
    if (widget.duration == Duration.zero) {
      _controller.value = widget.isExpanded ? 1 : 0;
      return;
    }
    if (widget.isExpanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _widthExpansion.dispose();
    _contentReveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _widthExpansion,
      builder: (context, child) {
        final width =
            MainNavRail.collapsedWidth +
            (widget.expandedWidth - MainNavRail.collapsedWidth) *
                _widthExpansion.value;
        return Container(
          key: const Key('main-nav-rail'),
          width: width,
          height: double.infinity,
          clipBehavior: Clip.hardEdge,
          decoration: widget.decoration,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: widget.expandedWidth,
            maxWidth: widget.expandedWidth,
            child: RepaintBoundary(
              child: SizedBox(
                key: const Key('main-nav-rail-content'),
                width: widget.expandedWidth,
                height: double.infinity,
                child: child,
              ),
            ),
          ),
        );
      },
      child: _NavRailExpansionScope(
        isExpanded: widget.isExpanded,
        expansion: _contentReveal,
        child: widget.child,
      ),
    );
  }
}

class _ClampedCurve extends Curve {
  const _ClampedCurve(this.curve);

  final Curve curve;

  @override
  double transformInternal(double t) => curve.transform(t).clamp(0.0, 1.0);
}

class _NavRailExpansionScope extends InheritedWidget {
  const _NavRailExpansionScope({
    required this.isExpanded,
    required this.expansion,
    required super.child,
  });

  final bool isExpanded;
  final Animation<double> expansion;

  static _NavRailExpansionScope of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_NavRailExpansionScope>()!;
  }

  static bool isExpandedOf(BuildContext context) => of(context).isExpanded;

  @override
  bool updateShouldNotify(_NavRailExpansionScope oldWidget) {
    return isExpanded != oldWidget.isExpanded ||
        expansion != oldWidget.expansion;
  }
}

class _ExpandedRailContent extends StatelessWidget {
  const _ExpandedRailContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _NavRailExpansionScope.of(context);
    return FadeTransition(opacity: scope.expansion, child: child);
  }
}

class _NavRailToggle extends StatelessWidget {
  const _NavRailToggle({required this.isExpanded, required this.onTap});

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isExpanded
        ? context.l10n.nav_collapseSidebar
        : context.l10n.nav_expandSidebar;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _railItemMinHeight(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Tooltip(
                  message: label,
                  preferBelow: false,
                  verticalOffset: 24,
                  child: SizedBox(
                    key: const Key('main-nav-toggle'),
                    width: 48,
                    height: 48,
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_double_arrow_left
                          : Icons.keyboard_double_arrow_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ExpandedRailContent(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                _ExpandedRailContent(
                  child: Text(
                    'v${AppVersion.versionName}',
                    key: const Key('main-nav-version'),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showBadge;
  final String? badgeLabel;
  final FocusNode? focusNode;

  const _NavIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.showBadge = false,
    this.badgeLabel,
    this.focusNode,
  });

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pressDuration = _boundedMotionDuration(
      context,
      theme.appTheme.fastDuration,
      minMilliseconds: 100,
      maxMilliseconds: 140,
    );
    final hoverDuration = _boundedMotionDuration(
      context,
      theme.appTheme.normalDuration,
      minMilliseconds: 120,
      maxMilliseconds: 180,
    );
    final color = widget.isSelected
        ? theme.colorScheme.primary
        : theme.iconTheme.color?.withValues(alpha: 0.7);

    // 计算背景色：选中状态优先，其次是 Hover 状态
    Color backgroundColor = Colors.transparent;
    if (widget.isSelected) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.16);
    } else if (_isHovering) {
      backgroundColor = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      constraints: BoxConstraints(minHeight: _railItemMinHeight(context)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: widget.focusNode,
          focusColor: Colors.transparent,
          onTap: widget.onTap,
          onHover: (val) => setState(() => _isHovering = val),
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedScale(
            scale: _isPressed ? 0.97 : 1.0,
            duration: pressDuration,
            curve: theme.appTheme.standardCurve,
            child: AnimatedContainer(
              duration: hoverDuration,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: widget.label,
                    preferBelow: false,
                    verticalOffset: 24,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Badge(
                          isLabelVisible:
                              widget.showBadge || widget.badgeLabel != null,
                          smallSize: 7,
                          label: widget.badgeLabel == null
                              ? null
                              : Text(widget.badgeLabel!),
                          child: Icon(widget.icon, color: color, size: 24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ExpandedRailContent(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: widget.isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 账户头像按钮组件
class _AccountAvatarButton extends StatefulWidget {
  final WidgetRef ref;

  const _AccountAvatarButton({required this.ref});

  @override
  State<_AccountAvatarButton> createState() => _AccountAvatarButtonState();
}

class _AccountAvatarButtonState extends State<_AccountAvatarButton> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pressDuration = _boundedMotionDuration(
      context,
      theme.appTheme.fastDuration,
      minMilliseconds: 100,
      maxMilliseconds: 140,
    );
    final hoverDuration = _boundedMotionDuration(
      context,
      theme.appTheme.normalDuration,
      minMilliseconds: 120,
      maxMilliseconds: 180,
    );
    final authState = widget.ref.watch(authNotifierProvider);
    final accounts = widget.ref.watch(accountManagerNotifierProvider).accounts;

    // 获取当前账户
    SavedAccount? currentAccount;
    if (authState.isAuthenticated && authState.accountId != null) {
      try {
        currentAccount = accounts.firstWhere(
          (a) => a.id == authState.accountId,
        );
      } catch (_) {
        currentAccount = null;
      }
    }
    if (currentAccount == null &&
        (authState.status == AuthStatus.loading || authState.hasError)) {
      final sortedAccounts = widget.ref
          .read(accountManagerNotifierProvider.notifier)
          .sortedAccounts;
      if (sortedAccounts.isNotEmpty) {
        currentAccount = sortedAccounts.first;
      }
    }

    final avatar = currentAccount != null
        ? AccountAvatarSmall(account: currentAccount, size: 40)
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          );

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      constraints: BoxConstraints(minHeight: _railItemMinHeight(context)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('main-nav-account-menu-button'),
          onTap: () => _showAccountMenu(context, currentAccount),
          onHover: (val) => setState(() => _isHovering = val),
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedScale(
            scale: _isPressed ? 0.97 : 1.0,
            duration: pressDuration,
            curve: theme.appTheme.standardCurve,
            child: AnimatedContainer(
              duration: hoverDuration,
              decoration: BoxDecoration(
                color: _isHovering
                    ? theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message:
                        currentAccount?.displayName ?? context.l10n.auth_login,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: avatar),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ExpandedRailContent(
                      child: Text(
                        currentAccount?.displayName ?? context.l10n.auth_login,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  _ExpandedRailContent(
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示账户菜单
  Future<void> _showAccountMenu(
    BuildContext context,
    SavedAccount? currentAccount,
  ) async {
    final theme = Theme.of(context);
    final authState = widget.ref.read(authNotifierProvider);
    final accounts = authState.isAuthenticated
        ? widget.ref.read(accountManagerNotifierProvider).accounts
        : const <SavedAccount>[];
    final menuCurrentAccount = authState.isAuthenticated
        ? currentAccount
        : null;

    // 获取按钮的位置用于定位菜单
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 使用 Rect 定义菜单弹出的锚点位置
    final railWidth = _NavRailExpansionScope.isExpandedOf(context)
        ? MainNavRail.expandedWidthFor(context)
        : MainNavRail.collapsedWidth;
    final menuAnchor = Rect.fromLTWH(
      railWidth + 8,
      offset.dy,
      1,
      button.size.height,
    );

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(menuAnchor, Offset.zero & screenSize),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        if (!authState.isAuthenticated)
          PopupMenuItem<String>(
            value: 'login',
            child: Row(
              children: [
                Icon(Icons.login, color: theme.colorScheme.onSurface, size: 20),
                const SizedBox(width: 12),
                Text(context.l10n.auth_login),
              ],
            ),
          ),

        // 当前账号标题
        if (menuCurrentAccount != null)
          PopupMenuItem<String>(
            enabled: false,
            height: 40,
            child: Text(
              '${context.l10n.auth_currentAccount}: ${menuCurrentAccount.displayName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),

        // 分割线
        if (menuCurrentAccount != null && accounts.length > 1)
          const PopupMenuDivider(),

        // 账号列表
        ...accounts.map(
          (account) => PopupMenuItem<String>(
            value: 'switch_${account.id}',
            child: Row(
              children: [
                AccountAvatarSmall(account: account, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (account.id == authState.accountId)
                  Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),

        if (authState.isAuthenticated) const PopupMenuDivider(),

        // 添加账号
        if (authState.isAuthenticated)
          PopupMenuItem<String>(
            value: 'add',
            child: Row(
              children: [
                Icon(Icons.add, color: theme.colorScheme.onSurface, size: 20),
                const SizedBox(width: 12),
                Text(context.l10n.auth_addAccount),
              ],
            ),
          ),

        // 退出登录
        if (authState.isAuthenticated)
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 12),
                Text(
                  context.l10n.auth_logout,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ),
          ),
      ],
    );

    if (value == null || !mounted) return;

    if (value == 'login') {
      // ignore: use_build_context_synchronously
      context.push(AppRoutes.login);
    } else if (value == 'add') {
      if (mounted) {
        // ignore: use_build_context_synchronously
        _showAddAccountDialog(context);
      }
    } else if (value == 'logout') {
      // Use SchedulerBinding.endOfFrame to ensure logout happens AFTER the menu is fully disposed
      // This prevents the "ref.listen can only be used within build method" error that occurs when
      // The router auth listener can run during menu disposal. endOfFrame is more reliable
      // than addPostFrameCallback because it waits for the entire frame to complete, including all
      // post-frame callbacks and microtasks, ensuring the widget tree is stable.
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (mounted) {
          widget.ref.read(authNotifierProvider.notifier).logout();
        }
      });
    } else if (value.startsWith('switch_')) {
      final accountId = value.substring(7);
      _switchAccount(accountId);
    }
  }

  /// 切换账号
  Future<void> _switchAccount(String accountId) async {
    final accounts = widget.ref.read(accountManagerNotifierProvider).accounts;
    final account = accounts.firstWhere((a) => a.id == accountId);

    // 获取 Token
    final token = await widget.ref
        .read(accountManagerNotifierProvider.notifier)
        .getAccountToken(account.id);

    if (token == null) {
      if (mounted) {
        AppToast.info(context, context.l10n.auth_tokenNotFound);
      }
      return;
    }

    // 使用 switchAccount（根据账号类型选择验证方式）
    final success = await widget.ref
        .read(authNotifierProvider.notifier)
        .switchAccount(
          account.id,
          token,
          displayName: account.displayName,
          accountType: account.accountType,
        );

    if (success) {
      // 更新最后使用时间
      widget.ref
          .read(accountManagerNotifierProvider.notifier)
          .updateLastUsed(account.id);
    } else {
      // 切换失败，显示错误提示并停留在当前账号
      if (mounted) {
        final authState = widget.ref.read(authNotifierProvider);
        String errorMessage;

        switch (authState.errorCode) {
          case AuthErrorCode.networkTimeout:
            errorMessage = context.l10n.auth_error_networkTimeout;
            break;
          case AuthErrorCode.networkError:
            errorMessage = context.l10n.auth_error_networkError;
            break;
          case AuthErrorCode.authFailed:
          case AuthErrorCode.tokenInvalid:
            errorMessage = context.l10n.auth_error_authFailed;
            break;
          case AuthErrorCode.credentialsLoginUnavailable:
            errorMessage = context.l10n.auth_error_credentialsLoginUnavailable;
            break;
          case AuthErrorCode.endpointIncompatible:
            errorMessage = context.l10n.auth_error_endpointIncompatible;
            break;
          case AuthErrorCode.serverError:
            errorMessage = context.l10n.auth_error_serverError;
            break;
          default:
            errorMessage = context.l10n.auth_loginFailed;
        }

        AppToast.error(context, errorMessage);
      }
    }
  }

  /// 显示添加账号对话框
  void _showAddAccountDialog(BuildContext context) {
    // 重置 AuthMode 为当前默认登录模式
    widget.ref.read(authModeNotifierProvider.notifier).reset();
    // 立即清除之前的登录错误状态（无延迟）
    widget.ref.read(authNotifierProvider.notifier).clearError(delayMs: 0);

    AdaptivePresenter.showForm<void>(
      context: context,
      title: context.l10n.auth_addAccount,
      dialogWidth: 450,
      builder: (panelContext, scrollController) => ContentSizedAdaptiveForm(
        scrollViewKey: const Key('main-nav-add-account-form'),
        scrollController: scrollController,
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 32),
        content: [
          LoginFormContainer(onLoginSuccess: () => Navigator.pop(panelContext)),
        ],
      ),
    );
  }
}
