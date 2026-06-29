import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/bookmark.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/core/storage/sqflite_reader_repository.dart';
import 'package:flutter_reader/src/core/storage/reader_user.dart';
import 'package:flutter_reader/src/core/storage/reading_progress.dart';

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
}
