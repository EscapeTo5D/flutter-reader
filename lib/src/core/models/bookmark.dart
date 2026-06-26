class Bookmark {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int pageIndex;
  final String content;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.pageIndex,
    required this.content,
    required this.createdAt,
  });
}
