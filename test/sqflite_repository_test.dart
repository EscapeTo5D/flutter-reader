import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/bookmark.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/core/storage/cached_chapter.dart';
import 'package:flutter_reader/src/core/storage/sqflite_reader_repository.dart';
import 'package:flutter_reader/src/core/storage/reader_user.dart';
import 'package:flutter_reader/src/core/storage/reading_progress.dart';
import 'package:flutter_reader/src/core/storage/reading_style_preset.dart';

/// SqfliteReaderRepository 集成测试。
///
/// 使用 sqflite_common_ffi + in-memory 数据库, 无需 Android/iOS 环境,
/// 在桌面/CI 上可直接跑。
void main() {
  // 初始化 ffi, 用 in-memory db
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<SqfliteReaderRepository> newRepo() async {
    // :memory: 每次测试一个全新的内存库
    return SqfliteReaderRepository.open(dbPath: ':memory:');
  }

  test('open 建表不报错(可重复 open)', () async {
    final repo = await newRepo();
    await repo.close();
    // 再开一次(in-memory 是新库, 但建表逻辑应幂等)
    final repo2 = await newRepo();
    await repo2.close();
  });

  // ─────────────────────────── 进度 ───────────────────────────

  test('saveProgress/getProgress upsert + 读取一致', () async {
    final repo = await newRepo();
    final p1 = ReadingProgress(
      userId: 'u1',
      bookId: 'b1',
      chapterIndex: 3,
      chapterCharOffset: 128,
      pageIndex: 5,
      lastReadAt: DateTime(2026, 6, 29, 10, 0),
    );
    expect(await repo.getProgress('u1', 'b1'), isNull);

    await repo.saveProgress(p1);
    final got = await repo.getProgress('u1', 'b1');
    expect(got, isNotNull);
    expect(got!.chapterIndex, 3);
    expect(got.chapterCharOffset, 128);
    expect(got.pageIndex, 5);

    // 覆盖更新(upsert)
    await repo.saveProgress(p1.copyWith(chapterIndex: 4, chapterCharOffset: 256));
    final got2 = await repo.getProgress('u1', 'b1');
    expect(got2!.chapterIndex, 4);
    expect(got2.chapterCharOffset, 256);
    await repo.close();
  });

  test('进度按用户隔离: u1 和 u2 的进度互不可见', () async {
    final repo = await newRepo();
    await repo.saveProgress(ReadingProgress(
      userId: 'u1', bookId: 'b1', chapterIndex: 1,
      chapterCharOffset: 10, lastReadAt: DateTime.now()));
    await repo.saveProgress(ReadingProgress(
      userId: 'u2', bookId: 'b1', chapterIndex: 9,
      chapterCharOffset: 90, lastReadAt: DateTime.now()));

    expect((await repo.getProgress('u1', 'b1'))!.chapterIndex, 1);
    expect((await repo.getProgress('u2', 'b1'))!.chapterIndex, 9);
    expect(await repo.getProgress('u3', 'b1'), isNull);
    await repo.close();
  });

  // ─────────────────────────── 书签 ───────────────────────────

  test('saveBookmark/getBookmarks/deleteBookmark', () async {
    final repo = await newRepo();
    expect(await repo.getBookmarks('u1', 'b1'), isEmpty);

    await repo.saveBookmark(Bookmark(
      id: 'bm1', bookId: 'b1', chapterIndex: 0, pageIndex: 2,
      content: '第一处', createdAt: DateTime(2026, 6, 1),
      chapterCharOffset: 50, userId: 'u1'));
    await repo.saveBookmark(Bookmark(
      id: 'bm2', bookId: 'b1', chapterIndex: 1, pageIndex: 0,
      content: '第二处', createdAt: DateTime(2026, 6, 2),
      chapterCharOffset: 100, userId: 'u1'));

    final list = await repo.getBookmarks('u1', 'b1');
    expect(list.length, 2);
    // 倒序(最新在前)
    expect(list.first.id, 'bm2');
    expect(list.first.chapterCharOffset, 100);

    await repo.deleteBookmark('bm1');
    expect((await repo.getBookmarks('u1', 'b1')).length, 1);
    await repo.close();
  });

  // ─────────────────────────── 设置 ───────────────────────────

  test('saveSettings/getSettings 全局 + 按用户', () async {
    final repo = await newRepo();
    expect(await repo.getSettings(), isNull);

    final global = ReadingSettings().copyWith(fontSize: 20);
    await repo.saveSettings(global);
    expect((await repo.getSettings())!.fontSize, 20);

    final userSpecific = ReadingSettings().copyWith(fontSize: 28);
    await repo.saveSettings(userSpecific, userId: 'u1');
    expect((await repo.getSettings(userId: 'u1'))!.fontSize, 28);
    // 全局不被用户设置覆盖
    expect((await repo.getSettings())!.fontSize, 20);
    await repo.close();
  });

  // ─────────────────────────── 书架 ───────────────────────────

  test('saveBookMeta/getBookshelf/removeBook', () async {
    final repo = await newRepo();
    final book = Book(
      id: 'b1', title: '示例书', author: '佚名', coverUrl: 'http://x/1.png',
      currentChapterIndex: 2, currentPageIndex: 4,
    );
    await repo.saveBookMeta('u1', book);
    final shelf = await repo.getBookshelf('u1');
    expect(shelf.length, 1);
    expect(shelf.first.title, '示例书');
    expect(shelf.first.coverUrl, 'http://x/1.png');
    expect(shelf.first.currentChapterIndex, 2);

    // removeBook 同时清理该书进度与书签
    await repo.saveProgress(ReadingProgress(
      userId: 'u1', bookId: 'b1', chapterIndex: 0,
      chapterCharOffset: 0, lastReadAt: DateTime.now()));
    await repo.saveBookmark(Bookmark(
      id: 'bm1', bookId: 'b1', chapterIndex: 0, pageIndex: 0,
      content: '', createdAt: DateTime.now(), userId: 'u1'));

    await repo.removeBook('u1', 'b1');
    expect(await repo.getBookshelf('u1'), isEmpty);
    expect(await repo.getProgress('u1', 'b1'), isNull);
    expect(await repo.getBookmarks('u1', 'b1'), isEmpty);
    await repo.close();
  });

  // ─────────────────────────── 用户 ───────────────────────────

  test('setCurrentUser/getCurrentUser', () async {
    final repo = await newRepo();
    expect(await repo.getCurrentUser(), isNull);

    await repo.setCurrentUser(ReaderUser(id: 'u1', name: '张三'));
    final u = await repo.getCurrentUser();
    expect(u, isNotNull);
    expect(u!.id, 'u1');
    expect(u.name, '张三');
    await repo.close();
  });

  // ─────────────────────────── 章节正文缓存 ───────────────────────────

  test('saveChapterContent/getBookChapters 往返 + 升序', () async {
    final repo = await newRepo();
    expect(await repo.getBookChapters('b1'), isEmpty);

    await repo.saveChapterContent('b1', 2, '第二章', '内容2');
    await repo.saveChapterContent('b1', 0, '第一章', '内容0');
    await repo.saveChapterContent('b1', 1, '第二章', '内容1');

    final list = await repo.getBookChapters('b1');
    expect(list.length, 3);
    // 按 chapter_index 升序返回
    expect(list.map((c) => c.chapterIndex), [0, 1, 2]);
    expect(list.first.title, '第一章');
    expect(list.first.content, '内容0');
    expect(list.last.title, '第二章');
    expect(list.last.content, '内容2');
    // 按书隔离
    expect(await repo.getBookChapters('b2'), isEmpty);
    await repo.close();
  });

  test('getCachedChapter 单章 + upsert 覆盖', () async {
    final repo = await newRepo();
    expect(await repo.getCachedChapter('b1', 0), isNull);

    await repo.saveChapterContent('b1', 0, '旧标题', '旧内容');
    final got = await repo.getCachedChapter('b1', 0);
    expect(got, isNotNull);
    expect(got!.title, '旧标题');
    expect(got.content, '旧内容');

    // 覆盖(同主键 upsert)
    await repo.saveChapterContent('b1', 0, '新标题', '新内容');
    final got2 = await repo.getCachedChapter('b1', 0);
    expect(got2!.title, '新标题');
    expect(got2.content, '新内容');
    await repo.close();
  });

  test('removeBook 级联清章节缓存', () async {
    final repo = await newRepo();
    await repo.saveChapterContent('b1', 0, '第一章', '内容');
    await repo.saveChapterContent('b1', 1, '第二章', '内容');
    // 书架得先有该书(removeBook 按 user+book 删)
    await repo.saveBookMeta('u1', Book(id: 'b1', title: '书', author: ''));

    expect((await repo.getBookChapters('b1')).length, 2);
    await repo.removeBook('u1', 'b1');
    // 缓存随删书架一并清理
    expect(await repo.getBookChapters('b1'), isEmpty);
    await repo.close();
  });

  // ─────────────────────────── 范围查 / 批量写 ───────────────────────────

  test('getCachedChaptersInRange 闭区间 + 升序 + 按书隔离', () async {
    final repo = await newRepo();
    // 准备 b1 的 0~4 章
    await repo.saveChapterContents('b1', [
      for (var i = 0; i < 5; i++)
        CachedChapter(bookId: 'b1', chapterIndex: i, title: '章$i', content: 'c$i'),
    ]);
    // b2 混入同名章, 验证按书隔离
    await repo.saveChapterContent('b2', 1, '别书', '别内容');

    // 闭区间 [1, 3]
    final range = await repo.getCachedChaptersInRange('b1', 1, 3);
    expect(range.map((c) => c.chapterIndex), [1, 2, 3]);
    expect(range.first.content, 'c1');
    expect(range.last.content, 'c3');
    // 不含 b2 的章
    expect(range.every((c) => c.bookId == 'b1'), isTrue);

    // 缺失章: b1 只存了偶数, 奇数 index 不在结果里
    await repo.saveChapterContents('b3', [
      CachedChapter(bookId: 'b3', chapterIndex: 0, title: 't0', content: 'x0'),
      CachedChapter(bookId: 'b3', chapterIndex: 2, title: 't2', content: 'x2'),
      CachedChapter(bookId: 'b3', chapterIndex: 4, title: 't4', content: 'x4'),
    ]);
    final sparse = await repo.getCachedChaptersInRange('b3', 0, 4);
    expect(sparse.map((c) => c.chapterIndex), [0, 2, 4]);

    // 空区间(from > to)返回空, 不误查全表
    expect(await repo.getCachedChaptersInRange('b1', 3, 1), isEmpty);
    await repo.close();
  });

  test('saveChapterContents 批量写 + 覆盖 + 等价于循环单写', () async {
    final repo = await newRepo();
    await repo.saveChapterContents('b1', [
      CachedChapter(bookId: 'b1', chapterIndex: 0, title: 'a', content: 'A'),
      CachedChapter(bookId: 'b1', chapterIndex: 1, title: 'b', content: 'B'),
    ]);
    var all = await repo.getBookChapters('b1');
    expect(all.length, 2);
    expect(all.first.content, 'A');

    // 批量覆盖(同主键 upsert)
    await repo.saveChapterContents('b1', [
      CachedChapter(bookId: 'b1', chapterIndex: 0, title: 'a', content: 'A2'),
      CachedChapter(bookId: 'b1', chapterIndex: 2, title: 'c', content: 'C'),
    ]);
    all = await repo.getBookChapters('b1');
    expect(all.map((c) => c.chapterIndex), [0, 1, 2]);
    expect(all.firstWhere((c) => c.chapterIndex == 0).content, 'A2');
    expect(all.firstWhere((c) => c.chapterIndex == 1).content, 'B'); // 未覆盖
    expect(all.firstWhere((c) => c.chapterIndex == 2).content, 'C');
    await repo.close();
  });

  // ─────────────────────────── 用户样式预设 ───────────────────────────

  test('saveStylePreset/getStylePresets 往返 + sort_order 升序', () async {
    final repo = await newRepo();
    expect(await repo.getStylePresets('u1'), isEmpty);

    final now = DateTime.now();
    final p0 = ReadingStylePreset(
        id: 'p0', userId: 'u1', name: '我的预设',
        bgColor: const Color(0xFFAABBCC), textColor: const Color(0xFF112233),
        sortOrder: 1, createdAt: now);
    final p1 = ReadingStylePreset(
        id: 'p1', userId: 'u1', name: '预设B',
        bgColor: const Color(0xFFFFFFFF), textColor: const Color(0xFF000000),
        sortOrder: 0, createdAt: now);

    await repo.saveStylePreset(p0);
    await repo.saveStylePreset(p1);

    final list = await repo.getStylePresets('u1');
    expect(list.length, 2);
    // 按 sort_order 升序
    expect(list.map((p) => p.id), ['p1', 'p0']);
    expect(list.first.name, '预设B');
    // 颜色往返一致(用 ARGB int 比较, 避免颜色空间差异)
    expect(list.last.bgColor.toARGB32(), 0xFFAABBCC);
    expect(list.last.textColor.toARGB32(), 0xFF112233);
    await repo.close();
  });

  test('预设按用户隔离: u1 看不到 u2 的预设', () async {
    final repo = await newRepo();
    final now = DateTime.now();
    await repo.saveStylePreset(ReadingStylePreset(
        id: 'pu1', userId: 'u1', name: 'U1预设',
        bgColor: const Color(0xFFFFFFFF), textColor: const Color(0xFF000000),
        sortOrder: 0, createdAt: now));
    await repo.saveStylePreset(ReadingStylePreset(
        id: 'pu2', userId: 'u2', name: 'U2预设',
        bgColor: const Color(0xFFF44336), textColor: const Color(0xFF2196F3),
        sortOrder: 0, createdAt: now));

    expect((await repo.getStylePresets('u1')).map((p) => p.id), ['pu1']);
    expect((await repo.getStylePresets('u2')).map((p) => p.id), ['pu2']);
    await repo.close();
  });

  test('deleteStylePreset + upsert 覆盖', () async {
    final repo = await newRepo();
    final now = DateTime.now();
    await repo.saveStylePreset(ReadingStylePreset(
        id: 'pd', userId: 'u1', name: '旧名',
        bgColor: const Color(0xFFFFFFFF), textColor: const Color(0xFF000000),
        sortOrder: 0, createdAt: now));

    // upsert 覆盖(同 id)
    await repo.saveStylePreset(ReadingStylePreset(
        id: 'pd', userId: 'u1', name: '新名',
        bgColor: const Color(0xFF4CAF50), textColor: const Color(0xFFF44336),
        sortOrder: 0, createdAt: now));
    var list = await repo.getStylePresets('u1');
    expect(list.length, 1);
    expect(list.first.name, '新名');
    // 用 ARGB int 比较, 避免颜色空间(colorSpace)导致的 Color 相等性差异。
    expect(list.first.bgColor.toARGB32(), 0xFF4CAF50);

    // 删除
    await repo.deleteStylePreset('pd');
    expect(await repo.getStylePresets('u1'), isEmpty);
    await repo.close();
  });
}
