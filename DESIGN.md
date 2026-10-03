---
version: alpha
name: Aaalice NAI Launcher
description: Quiet Layered Utility for a local-first, cross-platform NovelAI creative workspace
colors:
  primary: "#EF8558"
  on-primary: "#2A1208"
  primary-container: "#5A2A17"
  on-primary-container: "#FFDBCB"
  secondary: "#A9A9B1"
  on-secondary: "#18181A"
  tertiary: "#8FB5FF"
  on-tertiary: "#0E2250"
  surface: "#18181A"
  surface-container-low: "#202023"
  surface-container: "#28282C"
  surface-container-high: "#2E2E33"
  surface-container-highest: "#36363B"
  on-surface: "#EDEDF0"
  on-surface-variant: "#A9A9B1"
  outline: "#7E7E87"
  error: "#FF8A80"
  error-container: "#5C1A16"
  on-error-container: "#FFDAD6"
typography:
  display-large:
    fontFamily: "Manrope"
    fontSize: "57px"
    fontWeight: 600
    letterSpacing: "-1px"
  headline-small:
    fontFamily: "Manrope"
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "-0.2px"
  title-large:
    fontFamily: "Manrope"
    fontSize: "20px"
    fontWeight: 700
    letterSpacing: "-0.1px"
  title-medium:
    fontFamily: "Manrope"
    fontSize: "16px"
    fontWeight: 700
  body-large:
    fontFamily: "Manrope"
    fontSize: "16px"
    fontWeight: 500
  body-medium:
    fontFamily: "Manrope"
    fontSize: "14px"
    fontWeight: 500
  body-small:
    fontFamily: "Manrope"
    fontSize: "12px"
    fontWeight: 500
  label-large:
    fontFamily: "Manrope"
    fontSize: "14px"
    fontWeight: 700
  label-medium:
    fontFamily: "Manrope"
    fontSize: "12px"
    fontWeight: 600
rounded:
  sm: "10px"
  md: "12px"
  lg: "16px"
  xl: "16px"
  panel: "24px"
  pill: "100px"
spacing:
  xxs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    padding: "12px 20px"
  button-tonal:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    typography: "{typography.label-large}"
    rounded: "{rounded.md}"
    padding: "12px 20px"
  input-default:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.lg}"
    padding: "10px 12px"
  chip-selected:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
  navigation-active:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    height: "48px"
  card-section:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.lg}"
    padding: "16px"
  image-card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.xl}"
---

# Design System: Aaalice NAI Launcher

本文件维护产品视觉与交互契约；[PRODUCT.md](PRODUCT.md) 定义用户与产品边界，[自适应策略](docs/design/adaptive_ui_strategy.md) 定义共享 API 与状态保持，[覆盖清单](docs/design/adaptive_ui_inventory.md) 帮助选择本次验收场景。工程操作与授权规则见 [AGENTS.md](AGENTS.md)，不在设计文档复制工具参数或历史通过结论。

## Overview

**Creative North Star: "Quiet Layered Utility / 静谧层叠工具界面"**

Aaalice NAI Launcher 是高频创作工具，而不是视觉陈列品。Prompt、图像、参数、状态和操作是视觉主体；容器、主题装饰与品牌表达退到背景，只在帮助理解任务时出现。整体气质克制、专业、内容优先，默认状态安静，交互状态清楚而及时。

系统以 Flutter Material 3 为行为基础，以 `ColorScheme`、`TextTheme`、`AppThemeExtension`、`PromptSemanticColors` 和公共组件表达稳定语义。应用只提供一套 Pocket 主题，分浅色与深色两种明暗，设置里可选“浅色 / 深色 / 跟随系统”；两种明暗共享同一语义角色、组件规则与信息架构。frontmatter 记录深色的设计锚点，供阅读与设计参考，不是可直接复制的运行时配置；最终数值以 `ThemeComposer`、`PocketPalette`、`PocketTypography`、`PocketShapes`、`PocketMotion` 和公共组件为准，变更时同步核对。

**Key Characteristics:**

- 内容优先，容器退后；先用排版、留白和低对比色面建立层级。
- 克制、直接、状态清楚；状态变化不改变组件几何尺寸。
- 常用控件和重复交互使用同一套共享组件，统一尺寸、间距、视觉状态、命中区和响应式行为。页面只决定内容与挂载位置，不自行复制外观或改写交互；确有语义差异时提供清晰、有限的变体。组件抽取与状态边界遵循 `AGENTS.md` 的代码组织约定。
- tonal layered 深度：静态内容依赖色面，阴影留给浮层和图像交互。
- 桌面与移动端共享业务组件、状态和命令，但采用各自自然的导航与输入方式。
- 浅色与深色共享同一信息层级、语义色、命中区和交互结果。

**The Content Before Container Rule.** 如果去掉边框后层级仍然清楚，就不要把边框加回来。

## Colors

Pocket 主题以不带色相的中性底色和一个强调色构成克制的工具界面：浅色是纯白画布，分组与控件逐级压暗；深色是中性炭黑画布，容器逐级提亮。强调色由用户在“设置 → 外观 → 强调色”选择，frontmatter 记录的是默认强调色（余烬）的深色一档。组件只通过 Material 3 语义角色取色，不得直接写死某一种明暗或某一种强调色下的颜色。

### Primary

- **强调色（`primary`）**：主操作、当前选择、焦点和关键进度；使用必须稀少，避免与内容竞争。由 `PocketAccent` 提供浅色与深色两档：预设为余烬橙、晴空蓝、靛青、紫罗兰、玫瑰红、青碧、森林绿与石墨，浅色一档配白字时对比度不低于 4.5:1；自定义颜色在浅色画布上至少 3:1、在深色画布上至少 4.5:1，不足时沿明度自动校正，主色上的前景在黑白中取对比度更高者。
- **强调色容器（`primary-container`）**：选中项、低强调主色背景和需要持续可见的状态，由强调色的色调阶梯生成，保证与其前景的对比度。
- 强调色只改变 primary 系角色；画布、分组、控件、浮层与 secondary、tertiary、error 不随它变化。

### Secondary

- **中性灰（`secondary`）**：中性的次级强调，不承担品牌表达；错误语义必须通过 `error` 角色表达。

### Tertiary

- **雾蓝（`tertiary`）**：次级分类和辅助强调（例如标签模式），不承担主操作。

### Neutral

- **纯白 / 炭黑画布（`surface`）**：页面与工作区底色；浅色固定为 `#FFFFFF`。
- **正文（`on-surface`）**：主文本与默认图标。
- **元数据（`on-surface-variant`）**：说明、路径、统计与次级图标。
- **边界（`outline`）**：必要的结构线、输入轮廓和精确边界，不作为普通容器装饰。

Material 表面按职责使用：Canvas=`surface`，Section=`surfaceContainerLow`，Control=`surfaceContainer` / `surfaceContainerHighest`，Overlay=`surfaceContainerHigh`。浅色下 Section、Control、Highest 依次压暗于纯白画布，Overlay 保持近白并依靠阴影浮起；深色下容器逐级提亮。输入框压暗于画布与 Section 中更深的一层。中性色面不带色相（三通道差不超过 16/255）。同一页面最多出现三个明显表面层级。

### 跨端中性色面规范

- 每个主题交给 `ThemeData` 前必须具有完整的 `surfaceContainerLowest`、`surfaceContainerLow`、`surfaceContainer`、`surfaceContainerHigh`、`surfaceContainerHighest` 色阶；这些角色必须与 Canvas 保持可辨色差，并按层级单调变化。
- 旧主题缺失容器角色或把它们全部映射为 `surface` 时，由 `ThemeComposer` 统一通过 `resolveLayeredSurfaceColors` 补全。补全只能从 `surface` 做中性的明度变化，禁止混入 `onSurface`、`primary`、`secondary`、`tertiary` 或 `error`；前景色和强调色即使偏暖、偏红，也不得污染普通分组卡片。
- Android、Windows 与 macOS 必须消费同一套已经解析的语义色。禁止按平台单独指定普通卡片颜色，也禁止依赖 Android Material 默认值形成第二套色面；平台只改变布局和输入方式，不改变 Canvas、Section、Control、Overlay 的颜色关系。
- 页面和公共组件按职责使用 `sectionSurfaceColor`、`controlSurfaceColor`、`overlaySurfaceColor`，不得在组件内部自行用前景色透明叠加生成中性背景；普通 `Card` 必须继承全局 `CardTheme` 的 `surfaceContainerLow`。
- 图片承载区域统一使用 `ImageViewportSurface.background`（`#141414`），深浅主题与各平台一致；源图、结果、对比、查看器、悬浮预览和缩略图不再借用普通面板色。其上提示使用亮色前景；工具栏和参数表单仍跟随主题。透明棋盘格、用户指定透明底色和编辑器导出画布色保留原有语义，绘制在承载底色上方。
- 图片查看器在鼠标下常驻工具栏与缩略图条；手指单击图片切换二者显隐，未放大时单指下滑图片跟手、背景淡出露出下层页面，超过阈值或快速下滑即关闭，否则回弹。双指缩放、放大后的拖动与鼠标拖动都不触发关闭。
- 主题回归测试必须基于最终 `ThemeData`，至少断言容器色与 `surface` 不相等、各层级可区分、中性源色不会产生红绿蓝通道偏色，并确认切换 Android/桌面 `TargetPlatform` 不改变语义色值。

**The Cross-platform Surface Rule.** 中性卡片色只能来自统一解析后的 Material 3 容器色阶；任何平台默认值、前景色混合或页面专属补丁都不能成为第二颜色来源。

**The Semantic Color Rule.** 页面只使用 `ColorScheme` 与具名业务语义；禁止散落固定颜色或把 `secondary` 当作错误色。

**The Quiet Accent Rule.** `primary` 只标记主操作、选择、焦点与关键进度，不能让所有按钮和标签同时高亮。

## Typography

主题使用 Manrope：标题靠字重和略收的字距建立层级，正文与标签不额外加字距；中文字形回退到系统字体。用户字体设置可以替换字体族，但必须保留 Material 文字角色、字号层级和可读性。中文正文不额外增加 letter spacing。

- **Display / Headline**：用于少量大标题和页面标题；Operate 界面通常从 `headlineSmall` 或更低层级开始，避免宣传页式巨型标题。
- **Title**：`titleLarge` 用于页面或主面板标题，`titleMedium` / `titleSmall` 用于分组和条目标题。
- **Body**：`bodyLarge` 用于重要说明，`bodyMedium` 是常规正文与表单内容，`bodySmall` 用于辅助信息。
- **Label**：按钮、chip、导航和紧凑元数据使用 label 层级；路径、模型、种子和成列数字应保持易扫描，并使用 tabular figures（适用时）。

一个局部区域最多使用三个明显字号层级。Placeholder 不能替代永久标签；文本缩放和中、英、日、繁体中文长度变化不得裁切关键内容。

标题只负责命名当前层级，层级顺序固定为页面或弹窗标题 → 分组标题 → 控件标签。相邻父子标题若表达同一件事，必须合并为一个；不得用“选择要保存的内容 / 选择备份内容”这类近义标题连续占两层。副标题只有在补充用户作决定所需的结果、约束或风险时才出现，不得复述标题、解释显而易见的控件，也不得给同组每一项机械添加副标题；可统一说明的信息上移到分组说明，计数与状态优先作为紧凑元数据呈现。

**The Working Type Rule.** 排版服务于扫描和操作：标题靠字号、字重与留白建立层级，不靠描边、全大写或高饱和颜色。

## Layout

布局采用 4px 基础网格，稳定间距为 4、8、12、16、24、32px。同组元素间距必须小于组间距；桌面页面水平边距通常为 20–24px，紧凑屏幕为 12–16px。表单和设置内容通常限制在 840–960px，画廊、画布与生成工作区按任务需要扩展。

### Adaptive structure

- **Compact `<600px`**：移动 Shell，单列主流程、Material `NavigationBar`、bottom sheet 或独立次级页面。
- **Medium `600–839px`**：内容可采用紧凑双区；能在四周保留明显遮罩空间的短时模态任务使用居中 Dialog，不得仅因窗口未达 Expanded 就拉伸为大面积 bottom sheet。
- **Expanded `≥840px`**：宽屏 Shell、稳定侧栏与可并行主辅面板。
- **Wide `≥1180px`**：可增加辅助列或更宽工作区，但不盲目拉宽表单。

桌面 Navigation Rail 折叠宽 60px、展开宽 196px；导航项高 48px。宽度动效只改变导航自身的裁切视口，路由工作区只能接收动画起点与终点约束，不得把每一帧的中间宽度传入页面级 `LayoutBuilder`。触屏平台核心命中区优先 48×48 logical pixels，最低不小于 44×44；桌面常规点击目标通常不小于 40×40。方向、窗口尺寸、软键盘与导航容器变化后必须保留输入、选择、滚动位置和任务状态。

在线画廊在可承载工具栏的桌面/平板宽度维持固定职责分行：第一行只放全局控件，第二行只放来源专属筛选与操作。第一行采用左侧站点/模式/分级、中间弹性搜索、右侧全局操作的三段式结构；宽度不足时整行横向滚动，不把全局控件挪到第二行。顶栏使用与 collection workspace 相同的整条 Section 色面，底部分页或随机状态使用独立 Control 色面与 8px 外间距；两者均不使用贯穿式分隔线。设置与统计等工具页面沿用同一顶栏色面规则；设置分类导航作为带 8px 外间距的独立 Section 区域，不用纵向分隔线连接成表格。回归覆盖 700、840、1180、1600px，QuickTagCloud 单独覆盖。

### Collection workspace shell

本地画廊、Vibe 库、精准参考库与词库共用同一种 collection workspace 骨架。本地画廊工具栏按职责分行：标题行放名称、数量、多选与“更多”菜单；搜索行放搜索框与高级筛选（有模型、采样等条件时换成强调色面并加圆点）；范围行放“全部 / 收藏”两段切换（一键只看收藏）与日期、分类两个条件，设置后显示当前取值并附独立清除。宽屏把范围控件排在搜索框右侧，保持单行。刷新、撤销重做、按日期分组、跳转日期、打开文件夹与清除全部筛选收进“更多”菜单，不再排成可横向滚动的按钮带。精准参考库与 Vibe 库沿用同一结构：标题行放多选与“更多”（导出、打开文件夹、刷新、宽屏分类栏开关、清除筛选），搜索框旁放与其同高、带文字的“导入”，范围行放“全部 / 收藏”、类型或分类条件与排序条件；精准参考与 Vibe 选择器同样用“全部 / 收藏”与下拉条件，词库选图用“全部 / 收藏”。以上控件由 `gallery_scope_controls.dart` 统一提供，整条切换与条件同高（触屏 48px）。本地画廊、生成历史、精准参考库、Vibe 库及各选择器的缩略图都使用按原始宽高比的瀑布流（`LibraryMasonryGrid`），图片完整显示、放进当前最短的一列：手机竖屏为两列，更宽时按可用宽度增加列数；宽高比优先取元数据尺寸，其余图片只读取文件头，Vibe 组合包保持 4:5 层叠造型。工具栏始终是横跨整个工作区的一体化 Section 色面，页面名称固定在工具栏左端；页面标识组按内容取得自然宽度，与后续工具组使用 12px 间距，不得用固定宽度占位制造空白。Expanded/Wide 下的持久分类树位于工具栏下方的独立强 tonal 区域，分页也作为主内容底部的独立强 tonal 区域。手机平台（`prefersContinuousLibraryScrolling`）不显示分页条：本地画廊滚动接近底部时追加下一页，删除或刷新时按已加载范围整体重取；Vibe 库与精准参考库直接连续显示全部筛选结果；以上页面与在线画廊都可从顶部下拉刷新。三者通过背景色、圆角和 8px 间隔建立层级，不使用贯穿式边线把页面切成表格；色面必须通过 `sectionSurfaceColor` / `controlSurfaceColor` 解析，不能直接读取可能与 Canvas 重合的容器色 token。常规单行工具栏的最小高度统一为 72px，以容纳触屏 48px 命中区；侧栏默认宽度为 250px，持久侧栏通过共享拖动手柄调宽；各页面独立记住本机宽度，不参与云同步。拖动期间只更新布局，结束时持久化，窗口收窄不得覆盖已保存的偏好宽度。新增同类页面必须复用 `GalleryCollectionWorkspace`、`GalleryCollectionToolbarSurface` 与 `GallerySidebarSurface`，不得在各页面复制壳层结构和尺寸。

Compact/Medium 下没有持久侧栏时，页面名称保留在主工具栏，分类导航由 adaptive panel 承载并使用面板自身标题。窄屏换行、长本地化文案或放大文字可以让工具栏向下扩展，但不得裁切、缩放或隐藏操作；恢复为可容纳单行的宽度后应回到 72px 的共同基线。

### Generation workspace identity

画布是高密度创作工作区，不套用 collection workspace 的整条页面工具栏。Expanded/Wide 下，页面身份固定在展开的生成控制栏顶部，以无副标题的紧凑 Section 色面显示“画布”及画笔图标，并与侧栏折叠操作同排；经典布局与官网式布局必须复用 `GenerationWorkspaceHeader`。侧栏收起时只保留参数展开入口，不重复页面标题。

Compact/Medium 使用生成工作台：顶栏左侧是相邻的模型与尺寸两枚胶囊，右端是额度读数（闪电 + V5 体力百分比 | Anlas 图标 + 余额；Anlas 图标统一用 NovelAI 标志 `AnlasIcon`），读数没有独立色面，直接放在顶栏底色上，末尾数字与左侧胶囊同为 12 dp 边距，点按展开菜单直接切换（移动端只在这里切换模型，参数页不再重复提供；尺寸菜单只按分组列出官方预设与参数页保存的自定义尺寸，输入、保存和删除仍在参数页），放得下时全部完整显示；放不下时先去掉两枚菜单的箭头，仍放不下则整行横向滚动，不省略文字。顶栏胶囊与其下的页签轨道同为 44 dp，二者文字最多放大到 1.6 倍。内容滚到顶栏下方时顶栏保持 surface 色面，不切换容器色；其下是“图像 → 提示词 → 参数 → 参考 → 历史”页签，历史固定在最右侧。页签等分整行宽度、任何宽度下都不横向滚动：文字最多放大到 1.6 倍，仍放不下时在各自分段内等比缩小。页签之间可以左右滑动切换，相邻面板跟手移动，选中底同步连续移动，快速轻扫即可翻页，首尾页回弹；手指落在未聚焦的提示词文本上同样可以横滑，滑块、横向列表与拖动排序等内部控件优先。点按页签只以选中底的滑动回应，不叠加水波纹；新旧两个面板直接滑动衔接，不经过中间页签；Reduce Motion 下直接到终态。底栏固定在底部、所有页签共用，只有一行：抽卡开关、加入队列、智能体、队列与生成按钮，生成按钮占剩余宽度；点按生成后切到图像页直接呈现流式预览，进度填充在生成按钮内部。生成结束时若不在图像页，图像页签显示新结果标记。体力在主界面只显示闪电图标与剩余百分比（不画轨道、不显示张数，低于 10% 或耗尽时用错误色），命中区不小于 44，点按打开详情（剩余量、估算张数、回充时间、规则与本次消耗）；只在 Opus 订阅、订阅响应带有额度数据且当前模型受限（V5）时出现。软键盘弹出时收起页签栏与生成底栏并停用横滑，把高度留给正在编辑的内容；开关横滑不得重建面板。宽横屏时图像常驻左侧，右侧只保留编辑类页签。可用高度不足 600 的触屏窗格（如手机横屏）即使宽度达到 Expanded 也保留工作台，不切换桌面工作区。页签状态跨断点保留；提示词编辑器始终挂载，其他面板首次进入时构建后常驻。

经典布局的角色编辑位于左侧生成控制栏，顺序固定在种子之后、反推与图生图等辅助输入面板之前，作为独立的可折叠一级工作区呈现；中央工作区只承载主提示词、图像预览和生成操作。官网式布局在提示词侧栏呈现同一角色模块，两种布局必须共享模型可用性、角色数据、折叠状态、摘要、添加命令和纵向编辑结构。移动端继续使用独立角色管理界面，不把桌面侧栏结构塞入参数面板。支持角色的模型即使尚无角色，也必须保留首个角色的显式添加入口，不能因空列表隐藏整个模块。

**The Capability Parity Rule.** 桌面 hover、右键与快捷键必须有移动端单击、长按、菜单或系统入口的等价路径；低频操作可以折叠，但不能静默消失。只能靠修饰键触发的变体（如 Shift+点击替换）在菜单里另列一项，快捷键专属的功能放进对应菜单（如文本选择菜单里的“相关标签”对应 Ctrl+Shift+Space）。提示与说明文案按输入方式区分：右键、悬停、滚轮只对精确指针说，Ctrl/Shift/方向键只在支持快捷键配置的平台说，触屏版改写为长按或点按；只对鼠标有意义的设置项与控件（滚轮调权重、跟随鼠标、拖动改数、看图左右箭头、按钮提示里的快捷键）在触屏上不出现。

**The Local Constraint Rule.** 响应式判断使用局部 `LayoutBuilder.constraints` 与 capabilities；禁止按设备型号、`FittedBox` 缩小交互工具栏或在共享页面散落平台判断。

## Elevation & Depth

系统采用 **tonal layered** 深度。Canvas、Section、Control 和 Overlay 主要通过表面色与留白区分；普通 Card、静态内容、输入和按钮在静止状态不使用投影。菜单和 tooltip 使用一级环境阴影，对话框与 bottom sheet 使用二级结构阴影；图像卡片拥有独立的内容交互阴影。

智能体对话的 Composer 是持续可操作的浮起输入区，使用 `controlSurfaceColor` 与聊天 Canvas 建立稳定色阶；不得复用可能向 Canvas 变暗并与背景合并的普通输入填充色。其内部编辑器保持无独立填充和无描边，由同一个 Composer 色面承载输入与操作。附件、权限、展开、模型和上下文等次级控件静止时透明，只用 hover、focus 与 pressed 反馈交互；仅启用的状态开关和可执行的发送主操作保留填充色。

### Shadow Vocabulary

- **Flat Rest**：普通 Card 与按钮 elevation 0，shadow transparent。
- **Overlay Menu**：Flutter elevation 8，black 15%；仅用于 popup menu 与 menu。
- **Dialog Layer**：Flutter elevation 16，black 20%；用于 dialog 与 bottom sheet。
- **Tooltip Ambient**：blur 8px、offset `(0, 4)`、black 15%。
- **Image Rest / Hover**：常态 blur 6px、offset `(0, 2)`、black 8%；hover blur 14px、offset `(0, 6)`、black 16%。

静态 surface 不叠加“渐变 + 描边 + 发光 + 阴影”。玻璃只用于确有背景穿透价值的浮层或主题表达，并避开文字、输入和图像细节。

**The Flat-at-Rest Rule.** 阴影不是默认装饰；只有浮层、状态反馈或图像内容需要与背景分离时才出现。

## Shapes

主题使用克制的圆角层级：控件与 chip 为 10px，按钮与输入为 12px，分组卡片与图像卡片为 16px。Adaptive bottom sheet 使用 24px 顶部圆角，居中 Dialog 使用四周 24px 圆角；这些值属于大型浮层，不应下放到普通卡片。常驻 side panel 不是模态浮层，沿用所属工作区的 Section 形状。

业务组件声明 `control`、`card`、`dialog`、`menu`、`panel`、`circle` 或 `pill` 等语义角色，实际值由当前 shape preset 和 `AppThemeExtension` 提供。父子圆角通常递减；内层只有 chip、状态标记或圆形控件可以更圆。

默认组件不使用全胶囊和全大圆角；小型状态徽标与计数可以使用胶囊形。

**The Semantic Shape Rule.** 页面选择形状角色，不复制圆角数字；硬编码只允许稳定的签名组件尺寸，并应逐步归并到主题或公共组件。

## Components

组件哲学是**克制、直接、状态清楚**。优先复用 Material 3 行为和 `lib/presentation/widgets/common/`，组件 API 表达 `selected`、`danger`、`emphasis` 等语义，而不是暴露任意颜色。

### Buttons

- **Shape / padding**：默认按钮 6px；Filled 与 tonal action 为水平 20px、垂直 12px，TextButton 为水平 16px、垂直 10px。
- **Hierarchy**：`FilledButton` → tonal action → `TextButton` → `IconButton`；`OutlinedButton` 兼容入口表现为无 side 的 tonal action。
- **Icon actions**：普通纯图标按钮静止时背景透明，不使用 filled / filledTonal 或容器底色作为默认底座；hover 时高亮，键盘 focus 与触屏 pressed 保留等价反馈。图片上的覆盖操作沿用下文专用覆盖色规范。
- **Toggles**：开关、模式与页签按钮仅在激活或选中时保留背景；未激活时透明并使用中性前景，交互时显示临时反馈。此规则同时适用于自绘按钮和带文字的开关，不改变命中区、布局或操作语义。
- **States**：loading 使用 16px spinner 并保持内容结构和按钮尺寸；危险操作在最终确认阶段使用 error 语义。
- **Access**：仅图标按钮必须提供 tooltip 与语义标签；桌面保留焦点和快捷键，移动端提供足够命中区与即时按压反馈。
- **Prompt roles**：正面沿用主题 primary、负面沿用 error，固定词使用清晰蓝色，质量词保留来源语义色，统一由 `PromptSemanticColors` 提供。未启用入口背景透明并使用中性图标，仅启用状态显示少量功能色与轻微底色，避免整排彩色块。五个入口复用 `PromptControlButton`；圆角和动效读取主题 token，文字与图标对实际底色保持至少 4.5:1 对比度，页签通过字重、选中色面与 selected 语义表达当前状态。
- **Prompt role group**：移动端提示词页的“角色 / 固定词 / 质量词（负面时为负面预设）”合成一个 `PromptRoleSegmentGroup`：共用一块 Control 色面，分段之间只用短分隔线；每段只有图标与等宽数字（开关类只有图标），启用时图标取强调色，不再给每个入口单独铺色块或叠计数胶囊。各入口的点按、长按与菜单行为不变。

### Inputs / Fields

- **Style**：填充统一使用 `inputSurfaceFillColor`，从 Canvas 中性压暗形成凹入层级，不能从较亮的容器层混色；默认暗色主题约为 `#131313`（普通）/`#151515`（prominent），亮色主题仅轻微压暗。默认 8px 圆角；单行公共输入通常使用水平 12px、垂直 10px padding，多行使用 12px。
- **Outline**：允许固定几何的低对比 1px 轮廓；默认态尽量接近透明，focus 使用主色增强，error 使用错误色增强。所有状态占用相同内部空间，不改变外部尺寸。
- **Hierarchy**：大面积 Prompt 编辑器优先保障正文面积，工具操作放在框外 footer；只读内容无需编辑能力时直接使用文本。
- **Behavior**：prefix/suffix 保持次级权重；软键盘打开后当前字段必须可见。
- **Prompt 触屏长按**：当词条选区已由权重工具条接管时，不得同时弹出另一套文本选择菜单；复制与启用/禁用并入同一权重工具条，工具条固定优先置于选区上方并避让 SafeArea 与软键盘。没有权重工具条的普通文本选区，以及鼠标右键选择，继续使用原生文本菜单。
- **Prompt 分组编辑**：单框与分组模式共享同一个最终正面/负面提示词值；分区不预设分类或标题，只负责保存用户自定内容、启用状态、折叠状态与顺序。发送前按视觉顺序拼接所有启用且非空的分区，固定词、质量词和角色等既有请求准备逻辑保持独立且不重复注入。分区编辑器必须复用统一 Prompt 输入、补全、权重和 Tag 模式能力；切换模式及重启应用不得丢失分区结构。复用参数时导入的提示词会被重新拼接（去掉固定词与质量词、统一以“, ”连接），因此按标签（忽略大小写、空白、连接方式与禁用片段）与分区记录比对，一致即恢复分区，并把生成提示词改回分区拼接结果。
- **移动端 Prompt 工作台**：控制区只有一行 44 dp 纯图标控件：正/负面切换（图标 + 数量 + 切换标记，名称只在提示与读屏中）→ 新增分区（仅分组模式）→ 弹性留白 → 角色/固定词/质量词等宽三段工具组 → 单框/分组切换（固定在最右侧）；三段工具组使用一致的数字徽标、尺寸、间距与命中区，仅以语义色和图标区分职责。大字号放不下时整行横向滚动，不分行、不省略。透明背景不在提示词页：触屏在图像页信息条右端与参数页“生成”分组提供同一开关（前端为透明图标，其后为名称与开关；窄时先去开关、再去名称，启用态始终以强调色底表示）。分区标题栏固定按“启用 → 拖动 → 摘要 → AI → 更多 → 折叠”排列；摘要完整显示首个非空词条，并以 `+N` 表示其余词条，不截断半个词条。AI 入口不得覆盖文本输入区；展开的分区随内容完整展开、内部不再滚动，纵向拖动始终滚动整个分区列表，分区只通过标题栏右侧的折叠按钮收起或展开；底部生成状态与主操作保持稳定。
- **补全匹配说明**：拼音、双拼、首字母、同音、近音、近似、拆词、纠错、词形、语义等非字面匹配，在候选次要信息前显示小号标签（`tertiary` 文字、14% 同色底），纠正后的词或拆出的词放在 tooltip；字面匹配不显示标签。增强结果永远排在全部字面结果之后，上下文与使用习惯只在同一匹配方式内重排。用户可在“搜索增强”设置中关闭标签与各项增强。

### Sliders

- 滑条可以使用 `divisions` 保留离散取值、键盘步进和语义行为，但所有主题与局部 `SliderTheme` 均隐藏轨道间隔点，只显示轨道、进度和滑块。
- 生成参数中的步数、CFG 与 CFG 重缩放使用 `SteppedSlider`：两侧 −/+ 每次精确走一步、按住连续调整并逐渐加速，末尾数值框可直接输入，按步长对齐并限制在范围内；标题只写名称，数值以输入框为准。
- 提示词权重统一使用占满浮层可用宽度的离散滑条，范围为 -3.00～3.00、步进为 0.05，并持续显示两位小数；滑块使用主题主色圆形拇指，两端微调按钮与重置、复制、启用/禁用等动作保持独立层级，不能让数值输入框唤起软键盘或在右侧留下无用途空区。

### Chips

- **Style**：默认无 side，普通背景使用 `surfaceContainerHighest`，selected 使用 `primaryContainer`；短标签采用 4px 圆角与 8×4px padding。
- **State**：互斥模式优先 segmented control 或 tab；chip 只表示短标签、状态或可移除条件。
- **分段选项方向**：同一组模式保持横向排列；不要因弹窗局部宽度落入页面级 Compact 断点或文字放大而切成竖排。需要兼容窄屏的分段选项复用 `HorizontalSegmentedControl`，空间不足时横向滚动并保留完整标签与选择状态。
- **Touch parity**：删除按钮桌面可紧凑，触屏命中区保持 48×48px。
- **固定词网格**：固定词管理只显示名称，排成用户可切换的 1/2/3 列网格；手机严格按所选列数，更宽的面板保持同一密度增加列数，大字号时自动减列。列数按页面记在本机，不参与云同步。点按即启用或停用，启用态使用正/负向语义色面并带勾选标记；有联动的条目附联动标记，提醒点按会同时切换联动项。内容、插入位置、联动、复制、编辑与删除都放在详情里，触屏长按、鼠标右键打开；这是用户明确要求的“只保留选择”设计，因此网格末尾常驻一行操作提示，读屏通过长按动作进入。调整顺序是菜单进入的独立模式，拖动右侧手柄，始终覆盖该类全部条目，不受搜索和“只看启用”影响。

### Cards / Containers

- **Static Card**：`surfaceContainerLow`、无边框、无阴影；内部 padding 使用 16px 或 24px。
- **Interactive Card**：hover 可提高色面对比或轻移 2px；focus 使用不改变布局的 1px primary 状态线。
- **Grouping**：相关内容使用有明确色差的无边框 Card / Section 色面分组；归属、折叠与内外层级遵守下节规则。分隔线只用于无法通过分组与间距表达的同级连续记录，不能与分组卡片重复表达边界。

### 参数面板与菜单分组

- **先定归属，再摆控件**：参数面板、设置页、筛选弹窗和选项菜单先按用户任务划分少量、互斥且能一句话命名的组，每个字段与操作都有明确归属。层级固定为表面标题 → 分组标题 → 控件标签；组标题与该组全部内容必须位于同一视觉容器内，不能只把标题加粗后将各组参数平铺在背景上。
- **默认使用完整分组卡片**：多组参数表单采用静谧分组布局，复用 `SettingsCard` 等既有 Section 组件。标题、轻量图标、选项、说明及错误反馈一起被无边框色面包住；父表面使用 Canvas，分组使用 `sectionSurfaceColor`，控件使用对应 Control / Input 语义，必须有可辨的明度层级。不能让父容器与分组使用同一色面后再补描边掩盖层级缺失。
- **连续任务保持完整**：同一编辑任务的预设、基础参数与高级参数属于一张完整分组卡片，内部用小节标题、对齐与留白区分职责；运行环境、账号、维护等独立任务仍使用独立分组卡片。不得将连续参数拆成宽度不一、高度悬殊、散落留白的积木式卡片拼图，也不得为消除碎片感取消所有分组色面。同页分组沿统一内容宽度纵向排列，双列只用于卡片内部能稳定对齐的参数。
- **归属跨展开状态保持一致**：“高级参数”等折叠组收起时保留明确标题，可以是独立完整分组，也可以处于所属参数卡片内；展开后的全部子项必须仍由同一所属色面包住，收起时子项整体隐藏。不得只展开一段无容器的控件列表，也不得把子项溢出到组外。展开、折叠、调整宽度与文本缩放不得清空输入、选择、校验状态或帮助内容。
- **子组不再套卡片**：高级参数可用简短小节标题、对齐与留白划分内部职责；不以横线替代分组，不为每个字段单独铺卡片，不使用卡片套卡片。共享编辑器应明确由自身还是调用方提供分组色面；嵌入已有参数卡片时复用内部小节，避免重复外框与同义标题，保留一套分组事实来源。
- **密度服务于扫描**：卡片内边距通常 16px，组间 16–24px，组内相邻内容 4–8px；组间距必须大于组内距。标签、帮助入口与数值列稳定对齐，说明按需展开；宽度与文本缩放允许时可双列，否则完整回到单列，不缩小字和命中区、不删减字段，也不增加同轴嵌套滚动。
- **自定义尺寸预设**：生成参数的自定义宽高在常规宽度下与交换、保存/删除动作保持单行，数字输入只占完成任务所需宽度；保存后的尺寸进入下拉框“自定义”分组，当前尺寸已保存时原位切换为删除。窄屏或大字号无法安全容纳时，动作移到输入行下方右对齐，不缩小文字或触屏命中区。
- **短菜单按职责分段**：单一职责的短操作菜单可保持平面列表；包含多种职责时，用有名分组和组间留白组织选项，并在触屏等价入口中保持同一分组、顺序与危险操作边界。无需给菜单内每一组再套多层卡片，但不能让组标题看起来属于上一组，或把全局操作混入某个局部分组。
- **验收以归属可见为准**：至少检查折叠与展开、帮助与错误、长文案、禁用，以及 320/600/840/1180/1600 宽度和 3x 文本。测试应断言字段在对应组的子树与可见边界内、不同组不混杂、全部操作可达，且调整布局后保持编辑状态；截图检查必须能直接辨认“这个选项属于哪一组”，不能只以无 overflow 作为通过标准。

### Hover previews

- 悬浮预览属于 Overlay 层，统一使用 `overlaySurfaceColor`，必须与所在页面 Canvas 和源卡片保持可辨色差；不得直接使用可能与背景相同的 `surface` 或未校验的容器 token。
- 预览依靠色面、圆角与环境阴影从工作区浮起，默认不加完整描边；图片留白和元数据区域必须继承同一 Overlay 色面，不能出现与页面背景连成一片的大块空区。
- 在线画廊、本地图库、Vibe 与精准参考等图像资源统一复用 `ImageHoverPreviewSurface` 和 `ImageHoverPreviewController`；页面只提供媒体、角标与业务底栏，不得复制 Overlay 定位、圆角、阴影或图片尺寸算法。
- 图片区域以原始宽高比计算理想高度，并在最小展示高度与视口剩余高度之间动态收敛。达到高度边界后使用 `BoxFit.cover` 裁剪：超高图优先保留顶部主体，超宽图居中；禁止为了展示完整图片在两侧或上下制造 letterbox 留白。
- 悬浮预览优先出现在源卡片右侧，空间不足时切换左侧，两侧都不足时选择空间更大的一侧并夹紧；纵向按页面需要居中或顶对齐，同时避开 SafeArea、IME 与窗口边缘。窗口尺寸变化、源卡片滚出视口或失去链接时必须重新布局或隐藏。
- 底栏可按业务自定义信息，但标题、图标化指标、标签摘要、加载与错误状态必须复用公共原语和语义色；不得退化为无图标的连续文本，也不得传入页面专属装饰色破坏统一层级。

### Navigation

- 桌面使用稳定 rail，active 项采用淡主色背景与主色前景；移动端使用五入口 NavigationBar，并通过“更多”保留次级能力。
- Hover 只增强桌面反馈，不承载唯一信息。键盘可见或 shell overlay 激活时，移动底部导航可暂时隐藏以保护工作区。

### Dialogs and adaptive panels

- Dialog 用于需要完成、取消或确认后才能返回的短时模态流程，例如设置表单、内容选择与风险决策；标题直接说明任务，风险流程的正文先说结果，再说原因。
- Dialog / adaptive panel 标题区使用无边框 Section 色面与正文建立层级，禁止用横向分隔线切开标题和内容。
- 操作顺序保持低强调取消在前、主操作在后；Esc 与系统返回可关闭并恢复合理焦点。
- 表单使用 `AdaptivePresenter.showForm`：Medium / Expanded / Wide 为位于视口中央、宽高受限的独立模态 Dialog；标题与操作区按内容需要固定，正文独立滚动，四周保留可见遮罩空间，不得贴靠窗口侧边呈现。
- `showForm` 在 Compact 使用避开 SafeArea 与软键盘的 bottom sheet；`showPanel` / `showPicker` 在 Compact / Medium 使用 sheet，在 Expanded / Wide 居中。短确认可使用有界 Dialog。容器差异保持字段语义、状态和操作结果一致，不能将模态任务改为常驻侧栏。
- Dialog 与 bottom sheet 默认按实际内容取自然高度，只设置视口内的最大高度；只有长清单、长表单、可拖拽展开面板或明确需要稳定工作区的内容才占满上限。禁止用固定高度、默认最大高度或紧约束的 `Expanded` 人为撑高短内容弹窗。
- `AdaptivePresenter.showForm` 的短表单、操作菜单与说明正文统一复用 `ContentSizedAdaptiveForm`，由其管理收缩、最大高度内滚动和可选固定 footer；仅设置 `maxHeight` 或 `FlexFit.loose` 不能阻止默认 `ListView` 占满视口。动作需要随正文滚动时放入 `content`；长集合保持惰性视口，不为收缩而全量测量。高度回归必须同时断言短内容无大块留白、长内容可滚动，并覆盖内容增减、窗口缩放和 IME 后的恢复。
- Side panel 只承载常驻、非模态的工作区辅助内容；设置表单、内容选择、确认和其他需要用户完成或取消的流程不得使用 side sheet。
- 页面或弹窗在同一纵向轴上只能有一个主滚动容器。禁止在外层 `ListView` / `SingleChildScrollView` 中再放固定高度、可独立滚动的 `ListView`；少量子项直接随主容器滚动，长列表、搜索结果或选择器必须进入独立 Dialog / adaptive panel，并由该表面独占滚动控制器。横向工具栏滚动不受此限制，但不得劫持纵向滚轮。
- 长表单与选择清单遵守“参数面板与菜单分组”，并在 Dialog、sheet 和设置页复用同一参数编辑器；容器变化不能改变选项归属。
- 回归测试必须确认主表面内不存在第二个同轴滚动列表，并覆盖从主清单打开独立选择器、保存后回写状态、取消不改动，以及 320、600、840、1180、1600px 和 3 倍文字下的操作可达性与无 overflow。

### Image Cards

- **适用范围**：本地与在线画廊、生成结果、Vibe、精准参考及其他以图片为主体的资源卡片统一遵守本节；业务动作可以不同，但布局、视觉和交互状态不得各自发明。
- **卡片状态**：图像卡片是独立组件族，不套用普通静态 Card 的阴影与边界规则。桌面 hover 可轻移 2px 或约 1.01 倍缩放，但只能改变绘制，不能改变网格占位；selected / preview 使用 2px 语义边界。`MediaQuery.disableAnimations` 时立即回到静态终态。
- **显示时机**：精确指针下，操作按钮仅在卡片 hover 或键盘 focus 时显示；进入批量选择后隐藏普通操作，避免与选中手势竞争。收藏等持续状态可以在已启用时常驻，但必须与悬浮操作使用同一视觉语言。
- **标准布局**：按卡片几何选择公共组件提供的两种呈现，不按业务页面另造布局。纵向或紧凑卡片使用右上角操作轨，距边缘 4–8px；宽横向图片卡片使用底部居中的分组工具条。收藏属于同一动作序列，不得在操作轨之外另放一枚按钮再错位追加第二组动作。
- **词库头像**：词库条目只显示圆形头像、名称与更多操作：格子够宽时头像在左、名称在右；格子较窄（如手机三列）时改为头像在上、名称居中，更多操作固定在右上角。列数与固定词网格共用 1/2/3 列规则，原列表视图并入单列，视图菜单只保留“网格 / 分组”。点按条目打开使用面板（发送到提示词、角色或固定词），长按进入多选，编辑、收藏、分类、复制与删除在更多菜单。系统相册与应用内图库共用固定圆形取景框，拖动和捏合图片调整取景；沿用原有正方形焦点坐标保存，圆形头像裁切其内切圆，其他比例预览仍居中保留焦点。无图时提供主题色占位头像。选图使用原始宽高比瀑布流，解码只限制一条边，禁止强制方形解码导致变形。
- **动作来源与顺序**：同一卡片的悬浮按钮、右键和触屏菜单使用同一份动作描述与执行状态。图片“更多操作”菜单固定以“保存图像 → 复用参数 → 复用种子 → 收藏/取消收藏”开头：有种子的图片都提供“复用种子”，只把该图种子写回生成参数；本轮刚生成的图片参数就是当前参数，不提供“复用参数”。收藏以心形状态为反馈，成功时不弹提示、失败才提示；同一张图在生成预览、历史、详情与画廊共用按文件记录的收藏状态（`imageFavoriteStatusProvider`），不依赖图库当前页。其余动作再按“查看 → 使用 → 管理 → 危险操作”分组，危险操作始终在最后。纵向操作轨使用单列或最多两列，保持从上到下、从左到右的阅读顺序；容量不足时保留“更多操作”，横向工具条在有界宽度内换行，不通过裁切丢失操作。
- **选择与作用范围**：桌面 Ctrl/Cmd 切换选中，Shift 按当前显示顺序扩选，Ctrl/Cmd+A 选择当前展示项，Esc 退出选择；输入框保留自己的快捷键。选中卡片的右键和更多菜单显示选择数量并使用明确支持的批量动作，未选中卡片只操作自身且不清空已有选择。翻页保留选择，筛选或来源切换清理失效范围。触屏长按卡片进入选择后不松手拖动，按显示顺序选中起点到手指所在卡片之间的全部卡片，拖回时撤销本次拖入的项，靠近上下边缘自动滚动（`CardDragSelect`）。
- **拖放语义**：一张卡片只注册一个资源拖动源。拖动选中项时固定整组选中资源，内部传递资源身份，桌面外部拖出按需准备真实图片、Vibe/Bundle 或精准参考配置包，不能用封面冒充资源。接收端先完整读取并验证类型与数量，再执行业务；单项入口拒绝多项，失败不能静默跳过。开始拖动、打开菜单和进入选择时关闭悬浮预览，触屏保留显式等价入口。
- **统一尺寸与样式**：精确指针下按钮使用 40×40px 圆形命中区、16px 图标与 4px 间距；触屏命中区不少于 48×48px。图片覆盖按钮统一复用 `ImageOverlayControlStyle`：半透明黑色面、细微亮色边界、白色前景，并在 hover / focus / pressed 时提高对比。删除等危险操作只切换为 `error` 语义前景，不改变按钮背景和几何。底部工具条使用同一覆盖色语义，但通过共享工具条色面组织动作，不把每个按钮复制成独立页面样式。
- **悬浮反馈**：hover / focus 只增强遮罩对比，pressed 可短暂降低不透明度；使用 100–150ms ease-out，按钮不得位移、放大、弹跳或导致相邻按钮重排。鼠标从卡片移向按钮、在按钮间移动或阅读 Tooltip 时，操作组必须稳定驻留。
- **Tooltip 与可访问性**：每个纯图标动作必须提供本地化 Tooltip、Semantics label 和键盘 focus；修饰键会改变结果时在 Tooltip 中同时说明。Tooltip 使用 Overlay 呈现，不得被卡片圆角裁切，且不能遮挡当前按钮或使操作组消失。
- **触屏等价入口**：当前使用触屏，或仅有触屏而没有精确指针时，改用卡片右上角常驻的更多操作菜单；菜单包含桌面端全部动作并保持相同分组、顺序、危险语义和执行结果。切回鼠标或桌面键盘操作时恢复常用悬浮按钮，不能因曾经触摸过就永久改成常驻菜单。长按、右键与快捷键只能作为加速入口，不能取代菜单。
- **回归要求**：覆盖最窄实际卡片、最大动作集合、已收藏、批量选择、长本地化 Tooltip、键盘 focus、触屏菜单和 Reduce Motion；断言所有按钮完整位于卡片内、互不遮挡、动作可达且 hover 前后卡片占位不变。

**The Image Action Layout Rule.** 所有图片类卡片必须按自身几何复用标准右上操作轨或底部工具条，并共享动作排序、覆盖色语义和跨端入口；动作增多时按标准方向换列或换行，不缩小、不裁切，也不创建页面专属的第二套布局与按钮外观。

动效由 `AppThemeExtension` 驱动。高频状态通常处于 100–200ms，面板和页面变化可延长到 200–300ms。界面禁止使用弹簧、回弹、过冲、弹跳、缩放弹出或会让元素方向反复变化的进出场动画；面板、弹窗、选择器和导航容器优先使用短淡入淡出，确需位移时只允许单向、无过冲的减速过渡。不得在重建时重置 Tween 起点造成横向跳动，Reduce Motion 下必须立即到达终态。启动页可以使用一次性品牌入场动画，但不得延迟真实初始化、循环吸引注意或阻止初始化完成后立即进入主界面；原生启动背景与 Flutter 启动页必须使用连续的品牌底色，避免首帧闪白或跳色。

连续拖拽调宽属于高频直接操作。pointer move 不得逐次调用页面级 `setState`、写入 Provider 或重建工作区；宽度变化必须限制在对应分栏的 RenderObject / layout 边界内，由 Flutter 帧调度合并布局，并保持两侧昂贵子树的 Widget identity。拖拽过程中禁止对宽度做补间动画，面板必须一比一跟随指针；需要持久化宽度时只在 drag end 提交最终值。回归测试应同时验证宽度边界、无 overflow，以及拖动期间稳定子树没有 rebuild。

## 视觉与交互验收

用户要求自动化验收时，按 [aaalice-runtime-verify](.agents/skills/aaalice-runtime-verify/SKILL.md) 自动启动或复用热重载，Windows 使用 Computer Use 操作并查看当前 Debug App，Android 使用 ADB 操作与截图。工具准备、授权边界和日志流程由技能维护；本节只定义应观察的设计结果。

- 按本次相关页面、子部件、状态和展开层级建立矩阵，实际打开菜单、弹窗、筛选和编辑态，确认操作结果；不能只访问顶级页面。
- 当前 Agent 逐张查看截图，检查页面四边、工具栏首尾、标题层级、文字/图标对比、对齐间距、命中区、裁切遮挡与滚动可达性；不以截图文件存在、UI 树或日志正常代替视觉检查。
- 同时比较展开/折叠、键盘出现、宽度变化、长文案和选中/禁用前后的几何稳定性。检查共享 UI 的桌面与触屏等价入口，不把鼠标 hover 当作移动端方案。
- Widget tests 验证尺寸与状态断言，真实运行检查窗口、设备和平台输入；分别报告已执行的平台与组合，不能相互替代。
- 发现本次改动引入的问题后集中修复、正确刷新并重新采集受影响场景；共享改动复查两端，临时状态恢复后交还控制权。

## Do's and Don'ts

### Do:

- **Do** 让 Prompt、图像、参数与主操作比容器和主题装饰更醒目。
- **Do** 从公共组件、`ColorScheme`、`TextTheme`、`AppThemeExtension` 和稳定 spacing tokens 获取样式。
- **Do** 保持 default、hover、pressed、selected、focused、disabled、loading 状态完整且几何稳定。
- **Do** 为桌面鼠标、触控板、键盘和移动端触屏提供等价完成路径。
- **Do** 在共享 UI 变更中至少覆盖 320、600、840、1180、1600px，并按需要补充 360/412 等实际设备宽度；同时检查 3 倍文字、短横屏、SafeArea、软键盘、系统返回和窗口缩放。
- **Do** 使用 Semantics、清晰焦点、至少 WCAG AA 的正文对比度，以及不只依赖颜色的 selected / error / success 表达。
- **Do** 让加载和错误原位呈现，局部刷新保留已有内容；超过约 300ms 的异步操作提供可见反馈。
- **Do** 将进度反馈放在所属操作按钮、任务卡片或弹窗的任务区域；顶部通知只用文字说明状态或百分比。

### Don't:

- **Don't** 在应用顶部、标题栏或工具栏下方、页面首部横幅及顶部 Toast / Overlay 中显示进度条；禁止通过插入全局进度区挤动页面内容。
- **Don't** 给普通卡片、工具按钮、导航项、chip 或已填充控件默认添加高对比完整描边。
- **Don't** 叠加“大圆角卡片 + 图标底座 + 标题 + 副标题”，或用外框、内框和分隔线重复表达同一分组。
- **Don't** 连续堆放近义标题，或把副标题当成每个控件的默认组成；信息不能帮助判断时直接删除。
- **Don't** 在同一纵向流程里嵌套两个可滚动区域；长子列表拆成独立选择弹窗。
- **Don't** 在页面散落固定颜色、圆角、间距和 Duration，或声明没有实际消费者的 token。
- **Don't** 通过缩小文字、裁切、`FittedBox`、静默隐藏功能或复制业务流程得到移动版。
- **Don't** 让 hover、右键、外接键盘或精细拖拽成为核心任务的唯一入口。
- **Don't** 在高频功能控件上使用 bounce、elastic、持续漂浮或旋转；主题个性不能牺牲操作稳定性。
- **Don't** 用 placeholder 代替标签、用 toast 承载必须阅读的信息，或用只读输入框伪装普通文本。
- **Don't** 让主题改变信息架构、语义角色、命中区、响应式行为、可访问性或跨端操作结果。
