# 翻页动画切换器 + Slide 方向 Bug 修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Slide 翻页 NEXT 方向动画倒放的 bug，并在「界面」Sheet 加入翻页动画模式切换器（仅 slide 生效，其余存配置并标注未实现）。

**Architecture:** 两处独立改动。(1) `reader_view.dart` 的 `_buildPageStack()` NEXT 分支两个 `Transform.translate` 的 offset 公式写反，改为对齐原生 `SlidePageDelegate.kt` 的正确偏移；(2) `read_menu.dart` 的 `_StyleDialog` 新增 `SegmentedButton<PageAnimMode>` 切换段，绑定到 `ReadingSettings.pageAnimMode`。不动状态机、手势、peek API、排版逻辑。

**Tech Stack:** Flutter (Dart), Material SegmentedButton, 现有 `PageAnimMode` 枚举。

**Spec:** `docs/superpowers/specs/2026-06-28-page-anim-switcher-design.md`

---

## File Structure

- **Modify:** `lib/src/reader/widgets/reader_view.dart` — 修 `_buildPageStack()` NEXT 分支偏移公式
- **Modify:** `lib/src/reader/widgets/read_menu.dart` — `_StyleDialog` 加翻页动画切换器

本次不新建文件，不改 `reading_settings.dart`（`PageAnimMode` 枚举与字段已存在）。

---

## Task 1: 修复 Slide NEXT 方向偏移公式

**Files:**
- Modify: `lib/src/reader/widgets/reader_view.dart:287-298`

**背景：** 当前 NEXT 分支偏移公式倒放。`progress` 含义为 0=未动、1=翻完。正确偏移（对齐原生 `SlidePageDelegate.kt:49-55`）：
- cur 当前页：从 `0` → `-width`（左滑出）
- next 下一页：从 `width` → `0`（从屏右滑入）

当前错误代码（283-298 行）：
```dart
if (_animDir == _PageDirection.next && _nextCache != null) {
  final nextWidget = RepaintBoundary(
    child: _buildPeekPage(_nextCache!),
  );
  return Stack(children: [
    // cur 向左滑出
    Transform.translate(
      offset: Offset(progress * width - width, 0),
      child: curWidget,
    ),
    // next 从屏右滑入
    Transform.translate(
      offset: Offset(progress * width, 0),
      child: nextWidget,
    ),
  ]);
}
```

PREV 分支（301-317 行）经核对与原生一致，**不改**。

- [ ] **Step 1: 替换 NEXT 分支两个 Transform.translate 的 offset**

用 Edit 工具，把 `lib/src/reader/widgets/reader_view.dart` 中 NEXT 分支的 Stack（含两个 Transform.translate）替换为：

```dart
        if (_animDir == _PageDirection.next && _nextCache != null) {
          final nextWidget = RepaintBoundary(
            child: _buildPeekPage(_nextCache!),
          );
          return Stack(children: [
            // cur 向左滑出: 0 → -width
            Transform.translate(
              offset: Offset(-progress * width, 0),
              child: curWidget,
            ),
            // next 从屏右滑入: width → 0
            Transform.translate(
              offset: Offset(width - progress * width, 0),
              child: nextWidget,
            ),
          ]);
        }
```

old_string 用整个 NEXT `if` 块（从 `if (_animDir == _PageDirection.next` 到对应的 `}` 闭合，即 283-299 行）以确保唯一匹配。

- [ ] **Step 2: 运行 flutter analyze 验证无新增 error**

Run: `flutter analyze lib/src/reader/widgets/reader_view.dart`
Expected: 无新增 error（已知 `page_animations/` 目录缺失导致的 error 与本文件无关，不应出现新 error）。若出现与本行相关 error，检查 offset 表达式语法。

- [ ] **Step 3: 运行现有测试确认无回归**

Run: `flutter test`
Expected: 全部通过（上一次基线 33 过）。本改动是纯渲染偏移，不碰 peek/commit 逻辑，不应影响测试。

- [ ] **Step 4: 手动验证 slide 方向（需真机/模拟器，可选）**

打开示例 app 翻页：
- 左滑（下一页）→ 应看到下一页从右侧滑入、当前页向左滑出（修正前是反的）。
- 右滑（上一页）→ 应不变（本来就对）。

若无法跑模拟器，跳过此步，依赖 Step 2/3 的静态/回归验证。

- [ ] **Step 5: Commit**

```bash
git add lib/src/reader/widgets/reader_view.dart
git commit -m "fix: 修正 slide 翻页 NEXT 方向动画倒放

对照原生 SlidePageDelegate.kt:49-55, cur 应从 0 滑到 -width(左滑出),
next 应从 width 滑到 0(右滑入)。原公式两个 offset 写反导致整段动画倒放。"
```

---

## Task 2: 「界面」Sheet 加翻页动画切换器

**Files:**
- Modify: `lib/src/reader/widgets/read_menu.dart` (`_StyleDialog` / `_StyleDialogState`)

**背景：** `_StyleDialog` 的 build 顺序为：`_buildDragHandle()` → `_buildTopButtons()` → `_buildSeekBars()` → `_buildDivider()` → `_buildStyleSection()`。新增的翻页动画段插在 `_buildTopButtons()` 之后、`_buildSeekBars()` 之前。`_StyleDialogState` 现有 `_apply()` 一次性 copyWith 所有排版字段并调 `updateSettings`。`PageAnimMode` 枚举已在 `reading_settings.dart` 定义（cover/slide/simulation/scroll/none），可直接 import 使用。

**设计取舍（spec 已定）：**
- 5 段全部可选，选中存配置；仅 slide 运行时生效。
- 切换段下方加一行小字「覆盖/仿真/滚动/无动画开发中，当前仅滑动可用」。
- SegmentedButton 撑满宽度（不滚动），中文双字标签可行。

- [ ] **Step 1: 在 `_StyleDialogState` 加 `pageAnimMode` 状态字段并初始化**

在 `lib/src/reader/widgets/read_menu.dart` 的 `_StyleDialogState` 中，`initState` 现有（约 303-315 行）：
```dart
  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _fontSizeProgress = s.fontSize.toInt() - 5;
    _letterSpacingProgress = (s.letterSpacing * 100).toInt() + 50;
    _lineHeightProgress = ((s.lineHeight - 1.0) / 0.015).round();
    _paragraphSpacingProgress = (s.paragraphSpacing * 10).toInt();
    textIndent = s.textIndent;
    titleMode = s.titleMode;
    bgColor = s.backgroundColor;
    textColor = s.textColor;
    bgImage = s.backgroundImage;
  }
```

在字段声明区（约 281-290 行，`late Color textColor;` 之后、`late String? bgImage;` 之前或之后）新增：
```dart
  late PageAnimMode pageAnimMode;
```

在 `initState` 末尾追加：
```dart
    pageAnimMode = s.pageAnimMode;
```

- [ ] **Step 2: 把 `pageAnimMode` 加入 `_apply()` 的 copyWith**

现有 `_apply()`（约 317-332 行）：
```dart
  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        fontSize: (_fontSizeProgress + 5).toDouble(),
        lineHeight: 1.0 + _lineHeightProgress * 0.015,
        paragraphSpacing: _paragraphSpacingProgress / 10.0,
        letterSpacing: (_letterSpacingProgress - 50) / 100.0,
        textIndent: textIndent,
        titleMode: titleMode,
        backgroundColor: bgColor,
        textColor: textColor,
        backgroundImage: bgImage,
        clearBackgroundImage: _clearBgImage,
      ),
    );
  }
```

在 copyWith 参数列表末尾（`clearBackgroundImage: _clearBgImage,` 之后）追加一行：
```dart
        pageAnimMode: pageAnimMode,
```

- [ ] **Step 3: 新增 `_buildPageAnimSelector()` 方法**

在 `_StyleDialogState` 中（建议放在 `_buildTopButtons()` 方法之后）新增：

```dart
  Widget _buildPageAnimSelector() {
    const labels = ['覆盖', '滑动', '仿真', '滚动', '无'];
    const modes = [
      PageAnimMode.cover,
      PageAnimMode.slide,
      PageAnimMode.simulation,
      PageAnimMode.scroll,
      PageAnimMode.none,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('翻页动画', style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<PageAnimMode>(
              segments: List.generate(5, (i) =>
                ButtonSegment(value: modes[i], label: Text(labels[i])),
              ),
              selected: {pageAnimMode},
              onSelectionChanged: (set) {
                setState(() => pageAnimMode = set.first);
                _apply();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '覆盖/仿真/滚动/无动画开发中，当前仅滑动可用',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: 把 `_buildPageAnimSelector()` 插入 build 方法**

现有 build 方法（约 335-354 行）的 Column children：
```dart
        children: [
          _buildDragHandle(),
          _buildTopButtons(),
          _buildSeekBars(),
          _buildDivider(),
          _buildStyleSection(),
          SizedBox(height: bottomPadding),
        ],
```

改为（在 `_buildTopButtons()` 之后、`_buildSeekBars()` 之前插入 `_buildPageAnimSelector()`）：
```dart
        children: [
          _buildDragHandle(),
          _buildTopButtons(),
          _buildPageAnimSelector(),
          _buildSeekBars(),
          _buildDivider(),
          _buildStyleSection(),
          SizedBox(height: bottomPadding),
        ],
```

- [ ] **Step 5: 确认 `PageAnimMode` 已 import**

`read_menu.dart` 顶部 import（第 1-4 行）：
```dart
import 'package:flutter/material.dart';
import '../../core/controller/reading_controller.dart';
import 'chapter_list_page.dart';
import 'legado_icons.dart';
```

`PageAnimMode` 定义在 `reading_settings.dart`。需新增 import：
```dart
import '../../core/models/reading_settings.dart';
```

用 Edit 在 `import 'chapter_list_page.dart';` 之前或之后加这一行。确认该文件当前未 import `reading_settings.dart`（已确认：当前 imports 不含它）。

- [ ] **Step 6: 运行 flutter analyze 验证**

Run: `flutter analyze lib/src/reader/widgets/read_menu.dart`
Expected: 无 error。常见问题：若 `PageAnimMode` 未 import 会报 `Undefined name`；若 SegmentedButton API 误用会报类型错。

- [ ] **Step 7: 运行全量测试确认无回归**

Run: `flutter test`
Expected: 全部通过（33 过，与 Task 1 后一致）。本改动纯 UI，不影响现有测试。

- [ ] **Step 8: Commit**

```bash
git add lib/src/reader/widgets/read_menu.dart
git commit -m "feat: 界面 Sheet 加翻页动画切换器

SegmentedButton 选 cover/slide/simulation/scroll/none 存入 pageAnimMode。
仅 slide 运行时生效，其余标注开发中。对齐原生 menu_page_anim 入口。"
```

---

## Self-Review

**1. Spec 覆盖：**
- 修 NEXT 方向 bug → Task 1 ✅
- 「界面」Sheet 加切换器 → Task 2 ✅
- SegmentedButton<PageAnimMode> 5 段 → Task 2 Step 3 ✅
- 位置在排版滑块上方 → Task 2 Step 4 ✅
- 全部可选 + 存配置 → Task 2 Step 3 (`onSelectionChanged` 存) ✅
- 标注未实现 → Task 2 Step 3 (Text 小字) ✅
- 不实现其他模式动画 → 明确不在范围 ✅

**2. Placeholder 扫描：** 无 TODO/TBD，所有代码块完整。

**3. 类型一致性：** `PageAnimMode` 枚举值 cover/slide/simulation/scroll/none 与 `reading_settings.dart` 定义一致；`SegmentedButton<PageAnimMode>` 用法与现有 `_buildTitleModeSelector` 的 `SegmentedButton<int>` 模式一致；`pageAnimMode` 字段名与 `ReadingSettings.pageAnimMode`、`copyWith(pageAnimMode:)` 一致。
