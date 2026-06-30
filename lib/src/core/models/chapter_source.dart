import 'chapter_meta.dart';

/// 章节正文按需加载源。
///
/// 这是「按章加载」的抽象边界, 对齐原生 legado 的数据源概念: legado 的
/// `DataSource` 只持有 prev/cur/next 相邻三章, 章节正文从本地 DB 按章按需读取,
/// 而非一次性把全书正文常驻内存。
///
/// 本抽象把「目录(标题)」与「正文」分离:
/// - [chapterCount] / [chapterTitle]: 轻量元信息, 供目录页/书架/总进度使用,
///   不触发正文加载。
/// - [loadContent]: 按章索引懒加载正文, null 表示加载失败或无内容。
///
/// Controller 依赖此抽象而非 `Book.chapters` 全量内存, 从而:
/// - 内存只驻留「当前章 ± N 章」窗口的正文(对齐 legado 相邻三章);
/// - 翻到未加载的章时才触发加载, 首屏只加载/排版当前章。
///
/// 宿主负责提供实现, 例如 [CachedChapterSource](本地缓存优先→网络回填)。
abstract class ChapterSource {
  /// 章节总数(用于目录长度、总进度、翻章边界判断)。
  int get chapterCount;

  /// 指定章的标题(目录用)。越界返回空串。
  ///
  /// 不应触发正文加载——标题是轻量元信息, 应与正文解耦。
  String chapterTitle(int index);

  /// 异步加载指定章正文。返回 null 表示加载失败或无内容。
  ///
  /// 实现应保证幂等(同 index 多次调用返回一致内容), 且优先命中本地缓存。
  Future<String?> loadContent(int index);

  /// 预热/确保缓存就绪(可选)。
  ///
  /// 典型场景: 首次打开网络未命中时, 宿主在此拉全书并回填本地缓存。
  /// 之后 [loadContent] 即命中本地, 秒开。默认空实现(已缓存/无需预热时)。
  Future<void> ensureCached() async {}

  /// 构造一个直接由内存数据驱动的 [ChapterSource](用于测试或小书)。
  ///
  /// [chapters] 为「标题+正文」的元组列表, [ChapterSource] 直接持有全部正文。
  /// 仅推荐小数据量场景; 大书请用懒加载实现(如 [CachedChapterSource])。
  factory ChapterSource.fromMemory(List<ChapterMeta> chapters) =>
      _MemoryChapterSource(chapters);
}

/// 内存直接驱动的 [ChapterSource](全量正文常驻内存)。
///
/// 这是「按章加载」的退化路径: 当无本地缓存、且宿主不愿实现懒加载时,
/// 可直接把全书章节灌入。行为等价于旧的 `Book.chapters` 全量内存模型,
/// 但统一走 [ChapterSource] 抽象, controller 无需区分代码路径。
class _MemoryChapterSource implements ChapterSource {
  _MemoryChapterSource(this._chapters);
  final List<ChapterMeta> _chapters;

  @override
  int get chapterCount => _chapters.length;

  @override
  String chapterTitle(int index) =>
      (index >= 0 && index < _chapters.length) ? _chapters[index].title : '';

  @override
  Future<String?> loadContent(int index) async {
    if (index < 0 || index >= _chapters.length) return null;
    return _chapters[index].content;
  }

  @override
  Future<void> ensureCached() async {}
}
