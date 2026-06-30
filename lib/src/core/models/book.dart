import 'chapter_source.dart';

class Book {
  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final List<Chapter> chapters;
  int currentChapterIndex;
  int currentPageIndex;

  /// 章节正文按需加载源(可选)。
  ///
  /// 设置后, [ReadingController] 走「按章加载」路径: 只在需要时(当前章/相邻章)
  /// 通过 [ChapterSource.loadContent] 懒加载正文, 内存不驻留全书。对齐原生 legado
  /// 相邻三章缓存的内存模型。
  ///
  /// 为 null 时退化为旧的全量内存路径(直接读 [chapters] 的 content)。
  /// 二者不互斥: [chapters] 可仅用于目录标题, 正文由 [chapterSource] 提供。
  final ChapterSource? chapterSource;

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.coverUrl,
    this.chapters = const [],
    this.chapterSource,
    this.currentChapterIndex = 0,
    this.currentPageIndex = 0,
  });

  Chapter? get currentChapter =>
      chapters.isNotEmpty ? chapters[currentChapterIndex] : null;

  /// 序列化元信息(不含 [chapters] 正文, 正文太重且走网络 API, 不该落盘)。
  /// 用于书架记录: id/title/author/coverUrl + 上次阅读位置。
  Map<String, dynamic> toMetaJson() => {
        'id': id,
        'title': title,
        'author': author,
        if (coverUrl != null) 'coverUrl': coverUrl,
        'currentChapterIndex': currentChapterIndex,
        'currentPageIndex': currentPageIndex,
      };

  /// 从元信息 JSON 重建 Book(无章节正文, chapters 为空)。
  /// 宿主通常先 fromMetaJson 拿到书架项, 点击时再按 id 走网络拉取章节正文。
  factory Book.fromMetaJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String,
        author: (json['author'] as String?) ?? '',
        coverUrl: json['coverUrl'] as String?,
        currentChapterIndex: (json['currentChapterIndex'] as num?)?.toInt() ?? 0,
        currentPageIndex: (json['currentPageIndex'] as num?)?.toInt() ?? 0,
      );
}

class Chapter {
  final String id;
  final String title;
  final String content;
  final int index;

  Chapter({
    required this.id,
    required this.title,
    required this.content,
    required this.index,
  });
}
