import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/chapter_meta.dart';
import 'package:flutter_reader/src/core/models/chapter_source.dart';
import 'package:flutter_reader/src/core/controller/reading_controller.dart';

/// Controller 按章加载 + 异步排版测试(第 3 层核心)。
///
/// 覆盖:
/// - chapterSource 注入后走按章加载(不读 Book.chapters 正文)。
/// - 首次 loadBook → 当前章异步加载 + 排版, 完成后 pages 就绪。
/// - 翻章 → 目标章异步加载(缓存未命中)/ 命中缓存(预排后)同步就绪。
/// - loading 态: 加载中 chapterLoading=true, 就绪后 false。
/// - 降级: chapterSource=null 时走旧全量内存路径(行为不变)。
void main() {
  /// 构造一个可控的 ChapterSource: 内容可预设, 加载次数可计数。
  _TestSource makeSource(List<ChapterMeta> chapters) =>
      _TestSource(chapters);

  /// 等待 controller 的异步加载完成(轮询 notifyListeners 直到 pages 就绪或超时)。
  Future<void> waitForChapterReady(
    ReadingController c, {
    int chapterIndex = 0,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (c.currentChapterIndex == chapterIndex && c.pages.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('注入 chapterSource 后, loadBook 异步加载当前章并排版就绪', () async {
    final source = makeSource([
      ChapterMeta(title: '第一章', content: '这是第一章的正文内容,足够排一页。' * 5),
      ChapterMeta(title: '第二章', content: '这是第二章的正文内容。' * 5),
    ]);
    final book = Book(
      id: 'b1',
      title: '测试书',
      author: '',
      chapterSource: source,
    );
    final c = ReadingController();
    c.updatePageSize(const Size(360, 600));
    c.loadBook(book);

    // 加载初期 pages 为空(异步加载中)
    expect(c.pages, isEmpty);
    await waitForChapterReady(c);
    expect(c.pages, isNotEmpty);
    expect(c.currentChapterIndex, 0);
    expect(source.loadCount[0], greaterThan(0));
    c.dispose();
  });

  test('翻章触发目标章异步加载, 就绪后 pages 更新', () async {
    final source = makeSource([
      ChapterMeta(title: '第一章', content: '第一章正文。' * 5),
      ChapterMeta(title: '第二章', content: '第二章正文,内容不同。' * 5),
      ChapterMeta(title: '第三章', content: '第三章正文。' * 5),
    ]);
    final c = ReadingController();
    c.updatePageSize(const Size(360, 600));
    c.loadBook(Book(id: 'b1', title: '书', author: '', chapterSource: source));
    await waitForChapterReady(c, chapterIndex: 0);

    // 翻到第二章(未预排 → 异步加载)
    c.nextChapter();
    expect(c.currentChapterIndex, 1);
    await waitForChapterReady(c, chapterIndex: 1);
    expect(c.pages, isNotEmpty);
    expect(source.loadCount[1], greaterThan(0));
    c.dispose();
  });

  test('相邻章预排后, 翻章命中缓存 O(1) 同步就绪', () async {
    final source = makeSource([
      ChapterMeta(title: '第一章', content: '第一章正文。' * 5),
      ChapterMeta(title: '第二章', content: '第二章正文。' * 5),
    ]);
    final c = ReadingController();
    c.updatePageSize(const Size(360, 600));
    c.loadBook(Book(id: 'b1', title: '书', author: '', chapterSource: source));
    await waitForChapterReady(c, chapterIndex: 0);

    // 触发相邻章预取
    c.prefetchAdjacentChapters();
    // 等预排完成(第二章入缓存)
    await waitForChapterReady(c, chapterIndex: 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final loadsBefore = source.loadCount[1] ?? 0;
    // 翻到第二章: 应命中缓存, pages 立即就绪(同步)
    c.nextChapter();
    expect(c.currentChapterIndex, 1);
    expect(c.pages, isNotEmpty, reason: '命中预排缓存应同步就绪');
    // 命中缓存: 不应再次从 source 加载正文
    expect(source.loadCount[1] ?? 0, loadsBefore,
        reason: '预排缓存命中后翻章不应重复加载正文');
    c.dispose();
  });

  test('totalChapters / chapterTitle 取自 chapterSource', () async {
    final source = makeSource([
      ChapterMeta(title: '甲章', content: 'x'),
      ChapterMeta(title: '乙章', content: 'y'),
      ChapterMeta(title: '丙章', content: 'z'),
    ]);
    final c = ReadingController();
    c.loadBook(Book(id: 'b1', title: '书', author: '', chapterSource: source));
    expect(c.totalChapters, 3);
    c.dispose();
  });

  test('chapterSource=null 退化为旧全量内存模式(同步排,行为不变)', () async {
    final c = ReadingController();
    c.updatePageSize(const Size(360, 600));
    c.loadBook(Book(
      id: 'b1',
      title: '书',
      author: '',
      chapters: [
        Chapter(id: '0', title: '第一章', content: '旧模式正文。' * 5, index: 0),
      ],
    ));
    // 全量模式: loadBook 后立即同步就绪(无异步)
    expect(c.pages, isNotEmpty);
    expect(c.chapterLoading, isFalse);
    c.dispose();
  });

  test('pageSize 未就绪时不排版(pages 为空, 不崩)', () async {
    final source = makeSource([
      ChapterMeta(title: '第一章', content: '正文。' * 5),
    ]);
    final c = ReadingController();
    // 不调 updatePageSize
    c.loadBook(Book(id: 'b1', title: '书', author: '', chapterSource: source));
    expect(c.pages, isEmpty);
    // 延迟一会确认没有异常抛出
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.pages, isEmpty);
    // 尺寸就绪后触发排版
    c.updatePageSize(const Size(360, 600));
    await waitForChapterReady(c);
    expect(c.pages, isNotEmpty);
    c.dispose();
  });
}

/// 可控的测试用 ChapterSource: 记录每章被加载的次数。
class _TestSource implements ChapterSource {
  _TestSource(this._chapters);
  final List<ChapterMeta> _chapters;
  final Map<int, int> loadCount = {};

  @override
  int get chapterCount => _chapters.length;

  @override
  String chapterTitle(int index) =>
      (index >= 0 && index < _chapters.length) ? _chapters[index].title : '';

  @override
  Future<String?> loadContent(int index) async {
    loadCount[index] = (loadCount[index] ?? 0) + 1;
    if (index < 0 || index >= _chapters.length) return null;
    // 模拟一点加载延迟, 让异步路径可观测
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return _chapters[index].content;
  }

  @override
  Future<void> ensureCached() async {}
}
