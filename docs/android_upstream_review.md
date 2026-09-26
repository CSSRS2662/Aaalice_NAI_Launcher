# Android 分支与上游的分叉清单

本文件记录 `android-custom` 相对上游有意保留的差异，以及每次合并上游时的处理规则。合并前先读此表，合并后更新“最近一次合并”。

## 分支与基线

- 上游：`Aaalice233/Aaalice_NAI_Launcher`，2026-09-15 起由协作者接手维护，仍在持续更新。
- `main` 只跟随 `upstream/main`；全部定制在 `android-custom`。
- 每次合并前创建 `backup/android-custom-before-upstream-YYYYMMDD`，在独立本地分支合并验证后再快进 `android-custom`。
- 本地提交暂不推送 `origin`；需要发布时先确定远端分支，不强制推送。
- 工具链以 `tool/android_build_environment.lock.json` 为准；上游升级 Flutter 时同步更新该文件。

## 有意分叉与合并规则

| 领域 | 本分支做法 | 合并时的规则 |
| --- | --- | --- |
| 包名与品牌 | `com.cssrs2662.aaalicepocket`，名称、图标、启动页为 Aaalice Pocket | 保留本分支；MethodChannel 名称与上游保持一致，开发与验收脚本使用新包名 |
| 应用内更新 | 整套移除（检查、下载、安装、弹窗、横幅） | 上游对更新模块的修改一律丢弃；上游新测试中对更新 provider 的 override 一并删除 |
| 社区入口 | 导航与“更多”面板不显示 GitHub/Discord | `CommunityLinks` 常量保留，上游其他代码仍在引用 |
| 网络 | 共享连接工厂；Android 不使用应用级代理，交给系统/VPN | 保留工厂；上游的请求形态（浏览器请求头、JS 兼容 JSON）叠加在工厂创建的 Dio 上 |
| 设置 | Android 隐藏“网络”“快捷键”分类 | 保留，按能力矩阵判断 |
| 补全 | 中文否定与多关键词扩展；E5 语义补全 | `e5CompletionSourceProvider` 放在 `e5_completion_source.dart`；只在上游的 `autocompleteServicesProvider` 中补一行 `semanticSource` |
| Prompt | 分组编辑、权重滑条、移动端工作台、长按权重工具条 | 保留 |
| 分组持久化 | `PromptGroupRecordStore` 按结果图内容哈希记录分区，不写进 PNG | 与上游固定词记录一致；解析时在 `ImageMetadataService` 挂载，旧版写进 PNG 的 `aaalice_prompt_groups` 仍可读取且优先 |
| 图片菜单 | “保存 → 复用参数/复用种子 → 收藏”开头，无 Krita/Discord 项 | 与上游新增的复制、删除等操作合并，危险操作排在最后；存盘复用上游 `GeneratedImageFileLink` |
| 词库头像 | 圆形头像、应用内图库选图 | 保留 |
| 主题 | 只保留 Pocket 一套主题的浅色与深色，删除 16 套预设及其配色、字体、形状、动效预设；设置改为“浅色 / 深色 / 跟随系统”，新键 `theme_mode` 参与云同步 | 上游对主题预设与模块预设的修改一律丢弃；上游测试引用 `GrungePalette` 等旧配色时改用 `PocketPalette`；`AppTheme.getTheme` 只接收明暗 |
| 移动端生成页 | 工作台结构：图像、提示词、参数、参考、历史页签，全局生成底栏与 V5 体力条；移除参数/历史抽屉、折叠提示词条与上下滑手势 | 上游对 `mobile_generation_*` 的修改按工作台结构重新落位，不恢复抽屉与手势；桌面布局照常合并 |
| 构建 | `scripts/build_android_apk.ps1` 按锁定文件核对工具链 | 保留；CI 中的包名检查使用新包名 |

## 最近一次合并（2026-09-26）

- 上游 `6ba6700f..d1437760`：20 个提交（#295、#316–#329），751 个文件；Flutter 升级到 3.47.5 / Dart 3.13.4。
- 冲突 13 个文件，按上表处理；另修复 3 处不显示为冲突的悬空引用：旧路径 import、已删除的更新 provider、`CommunityLinks.github`。
- 与上游重复的实现：生成图收藏前的存盘逻辑改用上游 `GeneratedImageFileLink.ensureSaved`，删除本分支的 `ensureImageSaved`。
- 设计取舍：提示词分组原先写进 PNG，改为旁路记录库，与上游 #320 的固定词记录方案一致。
- MCP 服务端、DLSSNR 等桌面能力仍由能力矩阵在 Android 隐藏，桌面代码不删除。
- 验证：`flutter analyze` 无错误和警告，仅剩合并前已有的 2 条 `onReorder` 弃用提示；按 Git 改动选出的 661 个测试文件逐批运行。
- 合并后失败的 13 个非环境用例，在合并前的 fork（同一 Flutter 版本）上逐一复现，合并没有引入新失败；其中 11 个已修复（首帧后发布分区快照、删除失去引用的文案、按品牌与菜单更新测试期望）。
- 仍失败：3 个上游用例需要 Windows 符号链接权限，属环境限制；2 个 fork 窄屏用例见下文“已知注意事项”。

## 合并流程

1. 工作区干净，创建备份分支；`git fetch upstream`。
2. 新建本地分支执行 `git merge upstream/main`，按上表解决冲突。
3. 检查上游移动或删除的文件：旧 import 路径、已删除符号不会显示为冲突，但会导致编译失败；上游的分层测试禁止 `lib/core`、`lib/data` 引用 presentation。
4. `flutter pub get --enforce-lockfile`；生成输入变化时运行 `build_runner`，ARB 变化时运行 `flutter gen-l10n`。
5. `flutter analyze`、受影响测试、`scripts/build_android_apk.ps1`，需要时真机验证。
6. 更新本文件，再快进 `android-custom`。不要把旧备份分支整体合并回来。

## 已知注意事项

- 4.1.0 起的云备份新格式不能由旧版读取；多设备同步时先全部更新。
- 提示词分组记录暂未加入云同步：记录很小，但需要新增同步类型与四语文案，列为后续项。
- 分组记录按结果图字节哈希匹配；经重新编码的派生图（放大、增强等）不会继承分组，扁平提示词不受影响。
- 320 宽、3 倍字号下，选中文字后的权重工具条会遮住“标签模式”按钮（`text_mode_enabled_actions_test`），待调整工具条避让。
- 触屏“更多操作”菜单在前部加入保存、复用、收藏后，800×600 测试视口中的水印项超出可视范围（`local_image_card_thumbnail_test`），待确认菜单高度约束。
- 分组编辑器仍使用已弃用的 `ReorderableListView.onReorder`，改为 `onReorderItem` 时需同步调整控制器的索引语义与测试。
