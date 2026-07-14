import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/aloud/text_slicer.dart';
import 'package:flutter_reader/src/core/content_processor.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';

/// TextSlicer 偏移对齐测试。
///
/// 核心断言: TextSlicer 切段得到的 `AloudParagraph.charOffsetInChapter` 必须
/// 等于 PageEngine 排版后该段首个非空 TextLine 的 `chapterPosition`。两者都
/// 基于 `ContentProcessor.getContent(...).textList.join('\n')` 这份含缩进的
/// 预处理文本, 偏移同源才能让朗读高亮与翻页联动不错位。
///
/// 对应原生 legado: `getNeedReadAloud(...).split("\n")` 的段起点与
/// `TextChapter.getReadLength` 的页起点用同一套字符偏移流。
void main() {
  final engine = PageEngine();
  final settings = ReadingSettings();

  /// 用 ContentProcessor 生成预处理内容(含缩进、含标题行), 返回 (joined, paragraphs)。
  (String, List<String>) process({
    required String title,
    required String content,
    int textIndent = 2,
  }) {
    final book = ContentProcessor.getContent(
      title: title,
      content: content,
      bookName: '测试书',
      textIndent: textIndent,
    );
    return (book.textList.join('\n'), book.textList);
  }

  test('空内容切成空列表', () {
    expect(TextSlicer.slice(''), isEmpty);
  });

  test('单段: 切段偏移 == 排版首行 chapterPosition', () {
    final (joined, _) =
        process(title: '第一章', content: '这是一段正文内容。');
    final slices = TextSlicer.slice(joined);
    // 预处理: 标题行 + 缩进正文行 → 2 段
    expect(slices.length, 2);
    expect(slices[0].text, '第一章');
    expect(slices[0].charOffsetInChapter, 0);

    final pages = engine.paginate(
      content: joined,
      pageSize: const Size(360.0, 600.0),
      settings: settings,
    );
    // 找到正文段(非标题)的首行
    final bodyLine = pages.expand((p) => p.lines).firstWhere(
          (l) => l.text.isNotEmpty && !l.isTitle,
        );
    // 正文段偏移应等于 slices[1].charOffsetInChapter(标题长度 + \n)
    expect(
      bodyLine.chapterPosition,
      slices[1].charOffsetInChapter,
      reason: '正文段排版偏移应与切段偏移一致',
    );
    // 标题段偏移也应一致
    final titleLine = pages.expand((p) => p.lines).firstWhere(
          (l) => l.isTitle,
        );
    expect(titleLine.chapterPosition, slices[0].charOffsetInChapter);
  });

  test('多段: 各段切段偏移 == 排版各段首行 chapterPosition', () {
    final (joined, _) = process(
      title: '测试',
      content: '甲段正文。\n乙段正文。\n丙段正文。',
    );
    final slices = TextSlicer.slice(joined);
    expect(slices.length, 4); // 标题 + 3 段

    final pages = engine.paginate(
      content: joined,
      pageSize: const Size(360.0, 600.0),
      settings: settings,
    );

    // 收集排版后所有非空文字行的 (text, chapterPosition), 按段分组
    // 每段的首行偏移应与切段偏移对齐
    final allLines = pages.expand((p) => p.lines).where((l) => l.text.isNotEmpty).toList();

    // 标题段
    expect(allLines.first.chapterPosition, slices[0].charOffsetInChapter);
    // 正文各段: 用切段偏移在排版行里找匹配
    for (var i = 1; i < slices.length; i++) {
      final expected = slices[i].charOffsetInChapter;
      final matching = allLines.where((l) => l.chapterPosition == expected).toList();
      expect(
        matching,
        isNotEmpty,
        reason: '切段偏移 $expected (段$i) 应能在排版行中找到对应 chapterPosition',
      );
    }
  });

  test('纯标点段(分隔符)被过滤但偏移照常累加', () {
    // 直接构造含 *** 分隔符的预处理文本(绕过 ContentProcessor 它会保留)
    final joined = '正文一\n***\n正文二';
    final slices = TextSlicer.slice(joined);
    // *** 被过滤, 只剩 2 段
    expect(slices.length, 2);
    expect(slices[0].text, '正文一');
    expect(slices[0].charOffsetInChapter, 0);
    expect(slices[1].text, '正文二');
    // 正文一(3) + \n(1) + ***(3) + \n(1) = 8
    expect(slices[1].charOffsetInChapter, 8);
  });

  test('空行被跳过但偏移累加', () {
    final joined = '甲\n\n\n乙';
    final slices = TextSlicer.slice(joined);
    expect(slices.length, 2);
    expect(slices[0].charOffsetInChapter, 0);
    // 甲(1) + \n(1) + 空(0) + \n(1) + 空(0) + \n(1) = 4
    expect(slices[1].charOffsetInChapter, 4);
  });

  test('缩进字符计入偏移(与 chapterPosition 同源)', () {
    // 模拟 ContentProcessor 输出: 缩进 \u3000\u3000 + 正文
    final joined = '\u3000\u3000缩进正文';
    final slices = TextSlicer.slice(joined);
    expect(slices.length, 1);
    expect(slices[0].charOffsetInChapter, 0); // 段首含缩进
    expect(slices[0].text, '\u3000\u3000缩进正文'); // 含缩进原样保留

    final pages = engine.paginate(
      content: joined,
      pageSize: const Size(360.0, 600.0),
      settings: settings,
    );
    final line = pages.expand((p) => p.lines).firstWhere((l) => l.text.isNotEmpty);
    // 排版首行偏移也是 0(段首), 与切段一致
    expect(line.chapterPosition, slices[0].charOffsetInChapter);
  });

  test('切段文本可 trim 后喂 TTS(缩进不影响发音)', () {
    final joined = '\u3000\u3000你好世界';
    final slices = TextSlicer.slice(joined);
    final speakText = slices[0].text.trim();
    expect(speakText, '你好世界');
    expect(speakText.isNotEmpty, true);
  });
}
