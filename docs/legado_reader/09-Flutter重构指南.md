# 第9章 Flutter 重构指南

## 9.1 技术选型建议

| Android 原生 | Flutter 替代方案 | 说明 |
|-------------|-----------------|------|
| Canvas + TextPaint | `CustomPainter` + `TextPainter` | 核心文字绘制 |
| StaticLayout | `TextPainter` + `ParagraphBuilder` | 文字排版和断行 |
| ZhLayout (自定义) | 自定义实现 | 中文标点压缩 |
| Scroller + VelocityTracker | `AnimationController` + `Simulation` | 翻页动画 |
| FrameLayout | `Stack` | 多层视图叠加 |
| CanvasRecorder | `Picture` | 离屏录制回放 |
| SharedPreferences | `shared_preferences` / `hive` | 配置存储 |
| EventBus | `Stream` / `ChangeNotifier` | 事件通知 |
| CoroutineScope | `async` / `Future` / `Stream` | 异步编程 |
| Channel<T> | `StreamController<T>` | 流式数据 |

## 9.2 模块划分建议

```
lib/
├── core/
│   ├── model/ (book, book_chapter, book_progress)
│   ├── provider/ (chapter_provider, content_processor, image_provider)
│   └── service/ (read_book_service, book_help_service)
├── reader/
│   ├── entities/ (text_chapter, text_page, text_line, column/)
│   ├── layout/ (text_chapter_layout, zh_layout, text_page_factory)
│   ├── delegate/ (page_delegate, cover/slide/simulation/scroll/no_anim)
│   └── widgets/ (read_view, page_view, content_text_view, auto_pager)
└── data/ (database, repository)
```

## 9.3 关键实现要点

### 文字绘制 — CustomPainter

```dart
class ContentTextPainter extends CustomPainter {
  final TextPage textPage;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in textPage.lines) {
      for (final column in line.columns) {
        if (column is TextColumn) {
          final textPainter = TextPainter(
            text: TextSpan(text: column.charData, style: style),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(column.start, line.lineBase));
        }
      }
    }
  }
}
```

### 翻页动画 — AnimationController

```dart
abstract class PageDelegate {
  late AnimationController controller;
  void onDraw(Canvas canvas, Size size);
  void nextPage();
  void prevPage();
}

class SimulationPageDelegate extends PageDelegate {
  // 贝塞尔曲线控制点
  Offset bezierStart1, bezierControl1, bezierEnd1;
  // ... 同 Android 版
}
```

### 三页缓冲策略

```dart
class ReadBookService extends ChangeNotifier {
  TextChapter? prevTextChapter, curTextChapter, nextTextChapter;

  void moveToNextChapter() {
    prevTextChapter = curTextChapter;
    curTextChapter = nextTextChapter;
    nextTextChapter = null;
    _loadChapter(durChapterIndex + 1);
    notifyListeners();
  }
}
```

### CanvasRecorder 替代方案

```dart
class CanvasRecorder {
  Picture? _picture;

  void record(Size size, void Function(Canvas) drawCallback) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    drawCallback(canvas);
    _picture = recorder.endRecording();
  }

  void draw(Canvas canvas) {
    if (_picture != null) canvas.drawPicture(_picture!);
  }
}
```

## 9.4 迁移优先级

| 优先级 | 模块 | 说明 |
|--------|------|------|
| P0 | 数据模型层 | TextChapter/TextPage/TextLine/Column |
| P0 | 排版引擎 | ChapterProvider + TextChapterLayout |
| P0 | 文字绘制 | ContentTextPainter (CustomPainter) |
| P1 | 翻页动画 | PageDelegate 体系 |
| P1 | 状态管理 | ReadBookService (ChangeNotifier) |
| P2 | 配置系统 | ReadBookConfig |
| P3 | 文本选择、搜索高亮 | 选中、复制、搜索 |

## 9.5 注意事项

1. **文字渲染精度**: Flutter 的 `TextPainter` 与 Android 的 `Paint.measureText` 存在差异
2. **标点压缩**: Flutter 原生不支持，需要自定义实现
3. **字体加载**: 使用 `google_fonts` 或从 assets 加载
4. **内存管理**: 及时 `dispose()` TextPainter、Picture 等资源
5. **两端对齐**: 通过调整 `letterSpacing` 或手动计算字符位置实现
