/// 朗读文本切分器(对应原生 legado `TextChapter.getNeedReadAloud` + `AppPattern.notReadAloudRegex`)。
///
/// 把章节预处理后的全文(`ContentProcessor.getContent(...).textList.join('\n')`)
/// 切成可朗读的段落列表, 同时记录每段在章内的绝对字符偏移(与
/// [TextLine.chapterPosition] / [ReadingProgress.chapterCharOffset] **同源**)。
///
/// ⚠️ **偏移与缩进对齐(关键正确性细节)**:
/// `chapterPosition` 在 `PageEngine._wrapText`(`page_engine.dart:305-321`)中基于
/// **剥缩进后的 body** 计算: 段首行 = `baseOffset`(= 段在含缩进源文本里的起点),
/// 续行 = `baseOffset + 行在 body 内偏移`。即 chapterPosition 的增量步长是
/// **剥缩进后的字符**, 续行的偏移不含缩进。
///
/// 为与之同源, [AloudParagraph.text] 也**剥掉源缩进**(`body = raw 去前导空白`),
/// 而 [AloudParagraph.charOffsetInChapter] 仍取段首 `paraStart`(含缩进源文本的
/// 起点, 与段首行 chapterPosition=baseOffset 相等)。这样 `_loadChapterAndPlay`
/// 用 `charOffset - paraStart` 算出的 prefix 直接就是 body 内偏移, 喂引擎的
/// `text.substring(prefix)` 恰好从「页首第一个可见字」起读 —— 续行场景不错位、
/// 不多读缩进字符。对齐原生 legado `getNeedReadAloud` 同样去缩进的语义。
///
/// 单测覆盖见 `test/text_slicer_test.dart`。
class AloudParagraph {
  /// 该段文本(**已剥源缩进**, 如源 `　　正文` → `正文`)。直接喂给 TTS。
  final String text;

  /// 该段在章节预处理内容中的**段首**起始字符偏移(含缩进源文本里的起点)。
  ///
  /// 等于该段排版首行的 `chapterPosition`(= baseOffset), 用于 [AloudCursor] 对齐。
  /// ⚠️ 本字段是段首偏移; 段内某字符的偏移需用 `charOffsetInChapter + 段内下标`
  /// (因 [text] 已剥缩进, 段内下标与剥缩进 body 偏移一致)。
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

  /// 剥源缩进正则: 去掉段落前导空白(全角空格 \u3000 + 普通空白)。
  ///
  /// 与 `PageEngine._wrapText` 的 `body = text.replaceFirst(RegExp(r'^[\s\u3000]+'), '')`
  /// **完全一致**, 保证切段 body 与排版 body 同源 → 偏移对齐。
  static final _indentRegex = RegExp(r'^[\s\u3000]+');

  /// 把章节预处理后的全文切成可读段落列表。
  ///
  /// [processedChapterContent] 必须是
  /// `ContentProcessor.getContent(...).textList.join('\n')` 的结果(含缩进)。
  /// 空段和纯标点段被过滤, 但偏移照常累加(保持段首 charOffsetInChapter 与
  /// chapterPosition 单调一致)。每段 [text] 剥掉源缩进, 与 page_engine 的 body 同源。
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

      // 剥源缩进(与 page_engine._wrapText 的 body 一致), 使段内偏移与
      // chapterPosition 的 body 偏移同源。⚠️ paraStart 仍用含缩进源文本的起点
      // (不因剥缩进而改变), 保持与段首行 chapterPosition=baseOffset 相等。
      final body = raw.replaceFirst(_indentRegex, '');
      result.add(AloudParagraph(text: body, charOffsetInChapter: paraStart));
    }
    return result;
  }
}
