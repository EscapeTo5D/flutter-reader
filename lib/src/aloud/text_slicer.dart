/// 朗读文本切分器(对应原生 legado `TextChapter.getNeedReadAloud` + `AppPattern.notReadAloudRegex`)。
///
/// 把章节预处理后的全文(`ContentProcessor.getContent(...).textList.join('\n')`)
/// 切成可朗读的段落列表, 同时记录每段在章内的绝对字符偏移(与
/// [TextLine.chapterPosition] / [ReadingProgress.chapterCharOffset] **同源**)。
///
/// ⚠️ **偏移对齐(关键正确性细节)**:
/// `chapterPosition` 在 `PageEngine._wrapText`(`page_engine.dart:308-321`)中按
/// `bodyOffset = baseOffset + (startOffset - indentStr.length).clamp(0, body.length)`
/// 计算, 指向**含缩进**的预处理文本。`TextSlicer` 输入必须用同一份 join('\n')
/// 文本(含缩进字符), 切段时**不剥缩进**, 累加偏移 `raw.length + 1`(含 \n),
/// 这样第 N 段的 [AloudParagraph.charOffsetInChapter] 才等于排版后该段首行的
/// `chapterPosition`, 高亮与翻页联动才不会错位。
///
/// 单测覆盖见 `test/text_slicer_test.dart`。
class AloudParagraph {
  /// 该段文本(含缩进字符, 如 `\u3000\u3000正文`)。喂给 TTS 前会去空白。
  final String text;

  /// 该段在章节预处理内容中的起始字符偏移(含缩进偏移)。
  ///
  /// 等于 `TextLine.chapterPosition` 同源值, 用于 [AloudCursor] 对齐。
  final int charOffsetInChapter;

  const AloudParagraph({
    required this.text,
    required this.charOffsetInChapter,
  });

  @override
  String toString() =>
      'AloudParagraph(off=$charOffsetInChapter, "${text.length > 16 ? '${text.substring(0, 16)}…' : text}")';
}

class TextSlicer {
  TextSlicer._();

  /// 纯标点 / 空白 / 符号 / 控制符段落过滤正则。
  ///
  /// 对应原生 `AppPattern.notReadAloudRegex = ^(\\s|\\p{C}|\\p{P}|\\p{Z}|\\p{S})+$`。
  /// 这类段落(如 `***` 分隔符、`---` 装饰线)无朗读价值, 跳过避免 TTS 读出怪音。
  /// `unicode: true` 启用 Unicode 属性转义。
  static final _skipRegex =
      RegExp(r'^[\s\p{C}\p{P}\p{Z}\p{S}]+$', unicode: true);

  /// 把章节预处理后的全文切成可读段落列表。
  ///
  /// [processedChapterContent] 必须是
  /// `ContentProcessor.getContent(...).textList.join('\n')` 的结果(含缩进)。
  /// 空段和纯标点段被过滤, 但偏移照常累加(保持与 `chapterPosition` 单调一致)。
  static List<AloudParagraph> slice(String processedChapterContent) {
    final result = <AloudParagraph>[];
    if (processedChapterContent.isEmpty) return result;

    // 兜底: 规范化换行符。ContentProcessor 理论上不产生 \r, 但书源正文可能含
    // \r\n。残留 \r 会让 split('\n') 后某段末尾带 \r, raw.length 多算 1 →
    // 偏移与 chapterPosition 错位。
    final normalized = processedChapterContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    var offset = 0;
    for (final raw in lines) {
      final paraStart = offset;
      offset += raw.length + 1; // +1 for '\n'

      // 空段跳过(对齐 ContentProcessor 跳过空行 + 引擎段距行不参与朗读)。
      // 注意 raw 可能是缩进填充段(如全 \u3000), 经 _skipRegex 也归入此类。
      if (raw.isEmpty) continue;
      if (_skipRegex.hasMatch(raw)) continue;

      result.add(AloudParagraph(text: raw, charOffsetInChapter: paraStart));
    }
    return result;
  }
}
