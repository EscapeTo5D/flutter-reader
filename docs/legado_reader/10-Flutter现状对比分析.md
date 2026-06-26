# 第10章 Flutter 现状对比分析

> 本章记录当前 Flutter 版阅读器与 Android 原生版本的差异，作为补全功能的清单。

## 10.1 总览

| 维度 | Android 版 | Flutter 版 | 差距 |
|------|-----------|-----------|------|
| 排版精度 | Canvas 逐字符绘制 | TextPainter 逐行排版 | 🔴 大 |
| 数据模型 | TextChapter/TextPage/TextLine/Column 完整体系 | TextPage/TextLine 简化版 | 🔴 大 |
| 渲染方式 | Canvas.drawText + CanvasRecorder | Text Widget + RepaintBoundary | 🟡 中 |
| 翻页动画 | PageDelegate 5种动画 | PageAnimation 5种动画 | 🟢 小 |
| 状态管理 | 全局单例 ReadBook | ChangeNotifier + 依赖注入 | 🟢 小(架构更好) |
| 功能完整度 | 完整阅读器 | 基础阅读器 | 🔴 大 |

## 10.2 排版引擎差异

### 两端对齐

**Android 版**: 通过调整 `wordSpacing`（词间距）或 `extraLetterSpacing`（额外字间距）实现

**Flutter 版**: `ReadingSettings.textFullJustify` 配置项存在但 **未生效**

### 底部对齐

**Android 版**: 计算页面剩余空间，平均分配到各行间距中

**Flutter 版**: `ReadingSettings.textBottomJustify` 配置项存在但 **未生效**

### 中文标点禁则

**Android 版**: ZhLayout 自定义实现标点压缩

**Flutter 版**: 依赖系统 `TextPainter` 默认行为，**未实现**

### 多栏排版

**Android 版**: 横屏时支持双栏

**Flutter 版**: **完全没有实现**

## 10.3 数据模型差异

### TextChapter 缺失

**Android 版**: 缓存整章所有页面，翻章零等待

**Flutter 版**: `ReadingController._pages` 只缓存当前章，每次翻章实时重新排版

### TextLine 字段简化

**Android 版 TextLine 字段**:
```
text, textColumns, lineTop, lineBase, lineBottom,
indentWidth, chapterPosition, extraLetterSpacing, wordSpacing,
canvasRecorder ...
```

**Flutter 版 TextLine 字段**:
```dart
class TextLine {
  final String text;
  final bool isTitle;
  final bool isParagraphEnd;
  final double height;
}
```

### Column 体系完全缺失

**Android 版**: TextColumn / TextHtmlColumn / ImageColumn / ReviewColumn / ButtonColumn

**Flutter 版**: 没有任何 Column 对应类，不支持行内图片

## 10.4 功能缺失清单

| 功能 | Android 版 | Flutter 版 | 影响 |
|------|-----------|-----------|------|
| 图片内嵌 | ✅ ImageColumn | ❌ | 图文混排书籍无法阅读 |
| 自动翻页 | ✅ AutoPager | ❌ | 用户需求 |
| 朗读/TTS | ✅ ReadAloud | ❌ | 用户需求 |
| 替换规则 | ✅ ContentProcessor | ❌ | 净化广告内容 |
| 简繁转换 | ✅ | ❌ | 港台用户需求 |
| WebDAV 同步 | ✅ | ❌ | 多设备同步 |
| 书签持久化 | ✅ Room 数据库 | ❌ 内存 | 关闭丢失 |
| 进度持久化 | ✅ Room 数据库 | ❌ 内存 | 关闭丢失 |

## 10.5 补全优先级清单

### P0 — 必须实现（核心体验）

- [ ] **两端对齐**: 使用 `TextPainter` 逐行测量，调整字间距实现两端对齐
- [ ] **底部对齐**: 计算页面剩余空间，平均分配到各行间距
- [ ] **TextChapter 缓存**: 创建 `TextChapter` 类，缓存已排版页面，避免翻章重排
- [ ] **TextLine 字段补全**: 添加 `lineTop/lineBase/lineBottom`、`chapterPosition` 等字段

### P1 — 应该实现（体验提升）

- [ ] **多栏排版**: 横屏/平板自动分两栏
- [ ] **Column 体系**: 至少实现 `TextColumn` + `ImageColumn`
- [ ] **Canvas 逐字符绘制**: 自定义 `CustomPainter` 替代 `Text` Widget
- [ ] **数据持久化**: 书签、进度、配置持久化
- [ ] **中文标点压缩**: 自定义排版实现标点禁则

### P2 — 可以实现（功能完善）

- [ ] **自动翻页**: `AutoPager` 实现
- [ ] **图片内嵌**: `ImageColumn` + 图片加载
- [ ] **替换规则**: `ContentProcessor` 实现
- [ ] **CanvasRecorder 渲染优化**: `PictureRecorder` 离屏录制

### P3 — 进阶功能

- [ ] **朗读/TTS**
- [ ] **简繁转换**
- [ ] **WebDAV 同步**
- [ ] **段评显示**
