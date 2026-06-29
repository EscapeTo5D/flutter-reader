# flutter_reader

`flutter_reader` 是一个可嵌入宿主 Flutter 项目的文本阅读器 widget 包，参考 legado 阅读器的排版、页眉页脚、翻页交互和阅读设置模型实现。

## 功能

- 小说/长文本分页渲染，支持字号、字距、行距、段距、缩进、标题样式和两端对齐。
- 页眉/页脚 tip 配置，支持章节名、时间、电量、页码、书名、阅读进度等信息。
- 点击区域配置、菜单、章节列表、搜索、书签和文字选择工具栏。
- 滑动翻页与无动画模式；相邻章节预分页缓存用于降低跨章翻页卡顿。
- 可选持久化接口，内置 `SqfliteReaderRepository`，支持进度、设置、书签、书架和用户隔离。

## 安装

本地路径依赖：

```yaml
dependencies:
  flutter_reader:
    path: ../flutter-reader
```

Git 依赖：

```yaml
dependencies:
  flutter_reader:
    git:
      url: https://github.com/user/flutter_reader.git
```

## 最小接入

```dart
import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _controller = ReadingController();

  @override
  void initState() {
    super.initState();
    _controller.loadBook(widget.book);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ReaderView(controller: _controller),
    );
  }
}
```

书籍数据模型：

```dart
final book = Book(
  id: 'book-1',
  title: '示例小说',
  author: '佚名',
  chapters: [
    Chapter(
      id: 'chapter-1',
      title: '第一章',
      content: '第一章正文……',
      index: 0,
    ),
  ],
);
```

## 持久化接入

宿主可以使用内置 sqflite 实现，也可以实现 `ReaderRepository` 接入自己的数据库或云同步。

```dart
late final SqfliteReaderRepository _repo;
late final ReadingController _controller;

Future<void> initReader(Book book) async {
  _repo = await SqfliteReaderRepository.open();
  _controller = ReadingController(repository: _repo, userId: 'user-1');

  await _controller.loadSettings();
  _controller.loadBook(book);
}

Future<void> closeReader() async {
  await _controller.flushPersistence();
  _controller.dispose();
  await _repo.close();
}
```

持久化策略：

- 阅读进度按 `userId + bookId` 保存，主定位字段是章内字符偏移 `chapterCharOffset`，字号或屏幕尺寸变化后仍能恢复到相近内容位置。
- 阅读设置可按用户保存；未绑定用户时使用全局设置。
- 书签按用户和书籍隔离，包含章节、页码和章内字符偏移。
- 如果宿主已有账号系统，请把稳定账号 ID 作为 `userId` 传入。

桌面端使用 `sqflite_common_ffi` 时，宿主需要先初始化数据库工厂，并建议显式传入 `dbPath`。

## 背景资源

包内声明了 `assets/bg/` 背景资源。使用包内背景时传入相对资源路径即可，渲染层会通过 `package: 'flutter_reader'` 加载：

```dart
controller.updateSettings(
  controller.settings.copyWith(backgroundImage: 'assets/bg/护眼漫绿.jpg'),
);
```

## 开发验证

本仓库使用 FVM：

```bash
fvm flutter analyze
fvm flutter test
```

如果本机 Flutter 已在 PATH，也可以直接使用 `flutter analyze` 和 `flutter test`。
