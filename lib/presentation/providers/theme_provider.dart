import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/local_storage_service.dart';
import '../themes/app_theme.dart';

part 'theme_provider.g.dart';

/// 主题明暗偏好 Notifier
@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  @override
  AppThemeMode build() {
    final storage = ref.read(localStorageServiceProvider);
    return AppThemeMode.fromStorage(storage.getThemeMode());
  }

  /// 设置明暗偏好
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final storage = ref.read(localStorageServiceProvider);
    await storage.setThemeMode(mode.name);
  }

  /// 依次切换 跟随系统 → 浅色 → 深色
  Future<void> nextTheme() async {
    const order = AppThemeMode.values;
    await setThemeMode(order[(state.index + 1) % order.length]);
  }
}
