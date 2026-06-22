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
