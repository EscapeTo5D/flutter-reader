/// 朗读进度坐标(对应原生 legado `readAloudNumber` + `nowSpeak` + `paragraphStartPos`)。
///
/// 三层坐标, 自上而下精度递增:
/// - [chapterCharOffset]  章内字符绝对偏移(对应原生 `readAloudNumber`)。
///   与 [TextLine.chapterPosition] / [ReadingProgress.chapterCharOffset] **同源**,
///   都指向「预处理后章节内容」(`ContentProcessor.getContent(...).textList.join('\n')`)。
///   故朗读进度可直接喂给 [ReadingProgress] 持久化, 复用现有进度表与恢复逻辑。
/// - [paragraphIndex]     段下标(对应原生 `nowSpeak`, 在 `TextSlicer` 切段数组中的位置)。
/// - [charOffsetInParagraph] 段内偏移(对应原生 `paragraphStartPos`, 逐字高亮用)。
///
/// 此 value object 不可变, 每次进度推进产生新实例。
class AloudCursor {
  /// 当前章节序号。
  final int chapterIndex;

  /// 章内字符绝对偏移 = 当前段首偏移 + 段内偏移。
  ///
  /// 用于翻页联动(与各页首行 `chapterPosition` 比对)与进度持久化。
  final int chapterCharOffset;

  /// 当前段在 `TextSlicer` 切段数组中的下标。
  final int paragraphIndex;

  /// 段内已读字符偏移(0 = 段首)。逐字高亮用。
  final int charOffsetInParagraph;

  const AloudCursor({
    required this.chapterIndex,
    required this.chapterCharOffset,
    required this.paragraphIndex,
    required this.charOffsetInParagraph,
  });

  AloudCursor copyWith({
    int? chapterIndex,
    int? chapterCharOffset,
    int? paragraphIndex,
    int? charOffsetInParagraph,
  }) {
    return AloudCursor(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCharOffset: chapterCharOffset ?? this.chapterCharOffset,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      charOffsetInParagraph:
          charOffsetInParagraph ?? this.charOffsetInParagraph,
    );
  }

  @override
  String toString() =>
      'AloudCursor(ch=$chapterIndex, off=$chapterCharOffset, para=$paragraphIndex, '
      'inPara=$charOffsetInParagraph)';
}
