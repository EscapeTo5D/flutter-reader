# 翻页动画切换器 + Slide 方向 Bug 修复

日期: 2026-06-28
范围: `lib/src/reader/widgets/reader_view.dart`, `lib/src/reader/widgets/read_menu.dart`

## 背景与问题

### 问题 1: Slide 翻页 NEXT 方向动画倒放

当前 `reader_view.dart` 的 `_buildPageStack()` 中, NEXT(向左翻下一页)方向的偏移公式写反了,
导致整段动画倒放: 用户左滑翻下一页时, 看到的是「下一页往右跑、当前页从左边回来」。

对照原生 legado `SlidePageDelegate.kt:42-56`:

```kotlin
// 原生 NEXT
canvas.withTranslation(distanceX) { nextRecorder.draw(this) }      // next 从 width → 0
canvas.withTranslation(distanceX - viewWidth) { curRecorder.draw(this) }  // cur 从 0 → -width
```

当前 Flutter 代码 (`reader_view.dart:283-298`):

```dart
// 当前(错误)
cur.offset  = Offset(progress * width - width, 0)  // 0→1: -width → 0  ❌ 当前页从屏左外滑回
next.offset = Offset(progress * width, 0)          // 0→1: 0 → width   ❌ 下一页往右跑出去
```

PREV 分支 (`reader_view.dart:301-317`) 方向是对的, 无需改。

### 问题 2: 缺少翻页动画切换入口

- `ReadingSettings.pageAnimMode` 字段已存在 (`PageAnimMode` 枚举: cover/slide/simulation/scroll/none,
  对齐原生 `PageAnim.kt` 常量 0~4), 默认 slide。
- 但该字段**当前不被任何代码消费**: 整个 `ReaderView` 始终运行 slide 动画, `pageAnimMode` 只是个
  空配置。`Grep "pageAnimMode"` 仅命中 `reading_settings.dart`(定义) 与 `reader_view.dart`(注释)。
- 原生 legado 的切换入口在右上角 overflow 菜单 `menu_page_anim` → `showPageAnimConfig()` 弹 selector。
- Flutter 端「界面」Sheet (`_StyleDialog`) 目前有字号/行距/段距/底色等排版项, 但无翻页动画项。

## 设计

### A. 修复 Slide NEXT 方向偏移公式

只改 `reader_view.dart` 的 `_buildPageStack()` 中 **NEXT 分支**两个 `Transform.translate` 的 offset。
progress 含义不变 (0=未动, 1=翻完)。

修正后 (对齐原生):

```dart
// NEXT: 当前页左滑出, 下一页从屏右滑入
Transform.translate(
  offset: Offset(-progress * width, 0),      // cur: 0 → -width
  child: curWidget,
),
Transform.translate(
  offset: Offset(width - progress * width, 0), // next: width → 0
  child: nextWidget,
),
```

不动: PREV 分支、状态机、手势判定 (`_animDir`/`_isCancel`/`_dragOffset`)、peek API、commitTurn。
拖拽跟手阶段也用同一 `_currentProgress`, 公式改对了拖拽跟手方向自然也正确。

**注意**: PREV 分支当前公式 (`prev.offset = progress*width - width`, `cur.offset = progress*width`)
经核对与原生一致 (prev 从 -width → 0, cur 从 0 → width), **不改**。

### B. 「界面」Sheet 加翻页动画切换器

在 `_StyleDialog` (`read_menu.dart`) 增加「翻页动画」选择段。

#### 位置

放在 `_buildSeekBars()` (字号/字距/行距/段距) 之上、`_buildTopButtons()` (加粗/字体/缩进/...) 之下。
理由: 翻页动画是阅读行为配置, 与排版项(字号/行距)分组更清晰, 放在排版滑块上方视觉分隔合理。

#### 控件

- 用 `SegmentedButton<PageAnimMode>` (与 `_buildTitleModeSelector` 现有 SegmentedButton 风格一致),
  5 段对应 cover/slide/simulation/scroll/none, 中文标签「覆盖/滑动/仿真/滚动/无」。
- 5 段在一行 `SegmentedButton` 里会偏挤; 用 `SingleChildScrollView(scrollDirection: horizontal)`
  包裹, 或直接让 SegmentedButton 撑满宽度(每段约屏宽 1/5, 中文双字标签可行)。**默认采用后者
  (不滚动)**, 视觉更干净; 若实测挤压再改滚动。

#### 未实现模式的处理

- 5 个模式全部**可选**(不禁用), 选中后存入 `ReadingSettings.pageAnimMode`。
- 仅 `slide` 实际生效; cover/simulation/scroll/none 选中后**运行时仍走 slide**(因为只有 slide 实现)。
- 切换器下方加一行小字说明: 「覆盖/仿真/滚动/无动画开发中, 当前仅滑动可用」(color: black54, fontSize 11)。
  做到诚实标注, 不误导用户以为已实现。

#### 状态绑定

`_StyleDialogState` 新增 `late PageAnimMode _pageAnimMode;`, 在 `initState` 读 `s.pageAnimMode`。
`_apply()` 里 `pageAnimMode: _pageAnimMode` 一起 copyWith。SegmentedButton 的 `onSelectionChanged`
回调 `setState` 后调 `_apply()` (与现有字号/行距滑块的 apply 模式一致, 即时生效)。

### 不在本次范围 (YAGNI)

- cover / simulation / scroll / none 动画的**实际实现**。simulation(贝塞尔仿真翻页)尤其复杂。
  本次只让配置可存, 行为仍 slide。后续单独任务实现。
- `pageAnimMode` 在 `ReaderView` 里的消费分支(switch on mode 选 delegate)。本次保留单一 slide 路径,
  等实现其他模式时再加 `switch (settings.pageAnimMode)` 分发。
- 原生那种「右上角 overflow 菜单」入口。本次按你选择放「界面」Sheet。
- 切换动画模式时是否需要重新分页/重绘的考量: slide→slide(本次唯一生效模式)不涉及, 无需处理。

## 测试

- **手动验证 slide 方向 bug**: 打开阅读器, 左滑翻下一页 → 应看到下一页从右侧滑入、当前页向左滑出
  (修正前是反的)。右滑翻上一页应不变(本来就对)。
- **手动验证切换器**: 「界面」Sheet 出现「翻页动画」段, 默认选中「滑动」; 选其他段 → settings 保存
  (可通过重新打开 Sheet 确认选中状态保留); 但翻页行为仍是 slide。
- **无新增单元测试**: bug 是纯渲染偏移公式, 依赖手势+动画, 难以单测; 切换器是 UI 绑定。
  现有 `peek_api_test` 等不涉及此次改动, 不应回归。
- `flutter analyze` 应保持 0 新增 error(已知 page_animations 目录缺失导致的 38 error 与本次无关)。

## 风险

- 低风险。bug 修复仅改两个 offset 表达式; 切换器是新增 UI, 不动现有排版/翻页逻辑。
- 唯一需注意: `_StyleDialog._apply()` 调 `updateSettings` 会触发 `_rePaginate`(整个章节重新分页),
  这是现有行为(调字号滑块同样会重排), 切换 pageAnimMode 本不需要重排, 但走同一 `_apply` 通道会
  重排一次。开销可接受(与改字号一致), 且语义无害(重排结果不变)。不为此单独优化。
