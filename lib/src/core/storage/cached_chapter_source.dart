import 'dart:async';

import '../models/chapter_source.dart';
import 'cached_chapter.dart';
import 'reader_repository.dart';

/// 基于 [ReaderRepository] 章节缓存的 [ChapterSource] 实现。
///
/// 实现「本地缓存优先」的按章加载:
/// - **目录(标题)**: 构造时一次性载入全部章节标题(轻量, 不含正文), 供
///   [chapterTitle] / [chapterCount] 使用。标题来源由 [titles] 提供(宿主在
///   构造前从 `getBookChapters` 或网络解析得到)。
/// - **正文**: [loadContent] 按章 index 异步读取, 优先命中本地缓存
///   ([ReaderRepository.getCachedChapter]); 未命中时调用 [onMissing] 回调由
///   宿主提供(典型: 拉网络或抛错)。对齐原生 legado 章节正文按章从 DB 读。
///
/// 与全量内存模型([ChapterSource.fromMemory])的区别: 正文不在内存常驻,
/// 仅在 [loadContent] 被调时取一次; controller 配合可在使用后释放窗口外章。
class CachedChapterSource implements ChapterSource {
  /// 构造一个本地缓存优先的章节源。
  ///
  /// [titles] 是全部章节标题列表(顺序即章节 index), 决定 [chapterCount]。
  /// [repository] / [bookId] 用于按章读取正文。
  /// [onMissing] 处理缓存未命中的章: 返回该章正文(宿主可在此拉网络),
  ///   返回 null 则视为无内容; 默认直接返回 null。
  CachedChapterSource({
    required List<String> titles,
    required ReaderRepository repository,
    required String bookId,
    Future<String?> Function(int index, String title)? onMissing,
  })  : _titles = List<String>.unmodifiable(titles),
        _repository = repository,
        _bookId = bookId,
        _onMissing = onMissing;

  final List<String> _titles;
  final ReaderRepository _repository;
  final String _bookId;
  final Future<String?> Function(int index, String title)? _onMissing;

  /// 正文的内存窗口缓存: index → 已加载正文。
  ///
  /// [loadContent] 首次从 DB 读后会缓存于此, 避免同章反复查库。controller 可
  /// 通过 [evict] 释放窗口外章, 对齐 legado「内存只驻留相邻三章」。
  final Map<int, String> _window = {};

  @override
  int get chapterCount => _titles.length;

  @override
  String chapterTitle(int index) =>
      (index >= 0 && index < _titles.length) ? _titles[index] : '';

  @override
  Future<void> ensureCached() async {
    // 缓存已就绪由 repository 保证, 无需预热。宿主负责在构造前回填网络正文。
  }

  @override
  Future<String?> loadContent(int index) async {
    if (index < 0 || index >= _titles.length) return null;
    // 1. 内存窗口命中
    final cached = _window[index];
    if (cached != null) return cached;
    // 2. 本地 DB 命中
    final row = await _repository.getCachedChapter(_bookId, index);
    if (row != null) {
      _window[index] = row.content;
      return row.content;
    }
    // 3. 缓存未命中: 交宿主处理(如拉网络并回填)
    final fallback = await _onMissing?.call(index, _titles[index]);
    if (fallback != null) {
      _window[index] = fallback;
      try {
        await _repository.saveChapterContent(
          _bookId,
          index,
          _titles[index],
          fallback,
        );
      } catch (_) {
        // 回填失败不影响本次返回: 正文已在内存窗口, 下次仍可命中 onMissing。
      }
    }
    return fallback;
  }

  /// 预取一个窗口范围([fromIndex, toIndex] 闭区间)的正文到内存。
  ///
  /// 用 [getCachedChaptersInRange] 一次读取区间内已缓存章节(命中索引),
  /// 对齐 legado 相邻章预取。未缓存章不在此填充(留给 [loadContent] 按需处理)。
  Future<void> prefetchRange(int fromIndex, int toIndex) async {
    if (fromIndex > toIndex) return;
    final clampedFrom = fromIndex.clamp(0, _titles.length - 1);
    final clampedTo = toIndex.clamp(0, _titles.length - 1);
    if (clampedFrom > clampedTo) return;
    final rows = await _repository.getCachedChaptersInRange(
      _bookId,
      clampedFrom,
      clampedTo,
    );
    for (final r in rows) {
      _window[r.chapterIndex] = r.content;
    }
  }

  /// 释放窗口外章的正文, 回收内存。
  ///
  /// [keepIndices] 中的章保留(通常是当前章 ± N); 其余从内存窗口移除。
  /// 下次访问时 [loadContent] 会重新从 DB 读取。
  void evict(Iterable<int> keepIndices) {
    final keep = Set<int>.of(keepIndices);
    _window.removeWhere((index, _) => !keep.contains(index));
  }

  /// 从 [CachedChapter] 列表构造(标题从缓存行提取, 正文懒加载)。
  ///
  /// 便捷构造: 当宿主已通过 [ReaderRepository.getBookChapters] 拿到全书缓存时,
  /// 可直接传入, 标题从各行 [CachedChapter.title] 提取, 正文仍走 [loadContent]
  /// 按章读(避免内存常驻全书)。注意: 此构造要求 [chapters] 覆盖全部章且按 index
  /// 升序; 否则用主构造手动传 [titles]。
  factory CachedChapterSource.fromCached({
    required List<CachedChapter> chapters,
    required ReaderRepository repository,
    required String bookId,
    Future<String?> Function(int index, String title)? onMissing,
  }) {
    final sorted = List<CachedChapter>.from(chapters)
      ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
    return CachedChapterSource(
      titles: sorted.map((c) => c.title).toList(growable: false),
      repository: repository,
      bookId: bookId,
      onMissing: onMissing,
    );
  }
}
