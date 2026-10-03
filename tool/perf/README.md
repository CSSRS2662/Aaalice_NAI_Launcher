# Android 帧率测量

`measure_frames.dart` 通过 `adb` 读取 SurfaceFlinger 记录的 Flutter 画面上屏时间，统计真机帧间隔。它测的是已安装的正式包，不需要 profile 构建，也不会改动应用数据。

## 前提

- 只连接一台 Android 设备，已开启 USB 调试并解锁，应用已打开。
- 安装测量用的包只用 `scripts/build_android_apk.ps1 -InstallToDevice`（`adb install -r` 覆盖安装）。不要对日常使用的设备执行 `flutter run` 或安装 debug/profile 包：它们用调试证书签名，Flutter 会先卸载应用，用户数据随之清空。
- 在仓库根目录运行；结果追加到 `tool/.tmp/perf/results.jsonl`。

## 用法

```powershell
dart run tool/perf/measure_frames.dart tabs before-fix
dart run tool/perf/measure_frames.dart watch 20 generation
```

| 场景 | 操作 |
| --- | --- |
| `tabs` | 生成页“图像 → 提示词 → 参数”来回横滑，4 轮 |
| `history` | 历史页上下快速滑动 |
| `gallery` | 本地图库向下滑动（首次加载缩略图）再向上 |
| `online` | 在线画廊向下滑动 |
| `watch <秒>` | 只录制，期间手动操作，用于键盘、出图、看图等无法脚本化的场景 |

第二个参数是写进结果的标签，用于区分修改前后。点按坐标按 1440×3168 的 OnePlus 12 标定，其他设备需要先核对 `_Device` 中的比例。

## 读数

- `base_hz`：录制期间主要的刷新率。
- `late_pct`：超过 1.5 个刷新周期的帧间隔占比，即“晚帧”。
- `missed_vsyncs`：累计错过的刷新次数。
- `long_frames_ms`：所有 30 ms 及以上的间隔，按发生顺序列出；连续出现的几个值通常就是一次卡顿。
- 间隔超过 60 ms 视为画面静止，不计入统计。

SurfaceFlinger 每个图层只保留最近 128 帧（120 Hz 下约 1 秒），脚本在录制期间每 0.4 秒读取一次再合并，因此长时间录制不会丢帧。

## 已知结论（OnePlus 12，ColorOS，Android 16）

- 系统默认只给应用 60 Hz（静止）和 90 Hz（触摸）。应用通过 `DisplayRefreshRateChannel` 申请最高显示模式，并给 Flutter 画面投 120 Hz 票；设置 → 外观 → 高刷新率可以关闭。
- 软键盘弹出和收起时全应用都有大量晚帧（图库搜索框同样如此），原因是 Flutter 在系统键盘动画期间逐帧重排窗口，不是单个页面的问题。
