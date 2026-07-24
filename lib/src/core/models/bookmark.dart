class Bookmark {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int pageIndex;
  final String content;
  final DateTime createdAt;

  /// 书签的「原文」片段(对齐原生 legado `Bookmark.bookText`)。
  ///
  /// 快速加书签时取整页正文(`page.text.trim()`); Dialog 编辑时可改写。
  /// 旧书签(v3 schema 前)可能为空串。
  final String bookText;

  /// 关联的字符偏移(章内), 用于跨字号/换设备后定位回对应页。
  /// 可选: 旧书签可能没有; null 时回退用 [pageIndex] 定位。
  final int? chapterCharOffset;

  /// 所属用户 id(多用户隔离用)。null = 不绑定用户(全局书签)。
  final String? userId;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.pageIndex,
    required this.content,
    required this.createdAt,
    required this.bookText,
    this.chapterCharOffset,
    this.userId,
  });

  Bookmark copyWith({
    String? id,
    String? bookId,
    int? chapterIndex,
    int? pageIndex,
    String? content,
    DateTime? createdAt,
    String? bookText,
    int? chapterCharOffset,
    String? userId,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      pageIndex: pageIndex ?? this.pageIndex,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      bookText: bookText ?? this.bookText,
      chapterCharOffset: chapterCharOffset ?? this.chapterCharOffset,
      userId: userId ?? this.userId,
    );
  }

  /// 序列化为可 JSON 存储的 Map(不含 [userId], 用户隔离由表列承载)。
  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'chapterIndex': chapterIndex,
        'pageIndex': pageIndex,
        'content': content,
        'bookText': bookText,
        'createdAt': createdAt.toIso8601String(),
        if (chapterCharOffset != null) 'chapterCharOffset': chapterCharOffset,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json, {String? userId}) {
    return Bookmark(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      chapterIndex: (json['chapterIndex'] as num).toInt(),
      pageIndex: (json['pageIndex'] as num).toInt(),
      content: (json['content'] as String?) ?? '',
      bookText: (json['bookText'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      chapterCharOffset: (json['chapterCharOffset'] as num?)?.toInt(),
      userId: userId,
    );
  }
}
