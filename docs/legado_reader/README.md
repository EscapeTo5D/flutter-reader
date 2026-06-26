# Legado 阅读器重构文档

> 本目录包含 Legado（阅读）Android 应用中文本阅读器的完整技术分析文档，用于指导 Flutter 重构。

## 快速导航

| 文件 | 内容 | 重要程度 |
|------|------|----------|
| `00-目录.md` | 文档结构 + 原始代码路径树 | ⭐⭐ |
| `01-架构总览.md` | 五层架构、12个核心组件、数据流、三页缓冲 | ⭐⭐⭐ |
| `02-数据模型.md` | TextChapter/TextPage/TextLine/Column 完整字段定义 | ⭐⭐⭐⭐⭐ |
| `03-状态管理.md` | ReadBook 单例、内容加载管线、ContentProcessor | ⭐⭐⭐⭐ |
| `04-视图层.md` | ReadView/PageView/ContentTextView 核心实现 | ⭐⭐⭐⭐ |
| `05-排版引擎.md` | ChapterProvider/TextChapterLayout/ZhLayout 排版机制 | ⭐⭐⭐⭐⭐ |
| `06-翻页动画.md` | PageDelegate 体系、五种动画、贝塞尔曲线、AutoPager | ⭐⭐⭐⭐ |
| `07-配置系统.md` | ReadBookConfig 配置项、三态切换、样式更新 | ⭐⭐⭐ |
| `08-渲染管线.md` | CanvasRecorder、预渲染、绘制流程 | ⭐⭐⭐ |
| `09-Flutter重构指南.md` | 技术选型、模块划分、关键代码示例、迁移优先级 | ⭐⭐⭐⭐⭐ |
| `10-Flutter现状对比分析.md` | 当前Flutter版与Android版的差异、补全清单 | ⭐⭐⭐⭐⭐ |

## 如果你是 AI 助手

这些文档描述了一个 Android 原生阅读器的完整实现，供 Flutter 重构使用。关键信息：

- **原始项目**: Legado（阅读）Android 应用
- **原始代码路径**: `D:\GitHub\legado\app\src\main\java\io\legado\app\`
- **核心功能**: 文本阅读器（小说/文章），支持多种翻页动画、自定义排版、中文标点压缩
- **架构模式**: MVVM + 全局单例（ReadBook）
- **关键设计**: 三页缓冲策略、Channel 流式排版、CanvasRecorder 渲染优化

## 如果你是开发者

建议阅读顺序：
1. `00-目录.md` — 了解全貌
2. `01-架构总览.md` — 理解整体架构
3. `02-数据模型.md` — 掌握数据结构
4. `10-Flutter现状对比分析.md` — 了解当前差距和补全清单
5. `09-Flutter重构指南.md` — 开始动手

需要深入了解某个模块时，再查阅对应的详细文档。
