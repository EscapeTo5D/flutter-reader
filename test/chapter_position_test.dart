import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/reader/entities/text_page.dart';

/// chapterPosition 字段: 用于阅读进度持久化(存 charOffset 而非 pageIndex)。
///
/// 进度恢复时用 charOffset 二分各页首行 chapterPosition 定位回对应页,
/// 这样改字号/行距重排后不丢进度(对齐原生 legado dur/durPos)。
void main() {
  final engine = PageEngine();
  final settings = ReadingSettings();
  // 宽度足够一行放下短句, 高度限制 4-5 行, 便于测分页。
  final pageSize = const Size(360.0, 120.0);

  /// 断言: 多页时, 各页首行 chapterPosition 单调递增。
  /// 二分定位要求"页内首行偏移"随页号递增。
  test('各页首行 chapterPosition 单调递增', () {
    final content = '第一段第一行文字内容\n第二段第二行文字内容\n第三段第三行文字内容';
    final pages = engine.paginate(
      content: content,
      pageSize: const Size(120.0, 100.0), // 窄高, 强制多页
      settings: settings,
    );

    expect(pages.length, greaterThan(1), reason: '应产生多页');

    final firstOffsets = <int>[];
    for (final page in pages) {
      final firstTextLine = page.lines
          .where((l) => l.text.isNotEmpty)
          .toList();
      if (firstTextLine.isNotEmpty) {
        firstOffsets.add(firstTextLine.first.chapterPosition);
      }
    }
    // 单调递增(允许相等: 不同页可能首行落在同一段不同偏移, 但不应回退)
    for (var i = 1; i < firstOffsets.length; i++) {
      expect(firstOffsets[i], greaterThan(firstOffsets[i - 1]),
          reason: '页 $i 首行偏移应大于页 ${i - 1}: ${firstOffsets[i]} vs ${firstOffsets[i - 1]}');
    }
  });

  /// 断言: 首页首行 chapterPosition == 0, 正文首行偏移 = 标题段长度 + 换行。
  ///
  /// chapterPosition 是「预处理后内容」的绝对偏移(标题段也占偏移),
  /// 这样恢复时用同一套 ContentProcessor 重新生成内容, 偏移自洽可逆。
  test('标题段偏移 0, 正文首行偏移 = 标题长度 + 1', () {
    final title = '第一章 测试标题';
    final content = '$title\n这是正文第一段内容';
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(pages, isNotEmpty);

    // 找标题行: chapterPosition 应为 0
    TextLine? titleLine;
    TextLine? firstBodyLine;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isTitle && titleLine == null) {
          titleLine = line;
        } else if (line.text.isNotEmpty &&
            !line.isTitle &&
            firstBodyLine == null) {
          firstBodyLine = line;
        }
      }
    }
    expect(titleLine, isNotNull, reason: '应识别出标题行');
    expect(titleLine!.chapterPosition, 0,
        reason: '标题段偏移应为 0 (内容起点)');

    expect(firstBodyLine, isNotNull, reason: '应存在正文行');
    // 正文段起点 = 标题段长度 + '\n'(1)
    expect(firstBodyLine!.chapterPosition, title.length + 1,
        reason: '正文首段偏移 = 标题段长 + 换行符');
  });

  /// 断言: 同一段落多行时, 各行 chapterPosition 按文字长度递增。
  test('同段多行 chapterPosition 按文字长度递增', () {
    // 一段很长文字, 强制换行成多行
    final longLine = '一二三四五六七八九十' * 6;
    final content = longLine; // 单段
    final pages = engine.paginate(
      content: content,
      pageSize: const Size(120.0, 200.0), // 窄, 强制多行
      settings: settings,
    );
    expect(pages, isNotEmpty);

    final bodyLines = <TextLine>[];
    for (final page in pages) {
      bodyLines.addAll(page.lines.where((l) => l.text.isNotEmpty && !l.isTitle));
    }
    expect(bodyLines.length, greaterThan(1), reason: '单段长文字应折成多行');

    // 各行 chapterPosition 应单调递增(同段内, 不含段末段距行)
    for (var i = 1; i < bodyLines.length; i++) {
      expect(bodyLines[i].chapterPosition,
          greaterThan(bodyLines[i - 1].chapterPosition),
          reason: '同段各行偏移应递增');
    }

    // 末行偏移 + 末行文字长度 应 ≈ 整段长度(不含缩进)
    final last = bodyLines.last;
    final lastEnd = last.chapterPosition + last.text.length;
    expect(lastEnd, lessThanOrEqualTo(longLine.length + 1),
        reason: '末行末尾偏移不应超过源文本长度; 实际 $lastEnd vs ${longLine.length}');
  });

  /// 断言: charOffset↔pageIndex 互转语义——给定一个 charOffset,
  /// 能找到它落在哪一页(二分各页首行 chapterPosition)。
  test('charOffset → pageIndex 二分定位一致', () {
    final content = '第一段内容文字\n第二段内容文字\n第三段内容文字\n第四段内容文字';
    final pages = engine.paginate(
      content: content,
      pageSize: const Size(120.0, 100.0),
      settings: settings,
    );
    expect(pages.length, greaterThan(1));

    // 模拟 controller 的 offset→page 定位逻辑
    int offsetToPageIndex(int offset) {
      for (var i = pages.length - 1; i >= 0; i--) {
        final firstText = pages[i].lines
            .where((l) => l.text.isNotEmpty)
            .toList();
        if (firstText.isNotEmpty && firstText.first.chapterPosition <= offset) {
          return i;
        }
      }
      return 0;
    }

    // offset=0 应落在第一页
    expect(offsetToPageIndex(0), 0);

    // 一个超出最后一页首行的 offset 应落在最后一页
    final lastPageFirst = pages.last.lines
        .where((l) => l.text.isNotEmpty)
        .first
        .chapterPosition;
    expect(offsetToPageIndex(lastPageFirst), pages.length - 1);
  });

  /// 断言: 章节总偏移覆盖完整内容长度。
  test('末页末行 chapterPosition + 文字长度 ≈ 内容长度', () {
    final content = '一段较短的内容文字示例';
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(pages, isNotEmpty);

    final allBody = <TextLine>[];
    for (final page in pages) {
      allBody.addAll(page.lines.where((l) => l.text.isNotEmpty && !l.isTitle));
    }
    expect(allBody, isNotEmpty);

    final last = allBody.last;
    final covered = last.chapterPosition + last.text.length;
    // 覆盖范围应 >= 内容长度(允许含段末换行等冗余, 但不应远小于内容)
    expect(covered, greaterThanOrEqualTo(content.length - 5),
        reason: '末行末尾应覆盖到内容末尾附近; 实际覆盖到 $covered, 内容长 ${content.length}');
  });
}
