# 项目记忆 (AGENTS.md)

本文件存放 ZCode 跨会话需要记住的项目级信息。新会话自动读取。

## 项目概况

- **flutter_reader**: 基于 legado（开源阅读 App）做的 Flutter 重构，是一个文本阅读器 widget 包。
- 包代码在 `lib/`，运行示例 app 在 `example/`。
- 阅读排版配置模型: `lib/src/core/models/reading_settings.dart`（对应原生 `Config` / `ReadTipConfig`）。注意：2026-06-26 远程重构后文件已移到 `core/` 和 `reader/` 下。

## ⚠️ 关于"翻页架构重构"那条线

历史曾存在分支 `backup/pre-refactor-2026-06-26`（PageDelegate 基类 + NoAnimPageDelegate + 把 `scroll_mode_handler.dart` 迁出 `page_animations/` + 整套 legado 技术文档 docs/legado_reader/ 00~11 章）。**该分支已于 2026-06-29 前被删除，本地/远程/reflog 均无残留，不可恢复。** master 上的 `912604b feat: implement scroll page mode aligned with legado ScrollPageDelegate` 是 master 自身提交，与该分支无关。
- 后果：master 上 `page_animations/` 目录缺失（详见文末"待办"），根包暂不可整体编译。
- 如未来要重做"翻页架构重构"，只能从零开始，无法从那个分支接续。

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
- **未对齐项（留待后续）**：原生预设还含 padding(paddingTop5/Bottom4/Left22/Right22 等)、titleSize/titleMode、tipColor、header/footer padding、翻页等，Flutter `_StylePreset` 暂只支持 fontSize/letterSpacing/lineHeight/paragraphSpacing + 颜色 6 项。padding 等涉及 `ReaderPadding` 模型与尺寸重算，本轮未做。

## 页脚尺寸计算（已修复 2026-06-26）

**核心规则**：`reader_view.build()` 里算 `nonContentHeight`（喂给排版引擎的可用高度）时，每项"是否计入"的条件，必须和 `page_view.build()` 里"是否渲染"的条件逐项一致，否则正文与页脚会错位/重叠。

**对齐后的条件**（`page_view` 与 `reader_view` 必须同步）：
- `showHeader = settings.hideStatusBar && !settings.headerConfig.hidden`
- `showFooter = !settings.footerConfig.hidden`
- header 高度: 仅 `showHeader` 时计入 `headerHeight`
- footer 高度: 仅 `showFooter` 时计入 `footerHeight + 6`(footer 外层 Padding top2+bottom4)
- 分隔线 0.5: 跟随各自 show + showHeaderDivider/showFooterDivider

**设计约定（对齐原生 legado）**：
- 翻页模式（含 scroll）不影响 chrome 显隐，只改变翻页方式。scroll 模式也显示页眉页脚。
- 页眉页脚整体显隐只看 `hidden` 字段；三槽全 none 时页脚仍占位（对齐原生"容器始终在"）。

## 待办（先不做动画）

- `reader_view.dart` import 的 `page_animations/*.dart`（6个文件）整个目录缺失，根包当前无法编译。`flutter analyze` 的 38 个 error 全部源于此，与页脚/排版无关。用户决定先不补动画，等后续单独处理。
