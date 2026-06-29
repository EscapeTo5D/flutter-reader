import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_reader/src/core/controller/reading_controller.dart';
import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/core/storage/sqflite_reader_repository.dart';

/// 持久化集成测试: 进度恢复 / 书签同步 / 设置持久化 / 防抖落盘。
///
/// 核心验证: 改字号重排后, 用 charOffset 仍能定位回原阅读位置(不跳页)。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// 造一本多章节、每章多页的书。窄高 pageSize 强制每章分多页。
  Book makeBook() {
    final chapters = <Chapter>[];
    for (var c = 0; c < 3; c++) {
      // 一章 30 段, 每段较长, 保证在窄尺寸下分多页
      final paragraphs = <String>[];
      for (var p = 0; p < 30; p++) {
        paragraphs.add('第${c + 1}章第${p + 1}段内容' * 4);
      }
      chapters.add(
        Chapter(
          id: 'ch$c',
          title: '第${c + 1}章 章节标题',
          content: paragraphs.join('\n'),
          index: c,
        ),
      );
    }
    return Book(
      id: 'book-test',
      title: '测试书',
      author: '佚名',
      chapters: chapters,
    );
  }

  Future<SqfliteReaderRepository> newRepo() =>
      SqfliteReaderRepository.open(dbPath: ':memory:');

  /// dispose 前先 flush 持久化, 避免 dispose 的 fire-and-forget 落库
  /// 在 repo.close() 之后才执行(测试场景的时序问题, 非产品 bug)。
  Future<void> closeController(ReadingController c) async {
    await c.flushPersistence();
    c.dispose();
  }

  test('翻页后进度被持久化, 新 controller 恢复到同一页', () async {
    final repo = await newRepo();
    // 第一台"设备": 翻几页后落盘
    final c1 = ReadingController(repository: repo, userId: 'u1');
    c1.loadBook(makeBook());
    c1.updatePageSize(const Size(120, 200)); // 窄高, 分多页
    await Future.delayed(const Duration(milliseconds: 50)); // 等 restoreProgress

    expect(c1.pages.length, greaterThan(1), reason: '应分多页');
    // 翻到第 2 页
    c1.goToPage(2);
    expect(c1.currentPageIndex, 2);
    final savedChapter = c1.currentChapterIndex;
    final savedOffset = c1.pages[2].lines
        .where((l) => l.text.isNotEmpty)
        .first
        .chapterPosition;

    await c1.flushProgress();
    await closeController(c1);

    // 验证仓库里确实存了
    final stored = await repo.getProgress('u1', 'book-test');
    expect(stored, isNotNull);
    expect(stored!.chapterIndex, savedChapter);
    expect(stored.chapterCharOffset, savedOffset);

    // 第二台"设备"(新 controller, 同用户同书): 恢复进度
    final c2 = ReadingController(repository: repo, userId: 'u1');
    c2.loadBook(makeBook());
    c2.updatePageSize(const Size(120, 200)); // 同尺寸
    await Future.delayed(const Duration(milliseconds: 100));

    expect(c2.currentChapterIndex, savedChapter, reason: '应恢复到同一章');
    expect(c2.currentPageIndex, 2, reason: '应恢复到第 2 页');
    await closeController(c2);
    await repo.close();
  });

  test('改字号重排后, 用 charOffset 仍定位到对应内容(不跳页)', () async {
    final repo = await newRepo();
    // 设备 A: 字号 20, 翻到某页
    final cA = ReadingController(repository: repo, userId: 'u1');
    cA.loadBook(makeBook());
    cA.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));
    cA.goToPage(1);
    final offsetA = cA.pages[1].lines
        .where((l) => l.text.isNotEmpty)
        .first
        .chapterPosition;
    await cA.flushProgress();
    await closeController(cA);

    // 设备 B: 字号更大(30) → 每页字数少 → 页数变多。但 charOffset 不变。
    final cB = ReadingController(repository: repo, userId: 'u1');
    cB.loadBook(makeBook());
    cB.updateSettings(ReadingSettings().copyWith(fontSize: 30));
    cB.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 100));

    // 恢复到的页, 其首行 charOffset 应与设备 A 的接近(落在同一内容位置)
    final restoredOffset = cB.pages[cB.currentPageIndex].lines
        .where((l) => l.text.isNotEmpty)
        .first
        .chapterPosition;
    // 恢复页的首行 offset 应 <= 原 offset, 且下一页首行 offset > 原 offset
    expect(
      restoredOffset,
      lessThanOrEqualTo(offsetA),
      reason: '恢复页首行 offset 应 <= 原 offset',
    );
    if (cB.currentPageIndex + 1 < cB.pages.length) {
      final nextOffset = cB.pages[cB.currentPageIndex + 1].lines
          .where((l) => l.text.isNotEmpty)
          .first
          .chapterPosition;
      expect(
        nextOffset,
        greaterThan(offsetA),
        reason: '下一页首行 offset 应 > 原 offset (说明定位精确)',
      );
    }
    await closeController(cB);
    await repo.close();
  });

  test('书签同步落库与恢复', () async {
    final repo = await newRepo();
    final c1 = ReadingController(repository: repo, userId: 'u1');
    c1.loadBook(makeBook());
    c1.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));

    // 加一个书签
    expect(c1.isCurrentPageBookmarked(), isFalse);
    c1.addBookmark();
    expect(c1.isCurrentPageBookmarked(), isTrue);

    // 验证仓库有该书签
    final stored = await repo.getBookmarks('u1', 'book-test');
    expect(stored.length, 1);
    expect(stored.first.userId, 'u1');
    expect(stored.first.chapterCharOffset, isNotNull);

    // 新 controller 恢复后, 书签也在内存里
    final c2 = ReadingController(repository: repo, userId: 'u1');
    c2.loadBook(makeBook());
    c2.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(c2.isCurrentPageBookmarked(), isTrue);

    // 再次 addBookmark 应切换为删除, 且同步删库
    c2.addBookmark();
    expect(c2.isCurrentPageBookmarked(), isFalse);
    await Future.delayed(const Duration(milliseconds: 50));
    expect((await repo.getBookmarks('u1', 'book-test')), isEmpty);

    await closeController(c1);
    await closeController(c2);
    await repo.close();
  });

  test('设置持久化: loadSettings 恢复上次字号', () async {
    final repo = await newRepo();
    final c1 = ReadingController(repository: repo, userId: 'u1');
    c1.updateSettings(ReadingSettings().copyWith(fontSize: 28));
    // 触发防抖落盘 (手动 flush 一下 settings——通过再 updateSettings 后等)
    // 这里直接调 saveSettings 更确定:
    await repo.saveSettings(c1.settings, userId: 'u1');
    await closeController(c1);

    final c2 = ReadingController(repository: repo, userId: 'u1');
    await c2.loadSettings();
    expect(c2.settings.fontSize, 28);
    await closeController(c2);
    await repo.close();
  });

  test('flushSettings 立即保存待落盘设置', () async {
    final repo = await newRepo();
    final c1 = ReadingController(repository: repo, userId: 'u1');
    c1.updateSettings(ReadingSettings().copyWith(fontSize: 31));

    await c1.flushSettings();
    await closeController(c1);

    final c2 = ReadingController(repository: repo, userId: 'u1');
    await c2.loadSettings();

    expect(c2.settings.fontSize, 31);
    await closeController(c2);
    await repo.close();
  });

  test('纯内存模式(无 repo)不报错, 行为与旧版一致', () async {
    final c = ReadingController(); // 无 repo
    c.loadBook(makeBook());
    c.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));
    c.goToPage(1);
    expect(c.currentPageIndex, 1);
    c.addBookmark();
    expect(c.bookmarks.length, 1);
    // flush 在无 repo 时是 no-op, 不应抛
    await c.flushPersistence();
    await closeController(c);
  });

  test('多用户隔离: u1 进度不影响 u2', () async {
    final repo = await newRepo();
    final c1 = ReadingController(repository: repo, userId: 'u1');
    c1.loadBook(makeBook());
    c1.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));
    c1.goToPage(3);
    await c1.flushProgress();
    await closeController(c1);

    final c2 = ReadingController(repository: repo, userId: 'u2');
    c2.loadBook(makeBook());
    c2.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 100));
    // u2 没读过, 应停在首页
    expect(c2.currentPageIndex, 0);
    await closeController(c2);
    await repo.close();
  });
}
