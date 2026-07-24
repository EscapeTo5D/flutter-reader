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
    // 用零 padding 的设置: 本用例只验证「字号变化 → charOffset 仍落同一内容位置」,
    // 不应受 padding 默认值漂移影响(默认 padding 随预设对齐会变)。
    final baseSettings = ReadingSettings();
    final zeroPaddingSettings = baseSettings.copyWith(
      padding: const ReaderPadding(
        top: 0, bottom: 0, left: 0, right: 0,
        headerTop: 0, headerBottom: 0, headerLeft: 0, headerRight: 0,
        footerTop: 0, footerBottom: 0, footerLeft: 0, footerRight: 0,
      ),
    );
    // 设备 A: 字号 20, 翻到某页
    final cA = ReadingController(repository: repo, userId: 'u1');
    cA.loadBook(makeBook());
    cA.updateSettings(zeroPaddingSettings.copyWith(fontSize: 20));
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
    cB.updateSettings(zeroPaddingSettings.copyWith(fontSize: 30));
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

  test('updateBookmark 编辑笔记/原文后落库', () async {
    final repo = await newRepo();
    final c = ReadingController(repository: repo, userId: 'u1');
    c.loadBook(makeBook());
    c.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));

    c.addBookmark();
    expect(c.bookmarks.length, 1);
    final bm = c.bookmarks.first;
    // addBookmark 时 content=''(笔记留空), bookText=整页正文。
    expect(bm.content, '');
    expect(bm.bookText, isNotEmpty);

    // 编辑笔记 + 改原文。
    await c.updateBookmark(bm.copyWith(
      content: '我的读书笔记',
      bookText: '改后的原文',
    ));
    expect(c.bookmarks.first.content, '我的读书笔记');
    expect(c.bookmarks.first.bookText, '改后的原文');

    // 验证已落库。
    final stored = await repo.getBookmarks('u1', 'book-test');
    expect(stored.first.content, '我的读书笔记');
    expect(stored.first.bookText, '改后的原文');

    await closeController(c);
    await repo.close();
  });

  // 对齐原生: 点书签按钮弹 Dialog, 当前页无书签时 currentBookmarkDraft 返回预填原文
  // 的新书签草稿; 确定 → updateBookmark upsert(不存在则新建)。覆盖该新建路径。
  test('currentBookmarkDraft + updateBookmark 新建路径(对齐原生 Dialog 流程)', () async {
    final repo = await newRepo();
    final c = ReadingController(repository: repo, userId: 'u1');
    c.loadBook(makeBook());
    c.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));

    // 当前页无书签 → draft 是预填原文的新草稿(笔记空)。
    expect(c.isCurrentPageBookmarked(), isFalse);
    final draft = c.currentBookmarkDraft();
    expect(draft, isNotNull);
    expect(draft!.content, '');
    expect(draft.bookText, isNotEmpty); // 预填整页原文
    expect(draft.chapterCharOffset, isNotNull);

    // 用户在 Dialog 填笔记后确定 → updateBookmark upsert 新建。
    await c.updateBookmark(draft.copyWith(content: '我标记的笔记'));
    expect(c.bookmarks.length, 1);
    expect(c.isCurrentPageBookmarked(), isTrue);
    expect(c.bookmarks.first.content, '我标记的笔记');

    // 已落库。
    final stored = await repo.getBookmarks('u1', 'book-test');
    expect(stored.length, 1);
    expect(stored.first.content, '我标记的笔记');

    // 再次取 draft: 当前页已有书签 → 返回它(编辑态, 含已填笔记)。
    final draft2 = c.currentBookmarkDraft();
    expect(draft2!.content, '我标记的笔记');

    await closeController(c);
    await repo.close();
  });

  test('removeBookmark 按 id 删除内存+落库', () async {
    final repo = await newRepo();
    final c = ReadingController(repository: repo, userId: 'u1');
    c.loadBook(makeBook());
    c.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));

    c.addBookmark();
    final id = c.bookmarks.first.id;
    expect(c.bookmarks.length, 1);
    expect((await repo.getBookmarks('u1', 'book-test')).length, 1);

    await c.removeBookmark(id);
    expect(c.bookmarks, isEmpty);
    expect((await repo.getBookmarks('u1', 'book-test')), isEmpty);

    await closeController(c);
    await repo.close();
  });

  test('goToBookmarkLocation 用 charOffset 跨章精确定位', () async {
    final repo = await newRepo();
    final c = ReadingController(repository: repo, userId: 'u1');
    c.loadBook(makeBook());
    c.updatePageSize(const Size(120, 200));
    await Future.delayed(const Duration(milliseconds: 50));

    // 跳到第 2 章(idx=1)某页, 记下 charOffset, 加书签。
    c.goToChapter(1);
    await Future.delayed(const Duration(milliseconds: 50));
    c.goToPage(1);
    await Future.delayed(const Duration(milliseconds: 30));
    final targetChapter = c.currentChapterIndex;
    final targetOffset = c.charOffsetForCurrentPage();
    final targetPage = c.currentPageIndex;
    expect(targetChapter, 1);
    expect(targetOffset, greaterThan(0));

    c.addBookmark();
    final bm = c.bookmarks.first;

    // 跑到别处, 再用书签的 (chapter, charOffset) 跳回。
    c.goToChapter(0);
    c.goToPage(0);
    await Future.delayed(const Duration(milliseconds: 30));
    expect(c.currentChapterIndex, 0);

    c.goToBookmarkLocation(bm.chapterIndex, bm.chapterCharOffset!);
    await Future.delayed(const Duration(milliseconds: 80));
    expect(c.currentChapterIndex, targetChapter);
    expect(c.currentPageIndex, targetPage);

    await closeController(c);
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
