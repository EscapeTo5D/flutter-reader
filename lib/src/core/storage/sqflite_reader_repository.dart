import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../models/reading_settings_codec.dart';
import 'cached_chapter.dart';
import 'reader_repository.dart';
import 'reader_user.dart';
import 'reading_progress.dart';

/// [ReaderRepository] 的 sqflite 默认实现。
///
/// 数据库结构(单文件 `flutter_reader.db`):
/// - `users(id TEXT PK, name TEXT, avatar TEXT)`
/// - `progress(user_id, book_id, chapter_index, char_offset, page_index, last_read_at, PK(user_id,book_id))`
/// - `bookmarks(id TEXT PK, user_id, book_id, chapter_index, page_index, char_offset, content, created_at)`
/// - `settings(user_id TEXT PK, json TEXT, updated_at INTEGER)`
/// - `books(user_id, book_id, title, author, cover_url, current_chapter_index, current_page_index, updated_at, PK(user_id,book_id))`
/// - `chapter_contents(book_id, chapter_index, title, content, fetched_at, PK(book_id,chapter_index))` — 章节正文缓存(v2)
///
/// 进度/书签/书架均按 user_id 隔离; settings 整体存 JSON(便于 schema 演进, 见
/// [encodeReadingSettings] 的 `_version` 字段)。
/// **章节正文缓存不走 user_id**: 正文与用户无关(同书 A 用户第N章 = B 用户的),
/// 仅按 bookId+chapterIndex 存, 避免冗余; removeBook 时按 book_id 级联清理。
///
/// 用法:
/// ```dart
/// final repo = await SqfliteReaderRepository.open();
/// await repo.setCurrentUser(ReaderUser(id: 'u1'));
/// ```
class SqfliteReaderRepository implements ReaderRepository {
  SqfliteReaderRepository._(this._db);

  final Database _db;

  static const _kDbName = 'flutter_reader.db';
  // v2: 新增 chapter_contents 表(章节正文缓存, 用于二次打开秒开)。
  // _onUpgrade 在老库上用 IF NOT EXISTS 增量建表, 已有数据不动。
  static const _kDbVersion = 2;

  /// 打开(或创建)数据库。
  ///
  /// [dbPath] 可选: 指定数据库文件路径。不传时默认放应用文档目录
  /// (用 path_provider)。桌面端(Windows/Linux/macOS)需宿主先初始化
  /// sqflite_ffi 并通过 [dbPath] 传入路径。
  static Future<SqfliteReaderRepository> open({String? dbPath}) async {
    final path = dbPath ?? await _defaultDbPath();
    final db = await openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return SqfliteReaderRepository._(db);
  }

  static Future<String> _defaultDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _kDbName);
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    // 用户
    batch.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT,
        avatar TEXT
      )
    ''');
    // 阅读进度
    batch.execute('''
      CREATE TABLE IF NOT EXISTS progress (
        user_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        char_offset INTEGER NOT NULL DEFAULT 0,
        page_index INTEGER,
        last_read_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, book_id)
      )
    ''');
    // 书签
    batch.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        page_index INTEGER NOT NULL,
        char_offset INTEGER,
        content TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_bookmarks_user_book ON bookmarks(user_id, book_id, created_at DESC)',
    );
    // 设置(整体 JSON)
    batch.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        user_id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    // 书架(书元信息)
    batch.execute('''
      CREATE TABLE IF NOT EXISTS books (
        user_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        cover_url TEXT,
        current_chapter_index INTEGER NOT NULL DEFAULT 0,
        current_page_index INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, book_id)
      )
    ''');
    // 章节正文缓存(v2)。正文与用户无关, 仅按 bookId+chapterIndex 复合键存。
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chapter_contents (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (book_id, chapter_index)
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_chapter_contents_book ON chapter_contents(book_id, chapter_index)',
    );
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 增量建表: v2 新增 chapter_contents(用 IF NOT EXISTS, 老库平滑升级, 已有数据不动)。
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chapter_contents (
          book_id TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '',
          fetched_at INTEGER NOT NULL,
          PRIMARY KEY (book_id, chapter_index)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_chapter_contents_book ON chapter_contents(book_id, chapter_index)',
      );
    }
  }

  @override
  Future<void> close() => _db.close();

  // ─────────────────────────── 用户 ───────────────────────────

  @override
  Future<ReaderUser?> getCurrentUser() async {
    // 当前用户不存在于表中(它是个运行时选择), 这里用一个单行元表 current_user 存储。
    // 为避免再加一张表, 复用 settings 表的 special user_id = '__current_user__' 存 JSON。
    final rows = await _db.query(
      'settings',
      where: 'user_id = ?',
      whereArgs: ['__current_user__'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final json =
          jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
      return ReaderUser.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setCurrentUser(ReaderUser user) async {
    await _db.insert(
      'settings',
      {
        'user_id': '__current_user__',
        'json': jsonEncode(user.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─────────────────────────── 阅读进度 ───────────────────────────

  @override
  Future<ReadingProgress?> getProgress(String userId, String bookId) async {
    final rows = await _db.query(
      'progress',
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReadingProgress(
      userId: userId,
      bookId: bookId,
      chapterIndex: rows.first['chapter_index'] as int,
      chapterCharOffset: rows.first['char_offset'] as int,
      pageIndex: rows.first['page_index'] as int?,
      lastReadAt: DateTime.fromMillisecondsSinceEpoch(
        rows.first['last_read_at'] as int,
      ),
    );
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    await _db.insert(
      'progress',
      {
        'user_id': progress.userId,
        'book_id': progress.bookId,
        'chapter_index': progress.chapterIndex,
        'char_offset': progress.chapterCharOffset,
        'page_index': progress.pageIndex,
        'last_read_at': progress.lastReadAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─────────────────────────── 书签 ───────────────────────────

  @override
  Future<List<Bookmark>> getBookmarks(String userId, String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToBookmark).toList();
  }

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {
    await _db.insert(
      'bookmarks',
      {
        'id': bookmark.id,
        'user_id': bookmark.userId,
        'book_id': bookmark.bookId,
        'chapter_index': bookmark.chapterIndex,
        'page_index': bookmark.pageIndex,
        'char_offset': bookmark.chapterCharOffset,
        'content': bookmark.content,
        'created_at': bookmark.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [bookmarkId]);
  }

  Bookmark _rowToBookmark(Map<String, dynamic> row) {
    return Bookmark(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      chapterIndex: row['chapter_index'] as int,
      pageIndex: row['page_index'] as int,
      content: (row['content'] as String?) ?? '',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      chapterCharOffset: row['char_offset'] as int?,
      userId: row['user_id'] as String,
    );
  }

  // ─────────────────────────── 阅读设置 ───────────────────────────

  @override
  Future<ReadingSettings?> getSettings({String? userId}) async {
    final key = userId ?? '__global__';
    final rows = await _db.query(
      'settings',
      where: 'user_id = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final json =
          jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
      return decodeReadingSettings(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSettings(ReadingSettings settings, {String? userId}) async {
    final key = userId ?? '__global__';
    await _db.insert(
      'settings',
      {
        'user_id': key,
        'json': jsonEncode(encodeReadingSettings(settings)),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─────────────────────────── 书架 ───────────────────────────

  @override
  Future<List<Book>> getBookshelf(String userId) async {
    final rows = await _db.query(
      'books',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToBook).toList();
  }

  @override
  Future<void> saveBookMeta(String userId, Book book) async {
    await _db.insert(
      'books',
      {
        'user_id': userId,
        'book_id': book.id,
        'title': book.title,
        'author': book.author,
        'cover_url': book.coverUrl,
        'current_chapter_index': book.currentChapterIndex,
        'current_page_index': book.currentPageIndex,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeBook(String userId, String bookId) async {
    final batch = _db.batch();
    batch.delete('books',
        where: 'user_id = ? AND book_id = ?', whereArgs: [userId, bookId]);
    batch.delete('progress',
        where: 'user_id = ? AND book_id = ?', whereArgs: [userId, bookId]);
    batch.delete('bookmarks',
        where: 'user_id = ? AND book_id = ?', whereArgs: [userId, bookId]);
    // 章节正文缓存: 正文与用户无关, 但随「删书架」一并清理(用户从书架移除书
    // 即视为不再需要该书缓存)。按 book_id 清, 不需要 user_id。
    batch.delete('chapter_contents', where: 'book_id = ?', whereArgs: [bookId]);
    await batch.commit(noResult: true);
  }

  Book _rowToBook(Map<String, dynamic> row) {
    return Book(
      id: row['book_id'] as String,
      title: row['title'] as String,
      author: (row['author'] as String?) ?? '',
      coverUrl: row['cover_url'] as String?,
      currentChapterIndex: (row['current_chapter_index'] as int?) ?? 0,
      currentPageIndex: (row['current_page_index'] as int?) ?? 0,
    );
  }

  // ─────────────────────────── 章节正文缓存 ───────────────────────────

  @override
  Future<List<CachedChapter>> getBookChapters(String bookId) async {
    final rows = await _db.query(
      'chapter_contents',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC',
    );
    return rows.map(_rowToCachedChapter).toList();
  }

  @override
  Future<CachedChapter?> getCachedChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final rows = await _db.query(
      'chapter_contents',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToCachedChapter(rows.first);
  }

  @override
  Future<void> saveChapterContent(
    String bookId,
    int chapterIndex,
    String title,
    String content,
  ) async {
    await _db.insert(
      'chapter_contents',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'title': title,
        'content': content,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  CachedChapter _rowToCachedChapter(Map<String, dynamic> row) {
    return CachedChapter(
      bookId: row['book_id'] as String,
      chapterIndex: row['chapter_index'] as int,
      title: (row['title'] as String?) ?? '',
      content: (row['content'] as String?) ?? '',
    );
  }
}
