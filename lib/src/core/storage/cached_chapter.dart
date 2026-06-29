/// 章节正文缓存记录(对应 `chapter_contents` 表一行)。
///
/// 用于「二次打开秒开」: 首次打开从网络拉取的全书章节正文落盘后,
/// 后续打开直接从本地读取, 跳过全网请求。
///
/// **不走 userId 隔离**: 章节正文是书的内容, 与用户无关(同书 A 用户的第 3 章
/// = B 用户的第 3 章), 故仅按 `bookId` + `chapterIndex` 复合键存储, 避免冗余。
/// (进度/书签仍按 userId 隔离, 见 [ReaderRepository] 其它方法。)
class CachedChapter {
  final String bookId;
  final int chapterIndex;
  final String title;
  final String content;

  const CachedChapter({
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    required this.content,
  });

  @override
  String toString() =>
      'CachedChapter(bookId: $bookId, index: $chapterIndex, title: $title, '
      'content: ${content.length} chars)';
}
