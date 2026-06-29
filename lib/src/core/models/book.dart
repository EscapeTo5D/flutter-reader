class Book {
  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final List<Chapter> chapters;
  int currentChapterIndex;
  int currentPageIndex;

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.coverUrl,
    this.chapters = const [],
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
