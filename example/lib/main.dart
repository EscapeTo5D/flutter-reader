import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Reader Demo',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const ReaderHomePage(),
    );
  }
}

class ReaderHomePage extends StatefulWidget {
  const ReaderHomePage({super.key});

  @override
  State<ReaderHomePage> createState() => _ReaderHomePageState();
}

class _ReaderHomePageState extends State<ReaderHomePage> {
  final ReadingController _controller = ReadingController();

  @override
  void initState() {
    super.initState();
    _controller.loadBook(_createDemoBook());
  }

  Book _createDemoBook() {
    final buffer = StringBuffer();
    for (var i = 0; i < 20; i++) {
      buffer.writeln('这是第${i + 1}段内容。Flutter 是一个用于从单一代码库构建跨平台应用的 UI 工具包，'
          '由 Google 开发，支持 Android、iOS、Web、Windows、macOS 和 Linux。');
      buffer.writeln();
    }

    return Book(
      id: '1',
      title: '示例书籍',
      author: '作者',
      chapters: [
        Chapter(
          id: 'c1',
          title: '第一章 Flutter 简介',
          index: 0,
          content: '第一章 Flutter 简介\n\n${buffer.toString()}',
        ),
        Chapter(
          id: 'c2',
          title: '第二章 Dart 语言',
          index: 1,
          content: '第二章 Dart 语言\n\n'
              'Dart 是 Flutter 使用的编程语言。它是一种面向对象的、类定义的、'
              '单继承的语言，融合了 JavaScript 和 Swift 等语言的特点。\n\n'
              'Dart 支持 AOT（提前编译）和 JIT（即时编译）两种编译模式，'
              '这使得 Flutter 既能在开发阶段实现热重载，又能在生产环境中获得最佳性能。\n\n'
              '${buffer.toString()}',
        ),
        Chapter(
          id: 'c3',
          title: '第三章 Widget 体系',
          index: 2,
          content: '第三章 Widget 体系\n\n'
              'Widget 是 Flutter 中构建 UI 的基本单元。每个 Widget 都代表了界面的一部分。'
              'Flutter 提供了两种类型的 Widget：StatelessWidget 和 StatefulWidget。\n\n'
              'StatelessWidget 是不可变的，一旦创建就不能改变其状态。'
              'StatefulWidget 则可以在其生命周期内改变状态，'
              '适用于需要动态更新 UI 的场景。\n\n'
              '${buffer.toString()}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ReaderView(controller: _controller),
    );
  }
}
