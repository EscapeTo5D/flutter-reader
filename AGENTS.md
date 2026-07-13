# 项目记忆 (AGENTS.md)

本文件存放 ZCode 跨会话需要记住的项目级信息。新会话自动读取。

## 快速参考 (Quick Reference)

> 本节是面向任何新会话的速查表。下方「项目概况」起是历次会话沉淀的深度项目记忆，**勿删**。

### 常用命令（仓库用 FVM，`flutter` 不在 PATH 时一律加 `fvm` 前缀）

| 任务 | 命令 |
|------|------|
| 静态分析（包+example） | `fvm flutter analyze`（仓库根） |
| 全量测试 | `fvm flutter test`（仓库根，135 用例） |
| 单文件测试 | `fvm flutter test test/scroll_mode_test.dart` |
| 跑 example app | `cd example && fvm flutter run`（桌面端需先 `databaseFactory=databaseFactoryFfi`，见 `example/lib/db.dart`） |
| Flutter SDK | `.fvmrc` 锁 `stable`，`sdk: ^3.11.0`（见 `pubspec.yaml`） |

lint 用 `flutter_lints`（`analysis_options.yaml` 仅 `include: package:flutter_lints/flutter.yaml`，无自定义规则）。目标：根包 `flutter analyze` **0 error / 0 warning**（容忍少量 info）。

### 目录结构

```
lib/                          # 包代码（对外发布）
  flutter_reader.dart         # 唯一公共出口（barrel export）——新增公共 API 必须在此 export
  src/
    core/                     # 与渲染无关的核心：controller / models / storage / content_processor
      controller/             # ReadingController（外部主入口）
      models/                 # Book / Chapter / ReadingSettings + codec
      storage/                # ReaderRepository 抽象 + SqfliteReaderRepository + 数据模型
    reader/                   # 排版与渲染
      engine/                 # page_engine（排版核心）/ paginate_isolate（isolate 排版）
      entities/               # TextPage / Column
      page_animations/        # simulation_geometry/painter, scroll_mode_handler
      widgets/                # reader_view（容器）, page_view（单页+chrome）, read_menu, ...
example/                      # 演示 app（path 依赖 ../）
docs/legado_reader/           # legado 中文技术文档 00~10（与源码冲突时以源码为准）
test/                         # 单测（几何/排版/持久化/滚动/仿真 …）
```

### 架构边界（改代码前必读）

- **公共出口只有 `lib/flutter_reader.dart`**。内部实现都在 `src/`，不对外 export 的不进 barrel。
- **三层分层**：`core`（纯逻辑/数据，不依赖渲染）→ `reader/engine`（排版引擎，纯 Dart 可 isolate）→ `reader/widgets`（Flutter 渲染）。别让 widgets 的逻辑倒灌进 engine，别让 engine import `flutter/widgets` 之外的 UI。
- **`ReadingController` 是宿主唯一主入口**：`loadBook` / `loadSettings` / `updateSettings` / `flushPersistence`。持久化通过注入的 `ReaderRepository`（默认 `SqfliteReaderRepository`，null 时纯内存降级）。
- **排版引擎在 isolate**：`paginate_isolate.dart`。跨字号/屏幕改动后用 `chapterCharOffset`（非 pageIndex）恢复进度，pageIndex 会漂移（详见下方「持久化架构」）。
- **页眉/页脚不参与排版高度计算**：`nonContentHeight`（`reader_view`）与 chrome 渲染（`page_view`）的「是否计入/渲染」条件必须逐项一致，否则正文与页脚错位（详见下方「页脚尺寸计算」）。

### 关键约定

- **对齐原生 legado** 是本项目核心准则：原生 Kotlin 源码是权威参考（设备 A `D:/GitHub/legado` / 设备 B `D:/hong_projects/legado`），`docs/legado_reader/` 文档常量值有误时**以源码为准**。
- **颜色断言用 `.toARGB32()` int 比较**，不要直接 `==` 比 `Color`（不同 colorSpace 会判不等）。
- **`flutter_smart_dialog`** 是全局弹窗依赖，宿主需在 `MaterialApp.builder` 包 `FlutterSmartDialog.init()`（见 `example/lib/main.dart`）。
- **桌面 sqflite** 需宿主初始化 `sqflite_common_ffi`（`databaseFactory = databaseFactoryFfi` 或显式传 `dbPath`）。

## 项目概况

- **flutter_reader**: 基于 legado（开源阅读 App）做的 Flutter 重构，是一个文本阅读器 widget 包。
- 包代码在 `lib/`，运行示例 app 在 `example/`。
- 阅读排版配置模型: `lib/src/core/models/reading_settings.dart`（对应原生 `Config` / `ReadTipConfig`）。注意：2026-06-26 远程重构后文件已移到 `core/` 和 `reader/` 下。

## 原生项目 (legado) 位置 ⚠️ 重要

- 路径（**两台设备不同位置，都是同一项目的本地 clone**）:
  - 设备 A: **`D:/GitHub/legado`**
  - 设备 B: **`D:/hong_projects/legado`**
  - 两路径下源码结构一致（相对路径如 `app/src/main/...` 在两处都有效），引用源码文件时按当前设备取对应根目录。
  - ⚠️ 上一版 AGENTS.md 曾记「`D:/hong_projects` 是用户口误、实际只有 `D:/GitHub/legado`」——**那条记录有误**，两路径都是真实有效的设备本地路径，并非口误。
- git remote: `https://github.com/Luoyacheng/legado.git`
- 是原生 Android (Kotlin) 项目，本 Flutter 项目的重构参考来源。
- 本仓库 `docs/legado_reader/` 下有 legado 的中文技术文档（00~10 章），但文档与源码有出入时**以源码为准**。

### legado 关键源码路径（阅读/排版相关）

| 用途 | 路径 |
|------|------|
| 单页视图(含页眉/页脚) | `app/src/main/java/io/legado/app/ui/book/read/page/PageView.kt` |
| 页面布局 XML | `app/src/main/res/layout/view_book_page.xml` |
| 正文绘制 | `app/src/main/java/io/legado/app/ui/book/read/page/ContentTextView.kt` |
| 阅读视图容器(三页缓存/翻页) | `app/src/main/java/io/legado/app/ui/book/read/page/ReadView.kt` |
| 页数据实体 | `app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPage.kt` |
| 排版工厂 | `app/src/main/java/io/legado/app/ui/book/read/page/provider/TextPageFactory.kt` |
| 画笔/排版参数 | `app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt` |
| 阅读配置单例 | `app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt` |
| **提示信息配置** | `app/src/main/java/io/legado/app/help/config/ReadTipConfig.kt` |
| 全局阅读状态 | `app/src/main/java/io/legado/app/model/ReadBook.kt` |
| 电量/图标自定义 View | `app/src/main/java/io/legado/app/ui/widget/BatteryView.kt` |

## 底部页脚 (Footer) 原生实现要点

**结构**（`view_book_page.xml`）：根是 ConstraintLayout，从上到下：
`vw_status_bar` → `ll_header`(页眉) → `vw_top_divider` → `content_text_view`(正文) → `vw_bottom_divider` → `ll_footer`(页脚) → `vw_navigation_bar`。

**页脚 `ll_footer`** 也是 ConstraintLayout，固定 3 个 `BatteryView` 槽位：
- `tv_footer_left` (宽 0dp, weight 1, 左对齐)
- `tv_footer_middle` (居中, 默认 gone)
- `tv_footer_right` (右对齐, marginLeft 3dp)
- 所有槽位 12sp, singleLine, ellipsize=end。
- 用 `io.legado.app.ui.widget.BatteryView` 而非普通 TextView —— 它能根据 tip 类型切换「文本」或「电量图标(+文本)」显示。

**每个 tip 内容由配置驱动**（`ReadTipConfig.kt`，常量值）：
```
none=0 chapterTitle=1 time=2 battery=3 page=4
totalProgress=5 pageAndTotal=6 bookName=7
timeBattery=8 timeBatteryPercentage=9
batteryPercentage=10 totalProgress1=11
```
注意：本仓库 `docs/legado_reader/07-配置系统.md` 里写的常量值是**错的**（如 time=5, battery=6, pageAndTotal=4），以源码 `ReadTipConfig.kt` 为准。

**绑定逻辑**（`PageView.kt`）：
- `upTipStyle()`: 清空各槽 tag，按 `ReadTipConfig.tipFooterLeft/Middle/Right` 的值，用 `getTipView(tip)` 反查该 tip 应显示在哪个槽，再设置对应 `tvXxx`(tvTitle/tvTime/tvBattery/...) 的 tag、isBattery、textSize/typeface。即「值→槽位」是动态反查的。
- `setProgress(textPage)`: 填充实际文本——
  - 书名 `tvBookName` = `ReadBook.book.name`
  - 章节标题 `tvTitle` = `textPage.title`
  - 总进度 `tvTotalProgress` = `textPage.readProgress`
  - `tvTotalProgress1` = `"${chapterIndex+1}/$chapterSize"` (当前章/总章)
  - `tvPageAndTotal` 完结章 = `"${index+1}/$pageSize  $readProgress"`，未完结章 pageSize 显示为 `~N` 或 `-`
  - `tvPage` = `"${index+1}/$pageSize"`（不含进度）
- `upTime()` / `upBattery(battery)`: 实时刷新时间(`HH:mm`)与电量；`upTimeBattery()` 组合「时间 + 电量」给 `tvTimeBattery` / `tvTimeBatteryPercentage`。
- `footerMode`: 0=显示(默认), 1=隐藏（与 headerMode 三态不同，footer 只有两态）。

**三页缓存**：`ReadView` 维护 `prevPage/curPage/nextPage` 三个 PageView，每个都各自带一套页眉/页脚，翻页动画时跟随移动。

## 页脚与排版的关系 ⚠️ 核心架构

**关键结论：页眉/页脚不参与排版的高度计算，它们是 ConstraintLayout 布局约束自动隔离掉的。** 排版引擎拿到的尺寸已经是"纯正文可用区域"。

**尺寸传递链路**：
1. `PageView` 根布局是 ConstraintLayout，`content_text_view` 用约束夹在 header/footer 之间：
   `app:layout_constraintTop_toBottomOf="@id/vw_top_divider"` 且
   `app:layout_constraintBottom_toTopOf="@id/vw_bottom_divider"`。
2. Android 布局系统自动测量 → `ContentTextView` 的 `onSizeChanged(w, h)` 拿到的 w/h **已扣除页眉页脚**（`ContentTextView.kt:95-99`）。
3. `ContentTextView.onSizeChanged` 调 `ChapterProvider.upViewSize(w, h)`（`ContentTextView.kt:98`）。
4. `ChapterProvider.upLayout()` 算出排版核心尺寸（`ChapterProvider.kt:313-358`）：
   - `visibleWidth = viewWidth - paddingLeft - paddingRight`（双页时再除以 2）
   - `visibleHeight = viewHeight - paddingTop - paddingBottom`
   - 这里的 `paddingTop/Bottom` 是**用户配置的内容区内边距**（`ReadBookConfig.paddingTop/Bottom`），不是页眉页脚高度。
5. `visibleHeight/visibleWidth` 传给 `TextChapterLayout` 做分页（`prepareNextPageIfNeed` 判断 `durY > visibleHeight` 即换页）。

**所以**：
- 页眉页脚的显示/隐藏/高度变化 → 触发 ConstraintLayout 重新测量 → ContentTextView 尺寸变 → `onSizeChanged` → 重新排版。链路是自动的，排版代码无需感知页眉页脚。
- `PageView.headerHeight` 这个 getter 只用于**触摸坐标换算**（把全屏触摸点 y 减去 headerHeight 映射到正文坐标，`PageView.kt:60-65,410`），**不喂给排版**。

**排版引擎入口**：`TextChapterLayout`（`provider/TextChapterLayout.kt`），核心循环：
- 逐段落 `setTypeText` / 图片 `setTypeImage` / HTML `setTypeHtml`
- 用 `StaticLayout` 或自定义 `ZhLayout`（中文优先断行）算换行
- `durY` 累加行高(`textHeight * lineSpacingExtra`)、段距(`textHeight * paragraphSpacing/10`)
- `prepareNextPageIfNeed(durY + textHeight)` 判断超 `visibleHeight` 则 `onPageCompleted()` 切页
- `textFullJustify` 两端对齐：`addCharsToLineMiddle` 按空格数或字间距分配剩余宽度
- 每页结束加 `endPadding = 20dp`（`TextChapterLayout.kt:499-505`），末页不满则撑高。

## Flutter 端对应实现

- 配置模型: `lib/src/core/models/reading_settings.dart`
  - `HeaderFooterConfig { left, center, right, hidden }`（比原生多中槽，是兼容超集；`hidden` 对应原生 headerMode/footerMode 整体显隐）
  - `TipPosition` 枚举
- 渲染: `lib/src/reader/widgets/page_view.dart` 的 `_buildFooter()` / `_buildTip()`
- 默认 footer: 左=bookName(7), 中=none, 右=pageAndTotal(6) —— 对齐原生微信读书预设 readConfig.json(tipFooterLeft=7/Right=6)。2026-07-03 修正：左槽曾误为 chapterTitle，现改回 bookName。
- ⚠️ header 默认值**未对齐原生微信读书**：Flutter 现 左=time(2)/右=battery(3)，但原生微信读书 JSON 是 `tipHeaderLeft=1`(chapterTitle) / `tipHeaderRight=2`(time)，即 左=章节标题/右=时间。如需对齐需另行修改（用户本轮只要求改 footer 书名）。

## 行距/段距模型对齐（2026-06-26，commit 9cee39c）

原生 legado 用「纯字体度量 `textHeight` × 系数」模型（`ChapterProvider`/`TextChapterLayout`）：
```
textHeight        = descent - ascent + leading   // 纯字体度量(≈fontSize)
lineSpacingExtra  = ReadBookConfig.lineSpacingExtra / 10   // 默认 config=12 → 1.2
paragraphSpacing  = ReadBookConfig.paragraphSpacing         // 默认 config=2(整数)
行距 durY += textHeight * lineSpacingExtra            // 每行后
段距 durY += textHeight * paragraphSpacing / 10f      // 每段末尾追加(TextChapterLayout.kt:1026)
```

Flutter 端（`page_engine.dart` + `reading_settings.dart`）已对齐：
- `lineHeight`(默认 **1.2**)：行距倍数 = 原生 lineSpacingExtra。同时作为 TextPainter 的 `style.height` 用于换行测量。
- `paragraphSpacing`(默认 **2.0**)：段距系数，公式 `段距 = textHeight * paragraphSpacing / 10`，**非固定 px**。
- `TextLine.textHeight`（纯字体度量）：由 `metric.height / style.height` 反推（Flutter 把 leading 摊进 height，故除回去）。
- 渲染行高 `line.height = textHeight * lineHeight = metric.height`（与 paint 时 style.height 一致）。
- **段距注入**：`paginate` 在每个正文段落末尾插入一个 `isEmptyParagraph` 行（height=段距），对齐原生 `setTypeText` 段末 `durY` 累加。标题段用独立的 `titleBottomSpacing`，不走这里。
- ⚠️ `ContentProcessor` 跳过源文本空行（`if (paragraph.isEmpty) continue`），故实际管线里段距只来自引擎注入，不会双重；直接调 `paginate` 带 `\n\n` 的 caller 会对每个空行也加段距行（对齐原生同样跳过空行）。

## 字号/字距/行距/段距 滑块映射（2026-06-29 修正）

对齐原生 `ReadStyleDialog.kt` + `dialog_read_book_style.xml` 的四个 `DetailSeekBar`。**原生 progress 直接 = 字段值**，关键映射（`read_menu.dart` 的 `_StyleDialogState`）：

| 项 | xml max | progress↔字段 | display(valueFormat) | 默认(=微信读书预设) |
|---|---|---|---|---|
| 字号 textSize | 45 | `textSize = progress + 5` (5~50sp) | `progress + 5` | 24→p19 |
| 字距 letterSpacing | 100 | `letterSpacing = (progress-50)/100` (-0.5~0.5) | `(progress-50)/100` | 0→p50 |
| 行距 lineSpacingExtra | 20 | **progress = lineHeight × 10**(整数, 步长 0.1) | `(progress-10)/10` | 1.0→p10, 显示 0.0 |
| 段距 paragraphSpacing | 20 | **progress = 字段值**(整数) | `progress/10` | 6.0→p6, 显示 0.6 |

- 行距：字段 `lineHeight` 是「倍数」(= 原生 `lineSpacingExtra/10`)，正反推 `progress ↔ lineHeight × 10`。旧实现误用 0.015 步长（与原生 0.1 不符，正反推漂移），已修。
- 段距：字段 `paragraphSpacing` 的**值即原生 progress**(默认 2)。旧实现误用 `×10`（默认 2.0 被推成 p=20 满格），已修。渲染公式 `段距 = textHeight × paragraphSpacing / 10` 不变。
- 字段语义和 page_engine 渲染公式原本就与原生数值一致，这次只动 UI 滑块的正/反推换算 + 预设值。
- `page_engine._textStyle` 的 `height` 加了下限保护（≤0 落到 0.1），因原生 progress=0 时倍数为 0/负不崩，但 Flutter `TextPainter` 要求 `height > 0`。
- 预设点击同步换算（`_lineHeightProgress = lineHeight×10`、`_paragraphSpacingProgress = 字段值`），含 `_StylePreset` 数据。

## 行内 baseline 对齐原生（2026-06-29 修正行距视觉不对等）

**问题**：用户反馈"行距视觉不一致"。查源码定位到根因——行距系数对，但**行内文字垂直位置**不对。

**原生模型**（`TextLine.kt:103-107` `upTopBottom`）：文字顶部对齐 `textHeight` 顶部，lineSpacingExtra 的缝全部留在行块下方：
```
textHeight = descent - ascent + leading    // 纯字体度量, 不含 extra (PaintExtensions.kt:8)
lineBase   = textHeight - descent          // baseline 紧贴字体底部
// 行块内: [文字 textHeight 高][缝 textHeight×(lineHeight-1)]
```

**Flutter 旧实现错在哪**：`lineBase` 直接用 `metric.baseline`。但 Skia 的 `metric.height`(=textHeight×lineHeight) 会把 leading 摊在文字**上方**（文字在行块里偏下），与原生"缝全在下方"相反。lineHeight 越大偏移越大，实测（fs=24）：
```
lineHeight=1.0 → baseline 一致(缝为0, 无 leading 可摊, 两者重合) ← 微信读书正好是1.0, 所以它对等
lineHeight=1.2 → Flutter 文字偏下 4.83px (默认预设1~5 用1.2, 故不对等)
lineHeight=1.5 → 偏下 12px
```

**修复**：`page_engine.dart` `_wrapText` 里 `lineBase` 不再用 `metric.baseline`，改用原生公式重算 `textHeight - metric.descent`。`textHeight = metric.height / lineHeight`。这样文字在行块内顶部对齐、缝留下方，与原生一致。`metric.height` 仍是行块总高（含缝），`SizedBox(height: metric.height)` 不变。
- 影响面：仅 `lineBase` 一处，CustomPainter 绘制 + 选中高亮框（用 lineBase）都自动对齐。
- 降级 Text 分支（`!line.hasCharData`，几乎不走）仍用 Skia 默认，未改。
- 回归测试：`test/line_spacing_test.dart` 新增"lineBase 按原生公式重算"用例，锁定 lh=1.0/1.2/1.5 三个值。

**结论**：行距系数（lineHeight）换算一直是对的；视觉不对等是因为行内 baseline 定位，现已修。微信读书(lineHeight=1.0)本就对等，预设1~5(1.2)和大行距场景现在也对齐了。

## 行距/段距字体度量补偿（2026-06-29, 解决"0.4 对应 0.0"）

**问题**：上一条修完 baseline 后，用户实测反馈"Flutter 行距显示 0.4 才 ≈ 原生 0.0"。即行距系数换算虽对，但**绝对行距偏紧**。

**根因（实测确认）**：两平台「纯字体度量 textHeight」的 ratio 不同：
- 原生 `textHeight = descent - ascent + leading`（Android Paint，中文字体如思源黑体/Noto CJK）≈ **fontSize × 1.4**（asc/desc 都大，含 leading）。
- Flutter `textHeight = metric.height / lineHeight`（默认 Roboto）≈ **fontSize × 1.0**（实测各字号 height 恒等 fontSize，无 leading；测试环境连中文字体名也 fallback 到 Roboto，ratio 仍 1.0）。
- 故同样 lineSpacingExtra 倍数：原生行推进 = `fontSize × 1.4 × 倍数`，Flutter 仅 `fontSize × 1.0 × 倍数`，差约 0.4。用户反馈"Flutter 0.4 ↔ 原生 0.0"反推确认 ratio_native ≈ 1.4。

**修复**：`page_engine.dart` 加常量 `_nativeMetricFactor = 1.4`，仅作用于"间距性质"（行块高 + 段距）：
```
行块高 height = metric.height × 1.4          // _wrapText, lineBottom 同步
段距     = textHeight × paragraphSpacing / 10 × 1.4   // 空段落行 + 段末行两处
```
补偿后恒等式：`height = textHeight × lineHeight × 1.4`（非旧的 `× lineHeight`）。

**不受补偿影响**（关键，保持文字正确）：
- `lineBase = textHeight - descent`（真实字体度量，文字顶部对齐，lineBase 测试三个 lh 值不变）
- `textHeight` 字段（保持纯字体度量，baseline + 段距借用都依赖它）
- 滑块换算 / 预设值 / 默认值（仍按原生 progress 语义，用户看到的数值与原生一致：原生0.0 ↔ Flutter0.0）

**语义**：1.4 是"Flutter 字体 ratio(1.0) → 原生中文字体 ratio(~1.4)"的等效放大。补偿后原生显示 0.0(lineSpacingExtra=1.0) 与 Flutter 显示 0.0(lineHeight=1.0) 行推进绝对值一致。固定值而非动态测量——因 Flutter 端实际渲染字体 ratio 恒为 1.0（无论指定中文字体名都会 fallback），动态测无意义；1.4 是中文字体通用 ratio。

**回归测试**：`line_spacing_test.dart` 行高/段距断言更新为含 `× 1.4`；lineBase 测试不变（验证 baseline 不受补偿影响）。全套 34 测试通过。

## 文字底色预设（2026-06-29 对齐）

原生权威数据源：`D:/GitHub/legado/app/src/main/assets/defaultData/readConfig.json`（`DefaultData.readConfigs` → `ReadBookConfig.configList`）。共 6 个预设：

| 预设 | bg | text | textSize | letterSpacing | lineSpacingExtra | paragraphSpacing |
|---|---|---|---|---|---|---|
| **微信读书** | `#ffc0edc6` | `#ff0b0b0b` | 24 | 0 | 10 | 6 |
| 预设1 | `#FFFFFF` | `#000000` | (Config默认20) | (0.1) | (12) | (2) |
| 预设2 | `#DDC090` | `#3E3422` | 默认 | 默认 | 默认 | 默认 |
| 预设3 | `#C2D8AA` | `#596C44` | 默认 | 默认 | 默认 | 默认 |
| 预设4 | `#DBB8E2` | `#68516C` | 默认 | 默认 | 默认 | 默认 |
| 预设5 | `#ABCEE0` | `#3D4C54` | 默认 | 默认 | 默认 | 默认 |

- **默认预设 = 微信读书**：`ReadingSettings()` 构造默认值已改为微信读书参数（fontSize=24, lineHeight=1.0, paragraphSpacing=6.0, letterSpacing=0, bg=#C0EDC6, text=#0B0B0B）。首次打开即微信读书样式，无需手动选预设。
- **预设1~5 切换语义**：原生 JSON 只存颜色，其余字段回退到 `ReadBookConfig.Config` 类默认值（textSize=20, letterSpacing=0.1, lineSpacingExtra=12→lineHeight 1.2, paragraphSpacing=2）。故 Flutter `_StylePreset` 给预设1~5 显式补全这些默认文字参数——切换时重置滑块，而非保留当前值。对齐原生"切预设即重置排版参数"语义。
- **lineSpacingExtra↔lineHeight 换算**：微信读书 lineSpacingExtra=10 → lineHeight=1.0；预设1~5 = 12 → 1.2。
- **颜色 alpha**：原生微信读书色带 `#ff` 前缀（完全不透明），Flutter 用 `Color(0xFFxxxxxx)` 等价；预设1~5 色原生不带 alpha，Flutter 同样用 `0xFF` 前缀（不透明），视觉一致。
- **未对齐项（留待后续）**：原生预设还含 day/night/eink 三套色 + bgImage + bgAlpha + textAccent，以及 titleSize/titleMode、tipColor、翻页动画的实际绘制。Flutter `_StylePreset`/用户预设暂只存单套 bg/text 色 + fontSize/letterSpacing/lineHeight/paragraphSpacing。padding 边距已对齐（见下条「设置弹窗全量对齐」）。「字体」按钮暂为空实现。

## 页脚尺寸计算（已修复 2026-06-26）

**核心规则**：`reader_view.build()` 里算 `nonContentHeight`（喂给排版引擎的可用高度）时，每项"是否计入"的条件，必须和 `page_view.build()` 里"是否渲染"的条件逐项一致，否则正文与页脚会错位/重叠。

**对齐后的条件**（`page_view` 与 `reader_view` 必须同步）：
- `showHeader = settings.hideStatusBar && !settings.headerConfig.hidden`
- `showFooter = !settings.footerConfig.hidden`
- header 高度: 仅 `showHeader` 时计入 `headerHeight + headerTop + headerBottom`
  （2026-07-03 后 `ReaderPadding` 扩展为各向 padding; header 外层上下边距 `headerTop/headerBottom` 单独计入）
- footer 高度: 仅 `showFooter` 时计入 `footerHeight + footerTop + footerBottom`
  （旧实现硬编码 `+6` 即 top2+bottom4, 现改为读 `footerTop/footerBottom` 字段; 默认值见下「设置弹窗全量对齐 / WS2」节, 以微信读书 JSON 预设为准）
- 分隔线 0.5: 跟随各自 show + showHeaderDivider/showFooterDivider

**设计约定（对齐原生 legado）**：
- 翻页模式（含 scroll）不影响 chrome 显隐，只改变翻页方式。scroll 模式也显示页眉页脚。
- 页眉页脚整体显隐只看 `hidden` 字段；三槽全 none 时页脚仍占位（对齐原生"容器始终在"）。

## 设置弹窗全量对齐原生（2026-07-03）

对齐原生 `ReadStyleDialog` + `dialog_read_book_style.xml` + `PaddingConfigDialog`，分 4 个工作流：

### WS1 视觉对齐（commit b632d74）
- **去背景遮罩**：`_showStyleDialog` 的 `maskColor` 从 50% 黑改 `Colors.transparent`，对齐原生 `dimAmount=0.0f`（阅读页正文完全可见，不被半透明遮罩盖）。
- **去顶部圆角**：弹窗 Container 去掉 `borderRadius`，对齐原生无圆角（顶部直角贴屏底）。
- **字重文字**：原生 `strings.xml font_weight_text="N/B/L"`（英文），WS1 曾按「源码为准」改成 `N/B/L`，**后按用户偏好改回中文 `中/粗/细`**（commit 2162323）。教训：UI 文案/语言是用户偏好，**覆盖**「源码为准」原则——中文 App 用中文标签更直观，别为严格匹配原生英文 strings 而改语言。
- **预设选中边框**：宽度恒 1dp，仅 `borderColor` 从 textColor 变 accentColor（旧实现选中变宽 1→2px，错）。对齐原生 `CircleImageView` border 宽度恒定。
- **背景色** `#FFFFFF`→`#FAFAFA`：对齐原生 `md_grey_50`（原生运行时被主题 `bottomBackground` 覆盖，本包无主题系统故取静态值）。

### WS4 共享排版 shareLayout（commit 4a334f1）
- `ReadingSettings` 加 `bool shareLayout`（默认 false）+ codec 字段。
- **Flutter 语义重定义**（原生「跨样式槽共享」在扁平配置无对应）：`shareLayout=true` 时点颜色预设**只换 bg/text，不重置** 字号/字距/行距/段距 滑块；false 时切预设连同排版参数一起重置（原生默认行为）。这正是「共享排版」的用户可感知本质。
- checkbox 接线 `_shareLayout`，label 改「共享排版」。

### WS2 PaddingConfigDialog 边距弹窗（commit f0057cf；默认值 2026-07-03 修正）
- `ReaderPadding` 从 6 字段扩展为 14：body 原 top/bottom/left/right 保留；新增 header/footer 各 top/bottom/left/right。`copyWith` + codec 同步（向后兼容）。
- ⚠️ **默认值真相（2026-07-03 修正，推翻此前所有关于 padding 默认值的记录）**：原生 legado 的 padding 运行时默认值来自 `assets/defaultData/readConfig.json` 的「微信读书」预设（`configList[0]`，由 `DefaultData.readConfigs` 加载，`initConfigs`/`resetAll` 都用它），**不是** `ReadBookConfig.kt` 里 `Config` data class 的字段默认值（`6/6/16/16` 等）。data class 的 `=6` 只在预设1~5（JSON 缺 padding 字段）被 Gson 反序列化时回退用，而 Flutter 默认预设 = 微信读书。**核对默认值永远以 `readConfig.json` 的微信读书条目为准，别再看 `Config` data class。** `ReaderPadding` 默认构造现已全套对齐该 JSON：
  - 正文 `top/bottom/left/right` = **5/4/22/22**
  - header `top/bottom/left/right` = **10/0/19/16**
  - footer `top/bottom/left/right` = **0/10/13/17**
  - `headerHeight` = 24、`footerHeight` = **22.5**（均原生无此字段，抽象为固定行高。原生页脚行高是 `wrap_content` 自适应：12sp 文字(高≈12) + `BatteryView` 控件内 padding(上3下3) ≈ 18；22.5 为视觉偏好值，非原生实测，Flutter 用 `SizedBox` 写死高度故需一个数）
  - `showHeaderDivider`/`showFooterDivider` 默认均 **true**（对齐 JSON `showHeaderLine=true/showFooterLine=true`；此前 `showHeaderDivider` 误为 false）
  - 注意这套值**不对称**（headerLeft 19 ≠ headerRight 16 等），这是 legado 原始数据，照搬。
- **此前误记（已作废）**：曾长期记录"原生默认 6/6/16/16、用户偏好 footer 2/4 覆盖之、别改回 6/6"——这套建立在错误的 data-class 默认值上。footer 真正默认是 0/10（上0下10，用户手机所见即此）。footerHeight 与 footer padding 是两个独立维度：前者是 Flutter 抽象的固定行高（原生无此字段，wrap_content 自适应），后者已改回 JSON 真值。
- **`nonContentHeight` 计算**：header 总高 = `headerHeight + headerTop + headerBottom`，footer 同理（旧实现 footer 硬编码 `+6`，现读字段）。
- `page_view` 的 header/footer 渲染改用各向外边距（`headerLeft/Right/Top/Bottom` 等），删除 footer 外层冗余 `Padding`（避免与 footerTop/Bottom 双重 padding）。
- 新增 `_PaddingConfigDialog`：居中弹窗（0.9 宽，无 dim），3 组（页眉/正文/页脚）×4 向 = 12 滑块 + 2 分隔线开关（复用 `showHeaderDivider/showFooterDivider`）。body top max=200，其余 max=100，值整数 dp。
- 抽共享组件 `lib/src/reader/widgets/detail_seek_bar.dart`（`DetailSeekBar`，复刻原生 `DetailSeekBar`：`[标题60dp][−][Slider][+][值60dp]`），两个弹窗复用。

### WS3 用户自定义预设 DB 持久化（commit 39effe0）
- 新模型 `ReadingStylePreset { id, userId, name, bgColor, textColor, sortOrder, createdAt }`（极简，只存预设弹窗能选的 bg/text 色，不存排版参数——对齐 shareLayout 语义）。
- **schema v3**：新表 `reading_style_presets(id PK, user_id, name, bg_color, text_color, sort_order, created_at)` + 索引。`_onCreate` batch 加表，`_onUpgrade` 加 `if(oldVersion<3)` 块（照搬 v2/chapter_contents 模式）。
- repository 抽象 + sqflite 实现各加 3 方法：`getStylePresets(userId)` / `saveStylePreset`（upsert）/ `deleteStylePreset`。
- controller 透传 3 方法（无 repository 时返回空/无操作，纯内存退化）。
- `_StyleDialog`：initState 异步 `loadStylePresets`，内置 6 + 用户预设合并显示；「+」onTap 新建预设（用当前 bg/text 色，时间戳 id）存库刷新；长按预设 → `_PresetEditorDialog`（极简版 BgTextConfigDialog：名称输入 + bg/text 色板网格 8×2，删除/保存按钮）。颜色选择器用预设色板网格（不引第三方包）。
- **测试**：`sqflite_repository_test.dart` 加 3 用例（往返+升序、用户隔离、upsert+删除），共 85 测试通过。⚠️ 颜色断言用 `toARGB32()` int 比较，**不要直接 `==`** 比较两个 `Color`——不同 colorSpace（sRGB vs wide-gamut）会判不等（`Colors.green` vs `Color(0xFF4CAF50)`）。

### 不做的（本轮显式排除）
- ❌ 「字体」按钮（保持空实现；原生从文件系统选 .ttf/.otf 需 file_picker 依赖 + FontLoader）。
- ❌ 简繁实际文本转换（本包无 CJK 转换库，仅记录选中态）。
- ❌ 预设的 day/night/eink 三套色 + bgImage + bgAlpha + textAccent（原生 BgTextConfigDialog 全功能）。

## 顶部 6 按钮的子弹窗对齐原生（2026-07-03，commit 91926e9）

**问题**：点开「界面」→ _StyleDialog 后，顶部 6 个按钮（字重/字体/缩进/简繁/边距/信息）弹出的**子弹窗**与原生不对齐。**根因**：原生里这 6 个子弹窗**全部居中**（只有外层 ReadStyleDialog 自身是 `Gravity.BOTTOM`），但 Flutter 旧实现把字重/缩进/简繁做成了**底部滑出 sheet**，边距/信息位置对但样式/交互错。

**关键结论（务必记住）**：`context.alert{}` / `context.selector{}`（`AndroidAlertBuilder.show()` + `applyTint()` 的 `filletBackground`）= **居中 AlertDialog**：居中、3dp 圆角、主题背景色填充、标准 dim 遮罩、顶部标题、`setItems(...)` 纯文本列表（**无 checkmark**）、点击即选即关。**不是 bottom sheet。** 字重/缩进/简繁 都用它；TipConfigDialog 内部各 selector 也用它。

**本轮改动**（`read_menu.dart` 为主）：
- **新增 `_showOptionList` helper**：复刻上述居中 AlertDialog（`SmartDialog.show(alignment: Alignment.center, maskColor: 0.5黑)`，Container 3dp 圆角白底、标题在顶、纯文本 InkWell 列表）。字重/缩进/简繁/TipConfigDialog 各 selector 全部复用。
- **字重**：底部 sheet → 居中，标题「文章字重切换」，项 正常/粗体/细体（对齐 `R.array.text_font_weight` + 标题 `text_font_weight_converter`）。
- **缩进**：底部 sheet → 居中，标题「缩进」，**项数 9→5**（对齐 `R.array.indent` 5 项；原生公式 `paragraphIndent = "　".repeat(index)`，故 index ∈ 0..4，最多 4 全角空格）。`textIndent` 存 0..4。
- **简繁**：底部 sheet → 居中，标题「中文简繁体转换」，项 关闭/繁体转简体/简体转繁体（对齐 `R.array.chinese_mode`）。
- **边距弹窗 `_PaddingConfigDialog`**：圆角 **8→0**（原生 `BaseDialogFragment.onViewCreated` 仅 `setBackgroundColor`，无圆角）；分组标题行**内联**「显示分隔线」+ Checkbox（对齐 `dialog_read_padding.xml` 的 `tv_header_padding … showLine cb_show_top_line` 同行 LinearLayout）；正文组无开关。删 `_buildLineSwitch`（不再用 Switch）。padding 16→10（对齐 xml `padding=10dp`）。
- **信息弹窗 `_TipConfigDialog` 全宽 + 接通实际读写**：
  - 去掉 `maxWidth:340`，改 `Padding(horizontal:16)` 近全宽（对齐 `setLayout(MATCH_PARENT, WRAP_CONTENT)`）。
  - 每行（显示/左/中/右/提示颜色/分隔线颜色）**可点** → 弹居中 selector，直接 `controller.updateSettings` 读写：headerConfig/footerConfig 的 `hidden`/`left`/`center`/`right`、`tipColor`、`tipDividerColor`。
  - 「显示」selector 2 项（显示/隐藏）→ 写 `headerConfig.hidden`/`footerConfig.hidden`（true=隐藏，对齐原生 headerMode/footerMode 两态）。
  - 「左/中/右」selector = TipPosition 全集（Flutter 10 项：无/书名/标题/时间/电量/电量%/页数/进度(%)/时间及电量/页数及进度，对齐 `R.array.read_tip` 取 Flutter 支持项）。选后 **clearRepeat**：非 none 的 tip 在两区六槽中唯一，重复则把旧槽清成 none（对齐原生 `TipConfigDialog.clearRepeat`）。
  - 提示颜色 selector（跟随文字/自定义）+ 分隔线颜色 selector（跟随文字/跟随背景/自定义），自定义 → `_ColorSwatchPicker` 预设色板网格点选（复用 `_PresetEditorDialog._swatch`，不引第三方颜色选择器）。
  - 标题区 RadioGroup（靠左/居中/隐藏）+ 3 DetailSeekBar（字号/上边距/下边距）保留并接通。titleMode 变更同步回外层 _StyleDialog（`onTitleModeChanged` 回调 → setState + `_apply` 一起持久化）。
- **模型加 `Color? tipDividerColor`**（对齐 `ReadTipConfig.tipDividerColor`）：默认 null=跟随文字；`Color(0x00000000)` 作 sentinel=跟随背景；其余=自定义 ARGB。+ copyWith + codec（forward-compat：缺失字段回落 null）。serialization_test 补默认值+自定义值往返断言。

**渲染侧未接 tipDividerColor**：page_view.dart 的分隔线颜色目前仍硬编码，本轮只接通配置/持久化，渲染消费留待后续（与原生「分隔线颜色单独配」语义一致，避免本轮改动面过大）。

## 持久化架构（2026-06-29 实现：进度/设置/书签/书架/用户绑定）

**决策**：本地 sqflite + 多用户隔离 + 进度存字符位置（charOffset）+ 包内接口+默认实现。全 58 测试通过。

### 三层数据流
1. **引擎层** `page_engine.dart`：`TextLine.chapterPosition`（已存在但此前恒为 0，本次补全累加逻辑）= 该行在「预处理后内容」（`ContentProcessor` 输出 `join('\n')`）中的绝对字符偏移。**标题段也计入偏移流**（不归零），保证 charOffset 自洽可逆。
2. **Repository 层** `lib/src/core/storage/`：
   - `reader_repository.dart` — abstract 接口（用户/进度/书签/设置/书架 CRUD）。宿主可注入任意实现。
   - `sqflite_reader_repository.dart` — 默认 sqflite 实现（单文件 `flutter_reader.db`，5 张表）。桌面需宿主先初始化 `sqflite_ffi` 并传 `dbPath`（或调 `databaseFactory=databaseFactoryFfi`，example 的 `db.dart` 已封装）。
   - `reading_progress.dart` / `reader_user.dart` — 进度/用户数据模型（均带 toJson/fromJson）。
3. **Controller 层** `reading_controller.dart`：可选注入 `ReaderRepository`+`userId`（null = 纯内存，退化为旧行为，**不破坏现有 API**）。

### charOffset 进度模型（核心，对齐原生 legado dur/durPos）
- **为什么不用 pageIndex**：pageIndex 依赖 pageSize+settings（字号/行距/屏幕），换设备或改字号会漂移、跳页。
- **进度存什么**：`(chapterIndex, chapterCharOffset)`。恢复时重走"预处理→分页"，用 charOffset 二分 `_pages` 各页首行 chapterPosition 定位回页。
- **跨字号验证**：`test/persistence_integration_test.dart` "改字号重排后用 charOffset 仍定位到对应内容"——fontSize 20→30 重排后页数变了，但 charOffset 不变，仍落在同一内容位置。
- 互转方法（controller 私有）：`_charOffsetForCurrentPage()`（取当前页首行 chapterPosition）/ `_pageIndexForCharOffset(int)`（二分落页）。

### 防抖落盘
- 翻页/翻章/改设置后 1.5s 内无新动作才写库（`_progressSaveTimer`/`_settingsSaveTimer`），避免连续翻页每页一次 IO。
- `flushProgress()`：立即落盘，宿主在 controller.dispose() 前调（dispose 不能 async，内部只能 fire-and-forget）。
- `addBookmark` 同步落库；删除书签同步删库。

### 序列化（`reading_settings_codec.dart`，模型保持纯净）
- `encodeReadingSettings()`/`decodeReadingSettings()` 函数式编解码，带 `_version` 字段供 schema 迁移。
- Color → `toARGB32()`；FontWeight → `.value`（字重数值，非 index，index 已弃用）；枚举 → `.name`。
- 缺失字段回落 `ReadingSettings` 默认值（向前兼容旧 schema）。
- ⚠️ Flutter 3.41 stable：`Color.toARGB32()` 有，但 `Color.fromARGB32()` 尚不可用，fromJson 仍用 `Color(value)`（value 已弃用但唯一入口）。

### 用户绑定
- `ReaderUser { id, name?, avatar? }` 极简，只是隔离键载体。**本包不管账号登录/鉴权**（宿主职责）。
- 进度/书签/书架复合键 `(userId, bookId)`；设置可全局(`__global__`)或按用户。
- controller：构造 `{repository, userId}` 或 `attachRepository(repo, userId:)`/`bindUser(uid)`。

### 接入方式（example 已演示）
```dart
// main() 里: await AppDatabase.init();  // example/lib/db.dart
// ReaderPage: ReadingController(repository: AppDatabase.repo, userId: 'demo-user')
// loadBook 前: await controller.loadSettings();
// loadBook 后: controller 自动 restoreProgress + loadBookmarks
// 退出前: await controller.flushProgress();
```

### 测试覆盖（新增 4 个文件，19 个用例）
- `chapter_position_test.dart`(5)：chapterPosition 单调递增/标题偏移/同段多行/offset↔page 二分/覆盖完整内容。
- `serialization_test.dart`(6)：settings+bookmark 往返、向前兼容、JSON 基础类型。
- `sqflite_repository_test.dart`(7)：CRUD/upsert/用户隔离/removeBook 级联清理。
- `persistence_integration_test.dart`(6)：进度恢复/跨字号不跳页/书签同步/设置持久化/纯内存降级/多用户隔离。

## 章节正文缓存（2026-06-29 实现，二次打开秒开）

**问题**：example 打开书每次都转圈——`fetchChapters` 一次 `POST /api/novel/chapter` 拉全书所有章节正文（几百 KB~几 MB），等这个大请求返回才能渲染。原生 legado 快是因为章节正文缓存在本地 DB，二次打开读本地几乎 0 延迟。

**后端能力（已实测确认）**：只有两个接口可用——
- `GET /api/novel/index` 返回**书库列表**（每本 `{id,title,author,desc,thumb}`），**不含章节目录**。
- `POST /api/novel/chapter`（body `{id}`）**一次返回全书所有章节完整正文**，无法只拉目录或单章。
- `/api/novel/info|detail|show|catalog` 均不存在（404）。

故无法做按需拉取/骨架先显（需后端配合）。本次只做**正文本地缓存**：首次打开仍等全网，**二次起秒开**。

### 缓存表设计
- 新表 `chapter_contents(book_id, chapter_index, title, content, fetched_at, PK(book_id,chapter_index))`，schema 升 **v2**（`_onUpgrade` 用 `IF NOT EXISTS` 增量建表，老库平滑升级，已有数据不动）。
- **不走 userId 隔离**：章节正文是书的内容，与用户无关（同书 A 用户第 N 章 = B 用户的），仅按 `bookId + chapterIndex` 复合键存，避免冗余。progress/bookmarks 仍按用户隔离。
- **清理**：`removeBook(bookId)` 时按 `book_id` 级联清缓存（删书架即清缓存）。
- **无 TTL/失效检测**：连载新书出新章时本地会旧。本轮不做，留待后端有「最后章数/更新时间」接口时再做。

### Repository 接口（3 个原语，宿主组合「本地优先」策略）
- `getBookChapters(bookId)` — 二次打开主路径，一次拿全书已缓存章节（按 index 升序）。
- `getCachedChapter(bookId, index)` — 单章查询（预取/校验用）。
- `saveChapterContent(bookId, index, title, content)` — 网络下完后回填（upsert）。
- 新模型 `CachedChapter { bookId, chapterIndex, title, content }`（`lib/src/core/storage/cached_chapter.dart`）。

### Controller 不动
controller 仍读 `book.chapters[i].content`。「本地优先」逻辑放 example（`_fetchChaptersLocalFirst`）：先 `getBookChapters` 本地查 → 命中即渲染（秒开）→ 未命中走网络 → 逐章回填 `saveChapterContent`。包内 repository 只提供存/取原语，保持抽象层纯净，宿主可选用或不用缓存。

### 测试（sqflite_repository_test.dart 新增 3 用例）
- `saveChapterContent/getBookChapters` 往返 + 升序 + 按书隔离。
- `getCachedChapter` 单章 + upsert 覆盖。
- `removeBook` 级联清章节缓存。全 62 测试通过。

## 仿真翻页（simulation，2026-07-03 MVP 实现）

学习原生 legado `SimulationPageDelegate.kt`（612 行）做的贝塞尔卷曲翻页。分阶段实现，本次为 **MVP（~80% 观感）**。

### 文件结构
- `lib/src/reader/page_animations/simulation_geometry.dart` — **纯 Dart 几何核心**（无 Canvas 依赖，可单测）。`SimGeometry.calcCornerXY/getCross/calcPoints` 逐行翻译原生算法。
- `lib/src/reader/page_animations/simulation_painter.dart` — `SimulationPainter extends CustomPainter`，4 层绘制。
- `lib/src/reader/widgets/reader_view.dart` — 加模式分发 + 仿真手势 + onAnimStart 终点计算。
- `test/simulation_geometry_test.dart` — 几何核心 23 个单测。

### 核心算法（务必记住）
**几何灵魂**：touch 到 corner 的**垂直平分线作折痕**，折痕与 corner 两条邻边（水平 y=cornerY、垂直 x=cornerX）的交点 = 两段二次贝塞尔的控制点。`calcPoints` 输出 start/control/vertex/end 共 8 个点（vertex 是贝塞尔 t=0.5 处 = `(start+2·control+end)/4`），painter 用这些点构造 path0（卷曲边封闭路径）做裁剪。

**4 层绘制顺序**（从底到顶，对齐原生 onDraw NEXT 247-268）：
1. `drawCurrentPageArea` — 翻起页裁掉翻起区（差集裁剪）露出下层
2. `drawNextPageAreaAndShadow` — 底层目标页 + 卷曲投影（backShadow 渐变）
3. `drawCurrentBackArea` — 翻起页背面

### MVP 已做 vs 未做（第二阶段）
- ✅ 贝塞尔几何 + 边界钳制（原生 543-574 镜像修正）+ 除零保护
- ✅ 当前页裁剪 + 下一页 + 背面投影 + 折痕阴影 + 背面铺背景色
- ❌ **背面 Householder 反射矩阵**（背面镜像文字，"像纸"的灵魂，留第二阶段）
- ❌ 正面高光阴影（`drawCurrentPageShadow` 4 个 frontShadow 渐变）
- ❌ ColorMatrix 滤镜（仅反射 bitmap 时需要）

### ⚠️ 与原生的关键差异（踩过的坑）
0. **`control1X` 补除零保护（线上崩溃修复）**：原生 `calcPoints` 算 `control1.x = middleX - (cornerY-middleY)²/(cornerX-middleX)` **无除零保护**。当 `touchX == cornerX`（如点击翻页把初始 touch 精确设在 corner 上、或手指落在角柱正上方）时 `middleX == cornerX` → 分母 0 → Infinity/NaN 传染到 start1/end1/vertex1/degrees → Canvas 抛 `Offset argument contained a NaN value`。Android 静默吸收 NaN 故原生不崩，Flutter `Path` 严格会崩。修复：抽 `_control1X` 辅助函数，分母 0 时用 0.1（对齐已有的 `_control2Y` 保护策略）。回归测试 `touchX == cornerX 不产生 NaN` 锁定。
1. **`getCross` 改用参数化行列式法**：原生 `y=ax+b` 公式遇到竖直线（touchX == control1.x 时）会除零 → NaN。Flutter `Path` 对 NaN 比 Android 严格（会崩），故改用 `P1 + t·(P2-P1) = P3 + u·(P4-P3)` 的 2×2 行列式解，对竖直线鲁棒。非竖直场景与原生数学等价。测试里"水平线×竖直线交于 (3,5)"专门锁定此修复。
2. **Flutter `Canvas.clipPath` 无 `ClipOp.difference`**（仅 `clipRect` 支持 ClipOp）。原生 `clipOutPath(path0)` 的差集裁剪，在 Flutter 用 `Path.combine(PathOperation.difference, 全屏矩形, path0)` 预算"全屏减翻起区"再 intersect-clip。
3. **`dart:math` 无 `hypot`**（Kotlin `math.hypot`），用 `sqrt(x*x+y*y)` 替代。
4. **位图截图用 `RepaintBoundary.toImage`**（原生 `View.draw(Canvas)` 离屏截图）。三页 RepaintBoundary 加 GlobalKey，方向确定时 fire-and-forget 异步 `toImage`，完成前 painter 走纯色降级（progress≈0 卷曲极小，肉眼无感）。
5. **颜色换算**：原生 Kotlin Int（如 `-0xeeeeef`=`0xFF111111`、`0x333333`=`0x00333333`、`-0x4fcccccd`=`0xB0333333`）→ Flutter `0xAARRGGBB`，painter 顶部集中定义。

### reader_view 仿真状态机接线（关键设计点）
- 仿真模式三页 Stack **始终挂载**（供截图），翻页进行中（`_animDir != none`）在其上覆盖一层 `CustomPaint` 由 painter 接管卷曲绘制；静止态不覆盖（避免无谓重绘）。
- `_simTouch`（二维，含 Y 锁边）/ `_simCorner` / `_simCur/Next/Prev`（ui.Image 缓存）/ `_simAnimFrom/To`（动画起止 touch 点）。
- **touchY 锁边**（对齐原生 onTouch MOVE 173-183）：startY 在中部（H/3~2H/3）或 PREV → 锁到底边 viewH；startY 在上 1/3~1/2 且 NEXT → 锁到顶 1。
- **onAnimStart 终点计算**（对齐原生 208-238）：shouldCommit 推到对边，否则拉回 corner 同侧。用 `_pageAnim` + `_onSimAnimTick` 每帧插值 `_simTouch`。
- **图片 dispose 时序**：`_resetAnimState`（停动画）必须在 `_resetSimState`（dispose ui.Image）**之前**调用，否则动画进行中 dispose painter 正在用的 image。
- **点击翻页（`_turnByAnim`）**：仿真模式从对应角（NEXT 右下 / PREV 左下）起翻，先截图再下一帧启动落地动画。
- **手势状态机骨架完全复用**：`_animDir`/`_isCancel`/`_animGen`/`_deferredCommit`/`peekNext`/`commitTurn` 零改动，仿真只替换"如何把 progress 画出来"。
- slide/none 模式行为不变（仿真分支只在 `pageAnimMode == simulation` 进入）。

### 测试覆盖（23 用例全过，全套 108 测试通过）
`simulation_geometry_test.dart`：calcCornerXY 四角 + getCross（含竖直线鲁棒/平行退化）+ calcPoints 结构不变量（控制点落 corner 邻边、vertex 公式、touchToCornerDis、degrees）+ 除零保护 + 边界钳制 + 四角覆盖。几何核心不依赖渲染即可验证"形状对不对"。

## 滑动翻页（slide）防越界修复（2026-07-06）

**问题**：slide 模式下手指先左滑（锁定 NEXT）不松手、再回拉越过起点滑到右边缘时，动画方向变反——页面继续按 NEXT 公式（往左移）画一个 `|_dragOffset|/width` 的大进度，视觉上反方向滑动。

**根因**：`_animDir` 在 8dp touch slop 时锁定一次，整个手势期间永不翻转（对齐原生）；而 `_currentProgress` / `_onDragEnd.fromProgress` 用 `_dragOffset.abs()` 算进度，**丢符号**。当用户回拉让 `_dragOffset` 变号（NEXT 时变正 / PREV 时变负），锁定的方向与位移符号矛盾 → 渲染用锁定方向画反向进度。

**对齐原生**：legado `SlidePageDelegate.onDraw:36-39` 有显式防越界——
```kotlin
val offsetX = touchX - startX
if ((mDirection == NEXT && offsetX > 0) || (mDirection == PREV && offsetX < 0)) return
```
方向锁定后手指越过起点到相反侧，**直接 return 不绘制**，视觉停留原位；松手 `onAnimStart` 走 `isCancel` 分支回弹。legado 的设计是"方向一旦锁定，想反向必须松手重来"。

**修复**（`reader_view.dart`，新增 `_dragProgress(double width)` helper）：
- 拖拽阶段位移符号与 `_animDir` 相反时（NEXT 且 `_dragOffset>0` / PREV 且 `<0`）返回 **0**（对齐原生 return 不绘制 → Flutter 用 progress=0 让三页都停在静止偏移）。
- `_currentProgress` 拖拽分支 + `_onDragEnd.fromProgress` 都改用 `_dragProgress`（两处同源）。
- 越界状态松手时：`fromProgress=0`、`_isCancel=true`、`shouldCommit=false`、`toProgress=0`，`(0-0).abs()<0.001` 短路直接 `_resetAnimState`，无多余动画。视觉上"页面本就停在原位，松手无事发生"，与原生一致。

**为什么不让 `_animDir` 跟着翻转**：legado 设计如此（锁定后不翻转）；且中途翻转会让已预热的 peek 页（next/prev）与当前手势错配，动画起止/commit 目标都要重算。防越界 → progress=0 是最小改动且语义自洽。

## 滚动翻页（scroll，2026-07-07 实现）

对齐原生 legado `ScrollPageDelegate` + `ContentTextView.scroll`。**严格采用原生 pageOffset 模型**（单一 offset + 边界翻章修正），非旧 `912604b` 的 SingleChildScrollView 三章拼接长列方案。

### ⚠️ 历史脉络（推翻旧记录）
- 旧分支曾有 `912604b`(实现) / `618c873`(自动翻章) / `af73c17`(无缝切章) 三个 scroll commit，用的是 SingleChildScrollView + 三章全页拼超长列 + jumpTo 修正 offset 的方案。**该实现在 `905931d`（2026-06-26 目录迁移 `lib/src/widgets/` → `lib/src/reader/widgets/`）被整体删除**（连同 cover/slide/simulation_animation 等共 7 文件 1051 行）。此后 master 一直未重建 scroll，选中后 fallback 到 slide 水平滑动。
- 本次（2026-07-07）从零重写，改用原生 pageOffset 模型，避免旧方案 offset↔page 换算脆弱、跨章抖动的问题。

### 核心模型（务必记住）
**单一状态变量 `pageOffset ∈ [-pageHeight, 0]`**：
- `0` = 当前页顶部对齐视口顶（显示页首）
- `-pageHeight` = 当前页底部对齐视口底（显示页尾）
- `> 0` = 内容下方露出（需要上一页）
- `< -pageHeight` = 上方露出（需要下一页）

手指拖拽 / fling 惯性 / 点击翻页 都换算成 dy 喂给 `applyDragDelta(dy)`，它累加 `pageOffset`，越过 `[-pageHeight, 0]` 边界即翻页/翻章并修正偏移（保持视觉连续），到首/末页钳制 + 中止 fling（回弹）。对齐原生 `ContentTextView.scroll(mOffset)`（ContentTextView.kt:145-177）。

### 文件结构
- `lib/src/reader/page_animations/scroll_mode_handler.dart` — **核心 `ScrollModeHandler extends ChangeNotifier`**，持有 pageOffset + 当前章页 + 相邻章预取 + fling/pageTurn 两个 AnimationController。
- `lib/src/reader/widgets/reader_view.dart` — scroll 手势分支（`_onDragUpdate` 读 `delta.dy` / `_onDragEnd` 启 fling）+ `_buildScrollContent`（chrome 浮层 + 正文偏移拼接）+ `_turnByAnim` scroll 分支 + 生命周期。

### 关键算法
1. **`applyDragDelta(dy)`**（循环消化越界）：`pageOffset += dy`；首章首页 `>0` 钳 0 + abort；`>0`（有上一页）翻上一页/章，`offset -= pageHeight`；`< -pageHeight`（有下一页）翻下一页/章，`offset += pageHeight`；末页无下一页钳 `-pageHeight`。**循环**（非 early-return）：单次大 dy（fling 大步长）可能越过整页，循环翻到 offset 落回 `[-pageHeight, 0]`；guard 限 `(总章×每章页数)+4` 次防死循环。
2. **fling 惯性**（`onFlingStart(velocityY)`）：`ClampingScrollSimulation(position:0, velocity:velocityY)`，用**真实流逝时间**（`_fling.lastElapsedDuration`）驱动，每帧取 `sim.x(tSec)` 喂 `applyDragDelta`。⚠️ 不能用 AnimationController 归一化 value 当 simulation 自变量（摩擦衰减曲线会失真）。碰边界 `applyDragDelta` 内 `_abortAnim` 停 fling。
3. **点击翻页**（`turnByClick(next)`）：滚动 ±(pageHeight+0.5)，easeOutCubic 平滑（duration = 300ms × 距离/页高，clamp 120~300）。**多滚 0.5px** 确保 offset 严格越过 `-pageHeight` 边界（`applyDragDelta` 用严格 `<` 判定，恰好 `== -pageHeight` 不翻页 = 显示页尾）。无动画模式直接跳。⚠️ 未沿用原生「保留最后一行」(calcNextPageOffset)——那是连续画布下的优化，Flutter 离散分页模型下整页翻语义更清晰、与 slide/sim 一致。
4. **进度同步静默化**（核心性能）：滚动中 handler 局部 `setState`（仅重绘正文偏移 + chrome 文本），**不 notify controller**（避免整树 rebuild 卡顿）。章页码变化走 `controller.setCurrentPageSilent`（不 notify 不落盘），仅 ScrollEnd 时 `scheduleProgressSave` 防抖落盘。对齐原生 `ContentTextView.scroll` 只改 `pageOffset` + 局部 `postInvalidate`，不触发 `ReadBook.callback` 全量刷新。

### 渲染（对齐原生 `ContentTextView.drawPage` + `relativeOffset`）
- **正文层 `_buildScrollContent`**：`ClipRect(Stack)` 用 `Positioned(top: ...)` 拼接三页：prev(上一章末页) top = `offset - pageHeight`、cur top = `offset`、next(下一章首页) top = `offset + pageHeight`。每页用 `pv.PageView(showChrome:false)` 纯正文（`showChrome:false` 是本次新增的真正生效路径——只画正文行，无页眉页脚/分隔线/SafeArea）。
- **chrome 浮层 `_buildScrollChrome`**（固定不随滚动）：⚠️ **不在 `_buildScrollContent` 内部**，而在 `reader_view.build()` 的外层 GestureDetector Stack 里作为 `_buildPageContent()` 的**同级** `Positioned.fill` 挂载。因 `_buildPageContent` 拿到的 LayoutBuilder 约束已扣除 `nonContentHeight`(chrome 高)，若 chrome 浮层画在内容区内部会与正文重叠。外层挂载让 chrome 覆盖在完整视口(含状态栏区)，对齐原生 chrome 在 PageView 父布局。`IgnorePointer` 包裹不挡手势。复用 `pv.PageView(showHeaderOnly/showFooterOnly)`，页码/进度取 handler 当前可见页(滚动中实时变)，对齐原生 `setProgress` 每帧更新。

### ⚠️ 与原生/旧实现的关键差异
1. **chrome 浮层 vs 连续画布**：原生把 cur/next/nextPlus 三个逻辑页画在**同一个 ContentTextView**（drawPage 用 relativeOffset 拼接），chrome 在父 PageView 固定。Flutter 端正文用 `Positioned` 拼接三页（非同一画布），chrome 用 Positioned 浮层。视觉等价。
2. **点击翻页**：原生「保留最后一行」(calcNextPageOffset) 在连续画布下让「本页底 + 下页首同框」；Flutter 离散分页改为整页翻（±pageHeight），与 slide/sim 行为一致。
3. **`pv.PageView.showChrome`**：此前是死字段（声明未消费），本次让它生效——`showChrome:false` 跳过 header/footer/分隔线/SafeArea，纯正文（scroll 模式正文页复用）。其他模式仍 `showChrome:true`。
4. **静默进度同步**：原生无此问题（ContentTextView 不触发全量刷新）；Flutter 因 controller notify 会 rebuild 整树，故加 `setCurrentPageSilent` + ScrollEnd 才落盘。

### 测试（`test/scroll_mode_test.dart`，11 用例）
pageOffset 初始 0 / 章内滚不翻 / 越底翻下页 / 越顶翻上页 / 首章首页钳 0 / 章末翻下一章 / 下一章首页翻回上一章末页 / 末章末页钳制不翻 / 点击翻页推进 / setCurrentPageSilent 不 notify / scheduleProgressSave 不抛。全套 135 测试通过。

### 不做（本轮排除）
- ❌ 水平手势翻页（scroll 模式纯垂直；点击区域翻页保留）。
- ❌ 长截图模式（原生 `longScreenshot` 分支，无宿主场景）。
- ❌ autoPager 自动翻页联动（本包无此功能）。

## 覆盖翻页（cover，2026-07-13 实现）

对齐原生 legado `CoverPageDelegate.kt`（117 行）。与 slide（`SlidePageDelegate.kt`，64 行）共享 `HorizontalPageDelegate` 全部手势/方向锁定/动画逻辑，**唯一差异在 `onDraw` 的绘制方式**。

### 核心模型（务必记住）

**cover 与 slide 的本质区别一句话**：slide 让 cur 和 next/prev **都**按 progress 平移；cover 只让**覆盖方**平移，**被覆盖方静止不动**。

- **NEXT**：cur 像幕布向左滑出（`curX = -p·W`），next 静止在原位（`nextX = 0`）被 cur 覆盖，cur 滑走逐渐露出 next。
- **PREV**：cur 静止（`curX = 0`），prev 像推拉门从右滑入（`prevX = (p-1)·W`）覆盖 cur。

对应原生：`CoverPageDelegate.onDraw` NEXT 用 `withClip(W+offsetX, 0, W, H)` 让 next 静止露出右边缘 + `translate(distanceX-W)` 让 cur 滑出。Flutter 无需 clip，靠 Stack z-order + Transform 等价实现。

### 偏移矩阵（推导见 `cover_layout.dart` 顶部注释）

| 状态 | cur.x | next.x | prev.x | Stack 层级(底→顶) |
|---|---|---|---|---|
| none | 0 | +width(屏外) | -width(屏外) | [next, cur, prev] |
| NEXT(p) | -p·w(滑出) | 0(静止,被覆盖) | -width(屏外) | [next, cur, prev](cur 在 next 之上) |
| PREV(p) | 0(静止) | +width(屏外) | (p-1)·w(滑入) | [next, cur, prev](prev 在 cur 之上) |

⚠️ **cover 的 Stack children 顺序是 `[next, cur, prev]`**，与 slide 的 `[prev, cur, next]` 不同。这是 cover 的核心：NEXT 时 cur 要在 next 之上（盖住 next），PREV 时 prev 要在 cur 之上（覆盖 cur）。none 态 next/prev 都屏外，顺序变化不可见；模式切换时各页有稳定 `ValueKey`，element 按 key 复用不重建。

### 阴影（对齐原生 `addShadow`）

一层渐变阴影画在覆盖移动页的**后缘（右边缘）**：
- NEXT：阴影 left = cur 右边缘 = `(1-p)·W`，向右 15dp 渐淡（覆盖在露出的 next 上）。
- PREV：阴影 left = prev 右边缘 = `p·W`，向右 15dp 渐淡（覆盖在露出的 cur 上）。
- 起止点（p=0/1）不画（对齐原生 `addShadow` 的 `if (left == 0f) return`）。
- 颜色 `0x66111111`→透明（对齐原生 `CoverPageDelegate.kt:15`）。
- 宽度 15 逻辑像素（原生 30 是物理像素，xxhdpi ≈ 10dp；Flutter 取 15dp 视觉接近）。

### 文件结构
- `lib/src/reader/page_animations/cover_layout.dart` — **纯函数 `calcCoverOffsets`**（无 Canvas 依赖，可单测）。返回 `CoverOffsets(curX, nextX, prevX, shadowLeft)`。常量 `kCoverShadowWidth=15` / `kCoverShadowColorARGB=0x66111111`。
- `lib/src/reader/widgets/reader_view.dart` `_buildPagedContent` — cover 分支（约 20 行）：调 `calcCoverOffsets` 算偏移 + `[next,cur,prev]` 层级 + 阴影层 `_buildCoverShadow`。

### 零改动复用（关键，cover 之所以简单）
- **整个手势状态机**：`_animDir/_isCancel/_isDragging/_dragOffset/_animGen` —— cover 与 slide 用**完全相同**的 progress 概念，只是渲染层偏移公式不同。
- **`_dragProgress`/`_currentProgress`**：cover 复用 slide 同款 progress（方向锁定 + 防越界）。
- **`_onDragStart`/`_onDragUpdate`/`_onDragEnd`**：cover 自动落入 slide 的 default 路径（没有 sim/scroll/none 的特殊分支）。
- **`_turnByAnim`**：cover 走 slide 路径（`_startPageAnim(from:0, to:1)`）。
- **`_startPageAnim`/`_onPageAnimStatus`**：cover 走 PostFrame 延迟 commit（与 slide/none 一致；sim 才立即 commit）。
- **peek 缓存/`_resolveTarget`/`_deferredCommit`**：完全复用。
- **`PageAnimMode.cover` 枚举 + UI 入口「覆盖」按钮 + 序列化 codec**：本轮之前已预留，无需改动。

### 为什么 cover 比 simulation 简单得多
cover 不需要：截图（RepaintBoundary.toImage）、CustomPainter、几何核心（贝塞尔曲线）、异步时序管理。纯 `Transform.translate` 偏移 + 一层渐变 Container 即可。

### 测试（`test/cover_offset_test.dart`，18 用例）
none 态三页归位 / none 与 slide 一致（过渡连续）/ NEXT 各进度点偏移 / NEXT cover 与 slide 差异（next 不平移）/ PREV 各进度点偏移 / PREV cover 与 slide 差异（cur 不平移）/ 阴影 NEXT/PREV 位置正确 / 阴影起止点不画 / 边界（width=0/负/progress 超界不崩）/ 过渡连续性（none→NEXT/PREV p=0 偏移连续）。全套 168 测试通过。

## 待办（先不做动画）

- ~~`reader_view.dart` import 的 `page_animations/*.dart`（6个文件）整个目录缺失，根包当前无法编译。`flutter analyze` 的 38 个 error 全部源于此~~。**2026-06-29 复核**：根包 `flutter analyze` 现仅剩 2 个 info（`unnecessary_library_name` + `last_page_truncation_test.dart` 的 `prefer_interpolation`），0 error 0 warning，可整体编译。page_animations 缺失问题已不存在（reader_view 不再 import 该目录，或之前的提交已处理）。如确需补动画目录，从零开始即可。
- ~~cover/scroll 待实现~~。**2026-07-13 更新**：cover（见上「覆盖翻页」节）与 scroll 均已实现。五种翻页模式（cover/slide/simulation/scroll/none）全部完成。

## 键盘 viewInsets 引发的 rebuild 卡顿（2026-07-03 修复，commit 78d289a）

**场景**：目录页搜索框弹键盘 → 点左上角返回 → 阅读页卡顿 ~10 帧。

**根因（重要，别再只盯 _rePaginate）**：键盘收起时 `viewInsets.bottom` 在多帧里连续变化（日志实测 743→746→747→748）。`Scaffold` 默认 `resizeToAvoidBottomInset: true` 每帧重算 body 高度 → `LayoutBuilder` 每帧拿到不同 constraints → **整个 reader 子树每帧 rebuild + relayout**（GestureDetector/Stack/CustomPainter/peek 缓存等累加开销），持续多帧卡顿。

⚠️ 这条卡顿链**不经过排版**——controller 侧 `updatePageSize` 加了防抖挡住 `_rePaginate`（~170ms/次）后日志无 `paginate` 行，但卡顿依旧。因为 rebuild/relayout 本身就吃帧，重排只是其中最重的一环。**修 rebuild 必须从源头切断 viewInsets 传导**，光防抖重排无效。

**对照 legado**：目录/搜索是独立 `Activity`（`ReadBookActivity.kt:1191-1212` 用 ActivityResultContract 启动 `TocActivity`/`SearchContentActivity`），键盘弹在另一 window，底层阅读 View 根本不被 resize，从源头无 rebuild 链。Flutter 同 Navigator 栈无 Activity 隔离。

**修复（两层，从源头切断）**：
- **宿主层** `example/lib/main.dart`：`Scaffold(resizeToAvoidBottomInset: false)`，键盘收起时 body 高度不变。
- **包内层** `lib/src/reader/widgets/reader_view.dart`：`MediaQuery.removeViewInsets(removeBottom: true)` 包住 LayoutBuilder 子树。无论宿主怎么配，reader 内部子树都看到「无键盘」的稳定布局环境——包的健壮性，不依赖宿主正确配置。
- **兜底**（对齐 `ChapterProvider.upViewSize` 的 300ms 延迟 + 反弹取消）：`reading_controller.updatePageSize` 改防抖——尺寸变化延迟 300ms 执行，期间反弹回原值则取消；首次进入（`_pageSize == Size.zero`，loadBook 关键路径）同步不延迟。应对真正改变尺寸的场景（旋转/分屏/系统栏显隐）的连续帧，是 rebuild 链之外的额外保险。

**语义**：正文被键盘/搜索框遮挡时本就无需适配其高度，移除 viewInsets 不影响视觉。`SearchMenu` 当前用 `MediaQuery.padding`（系统栏）定位、不消费 viewInsets，故不受 `removeViewInsets` 影响。

## 「首次挂载卡顿」预 layout 预热模式（2026-07-03，commit 8f5aeb9）

**场景**：目录页（`ChapterListPage`）首次点搜索按钮唤起键盘，比第二次慢 ~90ms（124ms vs 31ms）。**无转场动画可掩盖**（在当前页内切换 TabBar↔TextField），卡顿赤裸可见。

**根因（用 Stopwatch 打点定位，别猜）**：
- `[PERF] ChapterListPage.build: 3ms`、`_ChapterListView.build: 0ms` → **build 不是瓶颈**。
- `enterSearch→PostFrame: 124ms` → 瓶颈全在 build 之后的 **layout**：TextField 内部 `EditableText` 的首次 layout（`RenderEditable` 初始化、光标几何、文本测量）。第二次复用 RenderObject 故快（31ms）。
- 教训：`EditableText` 这类有自定义 `RenderObject` 的 widget，**首次 layout 开销远大于首次 build**，性能分析必须分 build / layout 两段打点。

**对照 legado**（`TocActivity.kt:70-106`）：`SearchView` 作为 Toolbar menu actionView（`showAsAction="always"`），在 `onCreateOptionsMenu`（Activity 启动早期）就 inflate 好——用户一打开目录页看到的放大镜图标就是已 inflate 的 SearchView。点搜索只切 `isIconified(true→false)` + requestFocus，**无首次 inflate/layout**。这叫「预 inflate」。⚠️ 不是靠转场动画掩盖（书内全文搜索那条线 `SearchContentActivity` 才是独立 Activity + 转场，别和目录页混淆）。

**修复（对齐 legado 预 inflate 的 Flutter 等价物）**：
- title 用 `Stack` 叠放 `TabBar` 与 `TextField`，两者**都常驻挂载**，用 `Visibility` 切显隐。
- 关键：`Visibility(maintainState: true, maintainSize: true, maintainAnimation: true)`。三个 maintain 全开 = 保留 `Element`、保留 `RenderObject`、保留已算好的 **layout**、保留动画 ticker。EditableText 的首次 layout 在页面进入时（用户无感）就完成，点搜索时无首次 layout 开销。
- `_enterSearch`：`setState` 后用 `PostFrame` 重新 `requestFocus`——因为 `Visibility(visible:false)` 的 widget 无法获焦，切到 visible 后下一帧才能唤起键盘。

**踩过的坑（避免重复）**：
- `Offstage` **无效**：`Offstage` 的 widget 只 build，**跳过 layout 和 paint**。EditableText 没完成首次 layout，预热白做（实测 155→108 只省了 build 部分，layout 仍要补）。要预 layout 必须 `Visibility` 三 maintain 全开。
- `Visibility` 不带 maintain 参数 = 等同于条件挂载，也无效。
- `Opacity(opacity:0)` 理论上能预 layout（参与 layout/paint 但透明），但比 `Visibility` maintain 更重（真的 paint 了），不推荐。

**可复用模式**：任何「首次显示某重量级 widget（含自定义 RenderObject，如 EditableText/CustomPaint/图表）卡顿」的场景，都可考虑：
1. 先打点确认是 build 还是 layout 慢（`Stopwatch` 在 build 起止 + PostFrame 两段）。
2. 若是首次 layout 慢，用 `Visibility(maintainState/Size/Animation: true)` 把它常驻树里预 layout，切显隐时复用已有 RenderObject。
3. 代价：常驻一个隐藏 widget 的内存与 layout 开销，权衡是否值得（低频/轻量 widget 不值得）。

## SmartDialog 弹窗里别用 InkWell/InkResponse 做点击反馈（2026-07-13，commit bcb1adb）

**结论先行**：所有用 `SmartDialog.show()` 挂载的弹窗（_StyleDialog / _PaddingConfigDialog / _TipConfigDialog / _showOptionList / _PresetEditorDialog 等全系列）里，**不要用 InkWell/InkResponse/IconButton 做点击反馈**。改用 `GestureDetector` + 自管理按下态 + `AnimatedOpacity`/`AnimatedScale` 手画反馈。`DetailSeekBar` 的 ± 按钮、`_showOptionList` 的列表项 InkWell 都是这类。

**根因（5 轮诊断 + Flutter 源码定位，别再走一遍）**：
1. **SmartDialog 用独立 Overlay 渲染弹窗，脱离 MaterialApp 的 Material 树**。`InkResponse`/`InkWell` 的 ink feature 画在 `Material.of(context)` 找到的最近祖先 `_RenderInkFeatures` 上；SmartDialog 弹窗的 widget 树里**没有 Material 祖先**（诊断版去掉自套 Material → 完全无反馈，实证）。
2. **自套透明 `Material` 是必须的，但不可靠**：
   - `Material` 内部的 `_RenderInkFeatures.paint`（`material.dart:627`）画所有 ink feature 前会 `canvas.clipRect(Offset.zero & size)` —— **用 Material 自身 size 矩形裁剪所有 ink**。所以透明 Material 的 size 必须是正方形且 ≥ splash 直径，否则圆形 splash 被矩形裁成方。
   - 即使 Material size 对了，`InkResponse` 会**同时渲染 splash（圆）+ highlight（默认跟随 child 边界，常被裁成方）两层**，叠加 = 用户报的"圆+方两层"。
   - 想用 `highlightColor: Colors.transparent` 关 highlight 留 splash → 不稳定（主题 `overlayColor` 优先级更高会覆盖，且 overlayColor 同时影响 splash 无法单独控制）。
   - 想用 `overlayColor: WidgetStatePropertyAll(transparent)` 关一切 → **splash 也一起被关**（`overlayColor` 优先级高于 `splashColor`，见 `ink_well.dart:1095`）。
3. **结论**：ink 机制在这个脱离 Material 树的上下文里**根本不可靠**，再怎么调参数都得不到干净的单层圆形 ripple。

**正确做法**（`detail_seek_bar.dart` 的 `_RippleButton` 是参考实现）：
```dart
class _RippleButton extends StatefulWidget { /* icon, onTap */ }
class _RippleButtonState extends State<_RippleButton> {
  bool _pressed = false;
  Widget build(_) => GestureDetector(
    behavior: HitTestBehavior.opaque,  // 关键: 透明区也能点
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
    onTapCancel: () => setState(() => _pressed = false),
    child: Stack(alignment: center, children: [
      AnimatedOpacity(opacity: _pressed ? 1 : 0, duration: 120ms,
        child: Container(圆形背景 black12)),  // 手画的 ripple
      widget.icon,
    ]),
  );
}
```
要点：
- `GestureDetector` + `onTapDown/onTapUp/onTapCancel` 自管理 `_pressed`，不依赖 ink。
- `AnimatedOpacity` + `Container(decoration: circle)` 手画圆形背景，完全可控，不会有"两层"。
- `behavior: HitTestBehavior.opaque` 让透明 padding 区也能接收点击（否则只有图标像素可点）。
- 想要"扩散动画"可用 `AnimatedContainer` 让圆半径从 0 动画到目标值；当前简化为淡入淡出已接近原生 borderless ripple 观感。

**判断是否需要这套方案的快速检查**：widget 是否在 `SmartDialog.show(builder:)` 的回调里挂载？是 → 走手画；否（在 Scaffold/Material 常规树里）→ InkWell/InkResponse 正常用。

**原生对照**：legado 在 `view_detail_seek_bar.xml:24,41` 用 `?android:attr/selectableItemBackgroundBorderless`（无边界圆形涟漪），那是 Android framework 提供的、画在根 DecorView 上的机制，不依赖 view 自身有特殊背景。Flutter 没有等价的"画在根上"的 ripple，ink 必须挂在 Material 上 —— 这是两个平台机制的差异，SmartDialog 弹窗正好踩中这个差异。

