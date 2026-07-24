import '../models/bookmark.dart';

/// 阅读进度记录(按 用户 × 书 隔离)。
///
/// 进度存 **章内字符偏移** [chapterCharOffset] 而非页码, 这样:
/// - 改字号/行距/换设备重排后, 用 charOffset 二分各页首行的
///   `TextLine.chapterPosition` 即可定位回对应页, 不丢进度(对齐原生 legado dur)。
/// - [chapterIndex] 决定章节; [chapterCharOffset] 决定章内位置。
///
/// [pageIndex] 仅作降级用(旧数据/无 chapterPosition 时回退), 不作为恢复主依据。
class ReadingProgress {
  final String userId;
  final String bookId;

  /// 当前章节序号(从 0 起)。
  final int chapterIndex;

  /// 章内字符偏移(基于「预处理后的章节内容」, 见 PageEngine.chapterPosition)。
  final int chapterCharOffset;

  /// 上次记录时的页码(降级用, 恢复时优先用 chapterCharOffset)。
  final int? pageIndex;

  /// 最近阅读时间。
  final DateTime lastReadAt;

  const ReadingProgress({
    required this.userId,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterCharOffset,
    this.pageIndex,
    required this.lastReadAt,
  });

  ReadingProgress copyWith({
    String? userId,
    String? bookId,
    int? chapterIndex,
    int? chapterCharOffset,
    int? pageIndex,
    DateTime? lastReadAt,
  }) {
    return ReadingProgress(
      userId: userId ?? this.userId,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCharOffset: chapterCharOffset ?? this.chapterCharOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'bookId': bookId,
        'chapterIndex': chapterIndex,
        'chapterCharOffset': chapterCharOffset,
        if (pageIndex != null) 'pageIndex': pageIndex,
        'lastReadAt': lastReadAt.toIso8601String(),
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      userId: json['userId'] as String,
      bookId: json['bookId'] as String,
      chapterIndex: (json['chapterIndex'] as num).toInt(),
      chapterCharOffset: (json['chapterCharOffset'] as num?)?.toInt() ?? 0,
      pageIndex: (json['pageIndex'] as num?)?.toInt(),
      lastReadAt: json['lastReadAt'] is String
          ? DateTime.parse(json['lastReadAt'] as String)
          : DateTime.now(),
    );
  }

  /// 与书签的进度兼容表示(便于书签也用 charOffset 定位)。
  Bookmark toBookmark({required String bookmarkId, required String content}) =>
      Bookmark(
        id: bookmarkId,
        bookId: bookId,
        chapterIndex: chapterIndex,
        pageIndex: pageIndex ?? 0,
        content: content,
        bookText: '',
        createdAt: lastReadAt,
        chapterCharOffset: chapterCharOffset,
        userId: userId,
      );
}
