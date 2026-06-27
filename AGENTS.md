# 项目记忆 (AGENTS.md)

本文件存放 ZCode 跨会话需要记住的项目级信息。新会话自动读取。

## 项目概况

- **flutter_reader**: 基于 legado（开源阅读 App）做的 Flutter 重构，是一个文本阅读器 widget 包。
- 包代码在 `lib/`，运行示例 app 在 `example/`。
- 阅读排版配置模型: `lib/src/core/models/reading_settings.dart`（对应原生 `Config` / `ReadTipConfig`）。注意：2026-06-26 远程重构后文件已移到 `core/` 和 `reader/` 下。

## ⚠️ 重要分支: backup/pre-refactor-2026-06-26

**不要删除这个分支！** 它含一套**未合并到 master** 的独立工作（10 个提交）：
- **PageDelegate 翻页架构重构**：`PageDelegate` 基类、`NoAnimPageDelegate`、把 `scroll_mode_handler.dart` 从 `page_animations/` 迁出、删除旧 `page_animations/*.dart`。这就是 master 上 `page_animations/` 目录缺失的原因——这个分支是"删除旧实现 + 用新 PageDelegate 架构替代"的进行中工作。
- **整套 legado 技术文档**：`docs/legado_reader/` 00~11 章 + 重构计划 + 设计文档（约 5442 行）。
- 删除不可恢复（除非靠 reflog 碰运气）。

如果未来要恢复"翻页架构重构"那条线，从这个分支接续。

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
- UI 滑块（`read_menu.dart`）：行距/段距滑块已是倍数/系数语义，无需改。
- ⚠️ `ContentProcessor` 跳过源文本空行（`if (paragraph.isEmpty) continue`），故实际管线里段距只来自引擎注入，不会双重；直接调 `paginate` 带 `\n\n` 的 caller 会对每个空行也加段距行（对齐原生同样跳过空行）。

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
