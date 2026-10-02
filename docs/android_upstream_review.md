# Android 分支与上游的分叉清单

本文件记录 `android-custom` 相对上游有意保留的差异，以及每次合并上游时的处理规则。合并前先读此表，合并后更新“最近一次合并”。

## 分支与基线

- 上游：`Aaalice233/Aaalice_NAI_Launcher`，2026-09-15 起由协作者接手维护，仍在持续更新。
- `main` 只跟随 `upstream/main`；全部定制在 `android-custom`。
- 每次合并前创建 `backup/android-custom-before-upstream-YYYYMMDD`，在独立本地分支合并验证后再快进 `android-custom`。
- 自 2026-09-26 起，`android-custom` 以快进方式推送到 fork 的 `main`；每次推送前确认，不强制推送。
- 工具链以 `tool/android_build_environment.lock.json` 为准；上游升级 Flutter 时同步更新该文件。

## 有意分叉与合并规则

| 领域 | 本分支做法 | 合并时的规则 |
| --- | --- | --- |
| 包名与品牌 | `com.cssrs2662.aaalicepocket`，名称、图标、启动页为 Aaalice Pocket | 保留本分支；MethodChannel 名称与上游保持一致，开发与验收脚本使用新包名 |
| 应用内更新 | 整套移除（检查、下载、安装、弹窗、横幅） | 上游对更新模块的修改一律丢弃；上游新测试中对更新 provider 的 override 一并删除 |
| 社区入口 | 导航与“更多”面板不显示 GitHub/Discord | `CommunityLinks` 常量保留，上游其他代码仍在引用 |
| 网络 | 共享连接工厂；Android 不使用应用级代理，交给系统/VPN | 保留工厂；上游的请求形态（浏览器请求头、JS 兼容 JSON）叠加在工厂创建的 Dio 上 |
| 设置 | Android 隐藏“网络”“快捷键”分类 | 保留，按能力矩阵判断 |
| 补全 | 中文否定与多关键词扩展；E5 语义补全（多视图 int8 包：基线文档 + AME 译名/别名/注释，标签取最高分，`E5VectorIndex`）；随包 AME 中文词库 `AmeZhLexicon` 提供中文别名反查并作为翻译的最后一级兜底；非 AI 搜索增强（`lib/core/autocomplete/lexical/`：同音/模糊音、全拼、自然码双拼、首字母、近似中文、中文拆词匹配英文 tag、英文纠错与词形，上下文共现与本机使用习惯排序），数据由 `tool/search_lexicon/` 从固定版本的 MIT 来源生成，本机索引在后台构建 | `e5CompletionSourceProvider` 放在 `e5_completion_source.dart`；只在上游的 `autocompleteServicesProvider` 中补 `semanticSource`、`supplementalSources`、`rankingSignals` 三行；上游修改 `CompletionRanker` 时保留新增匹配方式的优先级（全部在字面匹配之后）与 `boosts` 参数；上游修改 `FastTagService` 时保留 `lexicon` 参数与其在搜索、解析末尾的位置 |
| Prompt | 分组编辑（展开的分区随内容完整展开、内部不滚动，只有分区列表滚动）、权重滑条、移动端工作台、长按权重工具条；移动端“角色 / 固定词 / 质量词”合为 `PromptRoleSegmentGroup`，各按钮新增 `segment` 呈现 | 保留；上游修改这些按钮的桌面外观时照常合并，`segment` 分支保持不变 |
| 分组持久化 | `PromptGroupRecordStore` 按结果图内容哈希记录分区，不写进 PNG | 与上游固定词记录一致；解析时在 `ImageMetadataService` 挂载，旧版写进 PNG 的 `aaalice_prompt_groups` 仍可读取且优先 |
| 图片菜单 | “保存 → 复用参数 → 复用种子 → 收藏”开头（本轮图不含复用参数），无 Krita/Discord 项；本地画廊、智能体图片与在线画廊 AI TAG 图都能直接复用种子（`reuseImageSeed`）；收藏状态按文件共享（`imageFavoriteStatusProvider`，只由 `LocalGalleryNotifier` 写入），成功切换不弹提示 | 与上游新增的复制、删除等操作合并，危险操作排在最后；存盘复用上游 `GeneratedImageFileLink`；上游新增收藏入口时走 `LocalGalleryNotifier.toggleFavorite` 或 `toggleGeneratedImageFavorite` |
| 词库与固定词 | 词库圆形头像、应用内图库选图；词库条目统一为“头像 + 名称 + 更多”卡片（窄格竖排），列表视图并入单列，点按打开使用面板；固定词管理对话框改为只显示名称的 1/2/3 列网格（`fixed_tag_chip.dart`），点按启用、长按/右键打开详情（`fixed_tag_details_sheet.dart`），调整顺序为独立模式；删除对话框内的拖拽连线层与行式条目；列数偏好 `gridColumnsProvider` 只存本机 | 上游修改 `fixed_tags_columns.dart`、`fixed_tag_entry_tile.dart`、`fixed_tags_link_layer.dart` 时按网格结构落位，不恢复行列表与连线；联动在对话框里经详情进入 `showFixedTagLinkManager(showAllCandidates: true)`；侧栏 `fixed_tags_sidebar.dart` 照常合并 |
| 触屏一致性 | 桌面专属入口在触屏补等价路径：在线画廊详情标签长按出菜单（`SimpleTagChip.onMenu`）、Vibe 菜单另列“替换现有 Vibe”、智能体结果图片触屏常驻“更多”；滚轮调权重与生成页布局设置、跟随鼠标、看图左右箭头、拖动改数在触屏隐藏；`ShortcutTooltip` 等在不支持快捷键配置的平台不显示组合键；说明文案按输入方式取 `*Touch` 版本；`usesDesktopGenerationLayout` 让触屏矮屏（手机横屏）保留工作台；查看器手指单击切换工具栏、下滑关闭（`DetailSwipeDismissController`）；文本选择菜单“相关标签”经 `AutocompleteOverlayHandle.showRelated` 触发 | 上游新增右键、悬停或快捷键交互时同步补触屏入口与触屏文案；上游修改 `generation_screen.dart` 的断点判断时保留 `usesDesktopGenerationLayout` |
| 主题 | 只保留 Pocket 一套主题的浅色与深色，删除 16 套预设及其配色、字体、形状、动效预设；设置改为“浅色 / 深色 / 跟随系统”，新键 `theme_mode` 参与云同步；中性纯白 / 炭黑底色，强调色可选预设或自定义（`accent_color`，参与云同步）；输入框底色取画布与分组中更深的一层；`appBarTheme` 固定 surface 色面，内容滚到顶栏下方不变色 | 上游对主题预设与模块预设的修改一律丢弃；上游测试引用 `GrungePalette` 等旧配色时改用 `PocketPalette`；`AppTheme.getTheme` 只接收明暗、字体与强调色 |
| 移动端生成页 | 工作台结构：图像、提示词、参数、参考、历史页签，页签等分不滚动、可左右滑动切换；顶栏只有模型（左）与尺寸（右，`MobileSizeMenu`，只选不改）；全局底栏为额度条（`MobileGenerationStatusStrip`：V5 体力与百分比 + Anlas 余额）与“抽卡 / 加入队列 / 智能体 / 队列 / 生成”；模型只在顶栏菜单切换，`ParameterPanelContent.generation` 不含模型；Variety+ 从 CFG 标题移出，成为带说明的独立分节（`VarietyPlusSection`，桌面面板共用）；页签点按无水波纹；步数、CFG、CFG 重缩放用 `SteppedSlider`（−/+ 与输入）；移除参数/历史抽屉、折叠提示词条与上下滑手势 | 上游对 `mobile_generation_*` 的修改按工作台结构重新落位，不恢复抽屉与手势；桌面布局照常合并 |
| 图库与历史 | 本地画廊、精准参考库、Vibe 库工具栏分标题、搜索、范围三行，“全部 / 收藏”一键切换，低频操作收进“更多”菜单；`GalleryLibraryToolbar` 新增 `titleActions`、`filters` 插槽与 `GalleryLibrarySearchAction`；范围控件集中在 `gallery_scope_controls.dart`；本地画廊、生成历史、精准参考库、Vibe 库及其选择器缩略图改为按宽高比的瀑布流（`LibraryMasonryGrid`，复用在线画廊的 `OnlineGalleryMasonryLayoutSnapshot`）；手机平台（`prefersContinuousLibraryScrolling`）去掉分页条：本地画廊 `loadMore` 追加并按已加载范围重取，Vibe 与精准参考库连续显示全部，均可下拉刷新（`LibraryScrollActions`，在线画廊同样）；长按拖动多选（`CardDragSelect` / `CardDragSelectTarget`） | 上游对 `local_gallery_toolbar.dart`、`gallery_grid.dart`、`history_panel.dart` 的修改按新结构落位；上游修改 `online_gallery_masonry_layout.dart` 时同步检查画廊与历史排版；上游修改 `LocalGalleryNotifier.loadPage` 时保留已加载范围的重取逻辑，桌面分页照常合并 |
| 构建 | `scripts/build_android_apk.ps1` 按锁定文件核对工具链；真机迭代参数 `-TargetPlatform android-arm64 -InstallToDevice -FallbackDirectory`（只编 arm64、校验后直接覆盖安装）；依赖指纹忽略 `version:` 行 | 保留；CI 中的包名检查使用新包名 |

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
