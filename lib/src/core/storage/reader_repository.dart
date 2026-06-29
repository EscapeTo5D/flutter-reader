import 'dart:async';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../models/reading_settings_codec.dart';
import 'reading_progress.dart';
import 'reader_user.dart';

/// 阅读器持久化仓库接口。
///
/// 本接口定义了 进度 / 设置 / 书签 / 书架 / 用户 五类数据的存取契约。
/// [SqfliteReaderRepository] 是包内自带的 sqflite 默认实现; 宿主也可实现此接口
/// 接入自己的存储(如 Isar/Hive/云端)。
///
/// 设计要点:
/// - **多用户隔离**: 进度/书签/书架均按 [userId] 隔离, 复合键 (userId, bookId)。
/// - **设置可全局或按用户**: [getSettings]/[saveSettings] 的 userId 可选;
///   null 表示全局设置(单用户场景或不按用户区分设置时用)。
/// - **进度用 charOffset**: [ReadingProgress.chapterCharOffset] 是章内字符偏移,
///   跨字号/换设备不漂移(详见 [ReadingProgress])。
abstract class ReaderRepository {
  // ─────────────────────────── 用户 ───────────────────────────

  /// 当前登录用户(null = 未登录/未设置, 此时进度等数据按 userId 取默认值)。
  Future<ReaderUser?> getCurrentUser();

  /// 设置当前用户。后续 getProgress/getBookmarks 等默认用此用户的 id。
  Future<void> setCurrentUser(ReaderUser user);

  // ─────────────────────────── 阅读进度 ───────────────────────────

  /// 读取某用户在某书的进度。无记录返回 null。
  Future<ReadingProgress?> getProgress(String userId, String bookId);

  /// 保存/覆盖进度(upsert, 主键 userId+bookId)。
  Future<void> saveProgress(ReadingProgress progress);

  // ─────────────────────────── 书签 ───────────────────────────

  /// 读取某用户在某书的所有书签(按创建时间倒序)。
  Future<List<Bookmark>> getBookmarks(String userId, String bookId);

  /// 保存/覆盖书签(按 id upsert)。
  Future<void> saveBookmark(Bookmark bookmark);

  /// 删除书签(按 id)。
  Future<void> deleteBookmark(String bookmarkId);

  // ─────────────────────────── 阅读设置 ───────────────────────────

  /// 读取设置。[userId] 为 null 时取全局设置。
  Future<ReadingSettings?> getSettings({String? userId});

  /// 保存设置。[userId] 为 null 时存为全局设置。
  Future<void> saveSettings(ReadingSettings settings, {String? userId});

  // ─────────────────────────── 书架(元信息) ───────────────────────────

  /// 读取某用户的书架(仅元信息, 不含章节正文)。
  Future<List<Book>> getBookshelf(String userId);

  /// 保存/更新书架中的某书元信息(upsert, 主键 userId+bookId)。
  Future<void> saveBookMeta(String userId, Book book);

  /// 从书架移除某书(同时清理该书在该用户下的进度与书签)。
  Future<void> removeBook(String userId, String bookId);

  // ─────────────────────────── 生命周期 ───────────────────────────

  /// 关闭/释放底层资源(数据库连接等)。dispose 时调用。
  Future<void> close();
}

/// [ReaderRepository] 的便捷扩展: 用 [ReaderSettingsCodec] 包装 settings 存取,
/// 让实现类无需各自处理 JSON 编解码。
extension ReaderRepositorySettingsCodec on ReaderRepository {
  /// 读取设置并以 JSON Map 形式返回(便于自定义实现直接存文本列)。
  /// 默认实现调 [getSettings] 再编码; 子类一般无需重写。
  Future<Map<String, dynamic>?> getSettingsJson({String? userId}) async {
    final s = await getSettings(userId: userId);
    return s == null ? null : encodeReadingSettings(s);
  }
}
