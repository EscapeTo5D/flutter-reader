import 'dart:async';

import '../../aloud/aloud_settings.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../models/reading_settings_codec.dart';
import 'cached_chapter.dart';
import 'reading_progress.dart';
import 'reading_style_preset.dart';
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

  // ─────────────────────────── 章节正文缓存 ───────────────────────────
  //
  // 章节正文与用户无关(同书 A 用户的第 N 章 = B 用户的第 N 章), 故仅按
  // (bookId, chapterIndex) 复合键存储, 不走 userId 隔离。用于「二次打开秒开」:
  // 首次打开从网络拉取的正文落盘后, 后续直接读本地。宿主据此组合「本地优先」策略。

  /// 读取某书已缓存的全部章节(按 chapter_index 升序)。
  ///
  /// 二次打开的主路径: 一次拿回全书正文, 命中即可瞬时渲染。
  /// 未缓存的书返回空列表——调用方应回退到网络拉取, 下完后用 [saveChapterContent]
  /// 回填, 下次即命中。
  Future<List<CachedChapter>> getBookChapters(String bookId);

  /// 读取某书指定章的缓存正文。无记录返回 null。
  ///
  /// 用于按章预取/恢复(如只校验某一章是否已缓存)。
  Future<CachedChapter?> getCachedChapter(String bookId, int chapterIndex);

  /// 读取某书在 [fromIndex, toIndex] 闭区间内已缓存的章节(按 chapter_index 升序)。
  ///
  /// 用于「当前章 ± N 章」窗口按需加载: 只读窗口内已缓存章节, 未缓存的 index
  /// 不在结果中(调用方据此判断哪些需走网络)。缺省实现基于 [getBookChapters] 过滤,
  /// 数据库实现应用 `BETWEEN` 命中主键索引, 避免全表扫描全书。
  Future<List<CachedChapter>> getCachedChaptersInRange(
    String bookId,
    int fromIndex,
    int toIndex,
  );

  /// 写入/覆盖某章正文缓存(upsert, 主键 bookId+chapterIndex)。
  ///
  /// 网络拉取到章节正文后调用, 落盘供下次本地命中。
  Future<void> saveChapterContent(
    String bookId,
    int chapterIndex,
    String title,
    String content,
  );

  /// 批量写入多章正文缓存(单事务 upsert)。
  ///
  /// 用于网络一次拉全书后的回填: 比循环调用 [saveChapterContent](每章一个事务)
  /// 快得多。缺省实现退化为循环单条写; 数据库实现应用 batch 提交。
  Future<void> saveChapterContents(
    String bookId,
    Iterable<CachedChapter> chapters,
  );

  // ─────────────────────────── 用户样式预设 ───────────────────────────
  //
  // 用户在「设置弹窗 → 颜色与背景」点「+」新建的自定义预设(bg/text 色),
  // 按 userId 隔离。内置 6 个预设(微信读书/预设1~5)不在 DB 内, 由 UI 硬编码,
  // 仅用户自定义预设走 DB。用于持久化用户配色, 重启不丢。

  /// 读取某用户的全部自定义预设(按 sort_order 升序)。
  Future<List<ReadingStylePreset>> getStylePresets(String userId);

  /// 保存/覆盖预设(按 id upsert)。
  Future<void> saveStylePreset(ReadingStylePreset preset);

  /// 删除预设(按 id)。
  Future<void> deleteStylePreset(String presetId);

  // ─────────────────────────── 朗读配置 ───────────────────────────
  //
  // 朗读子系统的全局配置(语速/引擎类型/跟随系统), 对齐原生 legado 的全局
  // SharedPreferences(`ttsSpeechRate`/`appTtsEngine`/`ttsFollowSys`)。
  // 与阅读进度/书签不同: 朗读配置与书无关、与用户无关(全局), 复用 `settings` 表
  // 的 KV 结构, 用专用 key `'__aloud__'` 存, 不加新表、不升 schema。

  /// 读取全局朗读配置。未配置返回 null(调用方回落 [AloudSettings.defaults])。
  Future<AloudSettings?> getAloudSettings();

  /// 保存/覆盖全局朗读配置。
  Future<void> saveAloudSettings(AloudSettings settings);

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
