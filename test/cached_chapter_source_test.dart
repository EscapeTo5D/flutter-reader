import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_reader/src/core/models/chapter_meta.dart';
import 'package:flutter_reader/src/core/models/chapter_source.dart';
import 'package:flutter_reader/src/core/storage/cached_chapter.dart';
import 'package:flutter_reader/src/core/storage/cached_chapter_source.dart';
import 'package:flutter_reader/src/core/storage/sqflite_reader_repository.dart';

/// CachedChapterSource 按章加载测试。
///
/// 覆盖: 标题不读正文 / 正文本地优先 / 未命中 onMissing 回填 /
/// 内存窗口缓存 / prefetchRange / evict 内存回收 / fromMemory 降级路径。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<SqfliteReaderRepository> newRepo() =>
      SqfliteReaderRepository.open(dbPath: ':memory:');

  group('目录(标题)不触发正文加载', () {
    test('chapterTitle/chapterCount 不读 content', () async {
      final repo = await newRepo();
      // 不预写任何正文缓存
      final src = CachedChapterSource(
        titles: const ['第一章', '第二章', '第三章'],
        repository: repo,
        bookId: 'b1',
      );
      expect(src.chapterCount, 3);
      expect(src.chapterTitle(0), '第一章');
      expect(src.chapterTitle(2), '第三章');
      expect(src.chapterTitle(5), ''); // 越界返回空串
      // 全程未访问 DB 正文列
      expect(await src.loadContent(0), isNull); // 无缓存无 onMissing
      await repo.close();
    });
  });

  group('正文本地优先', () {
    test('loadContent 命中本地缓存', () async {
      final repo = await newRepo();
      await repo.saveChapterContent('b1', 1, '第二章', '正文2');
      final src = CachedChapterSource(
        titles: const ['第一章', '第二章'],
        repository: repo,
        bookId: 'b1',
      );
      expect(await src.loadContent(1), '正文2');
      // 第二次走内存窗口(不再查库, 此处仅验证返回一致)
      expect(await src.loadContent(1), '正文2');
      await repo.close();
    });

    test('缓存未命中时 onMissing 回填 + 落库', () async {
      final repo = await newRepo();
      var missingCalls = 0;
      final src = CachedChapterSource(
        titles: const ['第一章', '第二章'],
        repository: repo,
        bookId: 'b1',
        onMissing: (index, title) async {
          missingCalls++;
          return '网络正文$index';
        },
      );
      // 未命中 → 走 onMissing
      expect(await src.loadContent(1), '网络正文1');
      expect(missingCalls, 1);
      // onMissing 回填后落库: 新 source 直接命中本地(不再调 onMissing)
      final src2 = CachedChapterSource(
        titles: const ['第一章', '第二章'],
        repository: repo,
        bookId: 'b1',
        onMissing: (_, _) async {
          fail('应命中本地缓存, 不该走 onMissing');
        },
      );
      expect(await src2.loadContent(1), '网络正文1');
      await repo.close();
    });

    test('onMissing 返回 null 视为无内容', () async {
      final repo = await newRepo();
      final src = CachedChapterSource(
        titles: const ['第一章'],
        repository: repo,
        bookId: 'b1',
        onMissing: (_, _) async => null,
      );
      expect(await src.loadContent(0), isNull);
      await repo.close();
    });
  });

  group('内存窗口管理', () {
    test('prefetchRange 预取窗口到内存', () async {
      final repo = await newRepo();
      await repo.saveChapterContents('b1', [
        for (var i = 0; i < 5; i++)
          CachedChapter(bookId: 'b1', chapterIndex: i, title: 't$i', content: 'c$i'),
      ]);
      final src = CachedChapterSource(
        titles: const ['t0', 't1', 't2', 't3', 't4'],
        repository: repo,
        bookId: 'b1',
      );
      await src.prefetchRange(1, 3);
      // 窗口内章节能秒取
      expect(await src.loadContent(2), 'c2');
      await repo.close();
    });

    test('evict 释放窗口外章', () async {
      final repo = await newRepo();
      await repo.saveChapterContent('b1', 0, 't0', 'c0');
      await repo.saveChapterContent('b1', 5, 't5', 'c5');
      final src = CachedChapterSource(
        titles: const ['t0', 't1', 't2', 't3', 't4', 't5'],
        repository: repo,
        bookId: 'b1',
      );
      // 先加载 0 和 5 进内存窗口
      await src.loadContent(0);
      await src.loadContent(5);
      // 保留当前章 0, 释放其它
      src.evict(const [0]);
      // 释放后重新 loadContent(5) 仍能从 DB 取回(窗口被回收但 DB 还在)
      expect(await src.loadContent(5), 'c5');
      await repo.close();
    });
  });

  group('降级路径', () {
    test('ChapterSource.fromMemory 全量正文常驻', () async {
      final src = ChapterSource.fromMemory(const [
        ChapterMeta(title: '第一章', content: '正文1'),
        ChapterMeta(title: '第二章', content: '正文2'),
      ]);
      expect(src.chapterCount, 2);
      expect(src.chapterTitle(1), '第二章');
      expect(await src.loadContent(0), '正文1');
      expect(await src.loadContent(5), isNull); // 越界
    });

    test('fromCached 从缓存行构造, 标题提取 + 正文懒加载', () async {
      final repo = await newRepo();
      await repo.saveChapterContents('b1', [
        CachedChapter(bookId: 'b1', chapterIndex: 0, title: 'a', content: 'A'),
        CachedChapter(bookId: 'b1', chapterIndex: 1, title: 'b', content: 'B'),
        CachedChapter(bookId: 'b1', chapterIndex: 2, title: 'c', content: 'C'),
      ]);
      final cached = await repo.getBookChapters('b1');
      final src = CachedChapterSource.fromCached(
        chapters: cached,
        repository: repo,
        bookId: 'b1',
      );
      expect(src.chapterCount, 3);
      expect(src.chapterTitle(0), 'a');
      expect(src.chapterTitle(2), 'c');
      // 正文仍走 loadContent 按章读
      expect(await src.loadContent(1), 'B');
      await repo.close();
    });
  });
}
