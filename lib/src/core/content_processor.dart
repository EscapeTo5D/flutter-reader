class BookContent {
  final List<String> textList;
  final bool sameTitleRemoved;

  const BookContent({
    required this.textList,
    this.sameTitleRemoved = false,
  });
}

/// 内容处理器 — 对应原生 Legado ContentProcessor
///
/// 负责去除重复标题、添加标题等内容预处理
class ContentProcessor {
  /// 处理章节内容
  ///
  /// 1. 去除内容开头的重复标题（防止源内容自带标题导致重复）
  /// 2. 如果 [includeTitle] 为 true，在内容最前面插入标题
  /// 3. 按段落分割并添加缩进
  static BookContent getContent({
    required String title,
    required String content,
    required String bookName,
    required int textIndent,
    bool includeTitle = true,
  }) {
    var mContent = content;
    var sameTitleRemoved = false;

    if (mContent == 'null') mContent = '';

    // 1. 去除重复标题
    if (mContent.isNotEmpty) {
      final removed = _removeDuplicateTitle(
        content: mContent,
        bookName: bookName,
        title: title,
      );
      mContent = removed.content;
      sameTitleRemoved = removed.removed;
    }

    // 2. 重新添加标题
    if (includeTitle && title.isNotEmpty) {
      mContent = '$title\n$mContent';
    }

    // 3. 按段落分割，添加缩进
    final indentStr = textIndent > 0 ? '\u3000' * textIndent : '';
    final paragraphs = <String>[];
    final isFirstTitle = includeTitle && title.isNotEmpty;

    final lines = mContent.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final paragraph = lines[i].trim();
      if (paragraph.isEmpty) continue;

      if (i == 0 && isFirstTitle) {
        // 标题行不加缩进
        paragraphs.add(paragraph);
      } else {
        paragraphs.add('$indentStr$paragraph');
      }
    }

    return BookContent(
      textList: paragraphs,
      sameTitleRemoved: sameTitleRemoved,
    );
  }

  /// 去除内容开头的重复标题
  ///
  /// 对应原生 ContentProcessor 中的去除重复标题逻辑：
  /// 匹配 ^(\\s|\\p{P}|bookName)*title(\\s)* 模式
  static _RemoveResult _removeDuplicateTitle({
    required String content,
    required String bookName,
    required String title,
  }) {
    if (title.isEmpty) return _RemoveResult(content: content, removed: false);

    // 构建匹配模式: 开头可能有空白、标点、书名，然后是标题，最后是空白
    final escapedTitle = RegExp.escape(title);
    final escapedBookName = RegExp.escape(bookName);
    final pattern = RegExp(
      r'^[\s\u0000-\u002F\u003A-\u0040\u005B-\u0060\u007B-\u007E\u2000-\u206F\u3000-\u303F\uFF00-\uFFEF'
      + escapedBookName + r']*' + escapedTitle + r'[\s]*',
      caseSensitive: false,
    );

    final match = pattern.firstMatch(content);
    if (match != null && match.end > 0) {
      return _RemoveResult(
        content: content.substring(match.end),
        removed: true,
      );
    }

    return _RemoveResult(content: content, removed: false);
  }
}

class _RemoveResult {
  final String content;
  final bool removed;

  const _RemoveResult({required this.content, required this.removed});
}
