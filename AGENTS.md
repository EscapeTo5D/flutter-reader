# 项目记忆 (AGENTS.md)

本文件存放 ZCode 跨会话需要记住的项目级信息。新会话自动读取。

## 项目概况

- **flutter_reader**: 基于 legado（开源阅读 App）做的 Flutter 重构，是一个文本阅读器 widget 包。
- 包代码在 `lib/`，运行示例 app 在 `example/`。
- 阅读排版配置模型: `lib/src/core/models/reading_settings.dart`（对应原生 `Config` / `ReadTipConfig`）。注意：2026-06-26 远程重构后文件已移到 `core/` 和 `reader/` 下。

## ⚠️ 关于"翻页架构重构"那条线（已删除）

历史曾存在分支 `backup/pre-refactor-2026-06-26`（PageDelegate 基类 + NoAnimPageDelegate + 把 `scroll_mode_handler.dart` 迁出 `page_animations/` + 整套 legado 技术文档 docs/legado_reader/ 00~11 章）。该分支含 10 个未合并到 master 的提交（`7a89790`~`8967075`，含 page_delegates 架构、padding/高度修复、delegate 文档），master 走的是 isolate 排版优化路线，未接续这条线。
- **该分支已于 2026-07-02 用 `git branch -D` 强制删除（本地，含 10 个未合并提交，不可恢复）。** 删除前从未 push 到远程，故远程无需清理。
- ⚠️ 上一版 AGENTS.md 曾写"该分支已于 2026-06-29 前被删除，本地/远程/reflog 均无残留"——**那条记录有误**，分支实际一直存活到 2026-07-02 才删。
- master 上的 `912604b feat: implement scroll page mode aligned with legado ScrollPageDelegate` 是 master 自身提交，与该分支无关。
- 如未来要重做"翻页架构重构"，只能从零开始，无法从那个分支接续。
- 另：同日还删了已完全合并的 `feat/perf-chapter-loading-isolate`（`git branch -d`，零风险）。现本地仅剩 `master`。

## 原生项目 (legado) 位置 ⚠️ 重要

- 路径: **`D:/GitHub/legado`**（不是 `D:/hong_projects` 下！用户曾口误为 `D:/hong_projrct`）
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
- 默认 footer: 左=bookName, 中=none, 右=pageAndTotal

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
  （旧实现硬编码 `+6` 即 top2+bottom4, 现改为读 `footerTop/footerBottom` 字段, 默认 6/6）
- 分隔线 0.5: 跟随各自 show + showHeaderDivider/showFooterDivider

**设计约定（对齐原生 legado）**：
- 翻页模式（含 scroll）不影响 chrome 显隐，只改变翻页方式。scroll 模式也显示页眉页脚。
- 页眉页脚整体显隐只看 `hidden` 字段；三槽全 none 时页脚仍占位（对齐原生"容器始终在"）。

## 设置弹窗全量对齐原生（2026-07-03）

对齐原生 `ReadStyleDialog` + `dialog_read_book_style.xml` + `PaddingConfigDialog`，分 4 个工作流：

### WS1 视觉对齐（commit b632d74）
- **去背景遮罩**：`_showStyleDialog` 的 `maskColor` 从 50% 黑改 `Colors.transparent`，对齐原生 `dimAmount=0.0f`（阅读页正文完全可见，不被半透明遮罩盖）。
- **去顶部圆角**：弹窗 Container 去掉 `borderRadius`，对齐原生无圆角（顶部直角贴屏底）。
- **字重文字** `中/粗/细`→`N/B/L`：对齐原生 `strings.xml font_weight_text="N/B/L"`（`TextFontWeightConverter` 显示）。
- **预设选中边框**：宽度恒 1dp，仅 `borderColor` 从 textColor 变 accentColor（旧实现选中变宽 1→2px，错）。对齐原生 `CircleImageView` border 宽度恒定。
- **背景色** `#FFFFFF`→`#FAFAFA`：对齐原生 `md_grey_50`（原生运行时被主题 `bottomBackground` 覆盖，本包无主题系统故取静态值）。

### WS4 共享排版 shareLayout（commit 4a334f1）
- `ReadingSettings` 加 `bool shareLayout`（默认 false）+ codec 字段。
- **Flutter 语义重定义**（原生「跨样式槽共享」在扁平配置无对应）：`shareLayout=true` 时点颜色预设**只换 bg/text，不重置** 字号/字距/行距/段距 滑块；false 时切预设连同排版参数一起重置（原生默认行为）。这正是「共享排版」的用户可感知本质。
- checkbox 接线 `_shareLayout`，label 改「共享排版」。

### WS2 PaddingConfigDialog 边距弹窗（commit f0057cf）
- `ReaderPadding` 从 6 字段扩展为 14：body 原 top/bottom/left/right 保留；新增 header/footer 各 top/bottom/left/right（默认对齐原生 0/0/16/16、6/6/16/16）。`copyWith` + codec 同步（向后兼容）。
- **`nonContentHeight` 计算**：header 总高 = `headerHeight + headerTop + headerBottom`，footer 同理（旧实现 footer 硬编码 `+6`，现读字段）。
- `page_view` 的 header/footer 渲染改用各向外边距（`headerLeft/Right/Top/Bottom` 等），删除 footer 外层冗余 `Padding(top:2,bottom:4)`（避免与 footerTop/Bottom 双重 padding）。
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

## 待办（先不做动画）

- ~~`reader_view.dart` import 的 `page_animations/*.dart`（6个文件）整个目录缺失，根包当前无法编译。`flutter analyze` 的 38 个 error 全部源于此~~。**2026-06-29 复核**：根包 `flutter analyze` 现仅剩 2 个 info（`unnecessary_library_name` + `last_page_truncation_test.dart` 的 `prefer_interpolation`），0 error 0 warning，可整体编译。page_animations 缺失问题已不存在（reader_view 不再 import 该目录，或之前的提交已处理）。如确需补动画目录，从零开始即可。

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
