/// 全书正文搜索的单条命中结果(对齐原生 legado `SearchResult`)。
///
/// 关键设计: [charOffsetInChapter] 是**预处理后章节正文**里的字符偏移,
/// 与 [TextLine.chapterPosition] / [ReadingProgress.chapterCharOffset]
/// / [AloudParagraph.charOffsetInChapter] 同源坐标系。
///
/// 搜索算法在 `ContentProcessor.getContent` 输出的 `textList.join('\n')` 字符串里
/// 做 `indexOf`, 得到的偏移直接就是同源坐标, 跳转时喂
/// `ReadingController.pageIndexForCharOffset` 即可落页, 无需换算。
/// 这与朗读子系统 `TextSlicer` 的切段偏移策略完全一致(见 AGENTS.md)。
///
/// [TextLine]: ../../reader/entities/text_page.dart
/// [ReadingProgress]: reading_progress.dart
/// [AloudParagraph]: ../../aloud/text_slicer.dart
class ReaderSearchResult {
  /// 搜索关键词。
  final String query;

  /// 命中所在章的索引(0-based)。
  final int chapterIndex;

  /// 命中所在章的标题。
  final String chapterTitle;

  /// 上下文片段: 关键词 + 前后各约 20 字(对齐原生 `SearchResult.resultText`)。
  final String snippet;

  /// 关键词在 [snippet] 中的起始偏移(高亮渲染用)。
  final int queryIndexInSnippet;

  /// 关键词在**预处理后**章节正文中的字符偏移(跳转落页用, 同源于 chapterPosition)。
  final int charOffsetInChapter;

  const ReaderSearchResult({
    required this.query,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.queryIndexInSnippet,
    required this.charOffsetInChapter,
  });

  @override
  String toString() =>
      'ReaderSearchResult(ch=$chapterIndex, off=$charOffsetInChapter, q="$query")';
}

/// 从 [SearchContentPage] 回带给阅读页的数据: 全部结果 + 用户选中的索引。
///
/// 对齐原生 `IntentData["searchResultList"]` + `index` extra。阅读页据此进入
/// 「搜索结果浏览态」(左右导航 FAB), 并跳到 [results][index]。
class SearchResultBrowseData {
  final List<ReaderSearchResult> results;
  final int selectedIndex;

  const SearchResultBrowseData(this.results, this.selectedIndex);
}
