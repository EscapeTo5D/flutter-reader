import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/reader/entities/text_page.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 【标题居中对齐原生 - 回归测试】
///
/// 原生 addCharsToLineNatural(TextChapterLayout.kt:999):
///   标题居中时 startX = (visibleWidth - desiredWidth) / 2, 整行右移。
///
/// Flutter 对齐: isTitle && isMiddleTitle 时, 每列 start/end 加 startOffset。
void main() {
  test('isMiddleTitle=true: 标题首列 start = (maxWidth - naturalWidth)/2', () {
    final settings = ReadingSettings()
      ..isMiddleTitle = true;
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '第一章 测试标题', // 单段, 被识别为标题
      pageSize: pageSize,
      settings: settings,
    );

    final maxWidth = pageSize.width - settings.padding.left - settings.padding.right;
    // 找标题行
    TextLine? titleLine;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isTitle) { titleLine = line; break; }
      }
    }
    expect(titleLine, isNotNull, reason: '应识别出标题行');
    expect(titleLine!.columns.isNotEmpty, true);

    final firstStart = titleLine.columns.first.start;
    final naturalWidth = titleLine.columns.last.end - titleLine.columns.first.start;
    final expectedOffset = (maxWidth - naturalWidth) / 2;
    debugPrint('标题首列 start=$firstStart naturalWidth=$naturalWidth '
        'maxWidth=$maxWidth 预期偏移=$expectedOffset');
    expect((firstStart - expectedOffset).abs(), lessThan(0.5),
        reason: '标题首列 start 应等于 (maxWidth-naturalWidth)/2');
  });

  test('isMiddleTitle=false: 标题左对齐, 首列 start≈0', () {
    final settings = ReadingSettings()
      ..isMiddleTitle = false
      ..titleMode = 0; // 不居中
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '第一章 测试标题',
      pageSize: pageSize,
      settings: settings,
    );

    TextLine? titleLine;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isTitle) { titleLine = line; break; }
      }
    }
    expect(titleLine, isNotNull);
    debugPrint('左对齐标题首列 start=${titleLine!.columns.first.start}');
    expect(titleLine.columns.first.start, lessThan(0.5),
        reason: 'isMiddleTitle=false 时标题应左对齐, start≈0');
  });

  test('titleMode=1 (居中模式): 标题居中', () {
    final settings = ReadingSettings()
      ..isMiddleTitle = false
      ..titleMode = 1; // 居中模式
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '第二章 标题',
      pageSize: pageSize,
      settings: settings,
    );

    TextLine? titleLine;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isTitle) { titleLine = line; break; }
      }
    }
    expect(titleLine, isNotNull);
    final start = titleLine?.columns.first.start ?? -1.0;
    debugPrint('titleMode=1 标题首列 start=$start');
    expect(start, greaterThan(1.0),
        reason: 'titleMode=1 时标题应居中, start>0');
  });

  test('正文行不受 isMiddleTitle 影响(始终左对齐)', () {
    final settings = ReadingSettings()..isMiddleTitle = true;
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    // 多段: 第一段标题, 第二段正文
    final pages = engine.paginate(
      content: '第一章 标题\n这是正文段落内容一二三四五六七八九十。',
      pageSize: pageSize,
      settings: settings,
    );

    for (final page in pages) {
      for (final line in page.lines) {
        if (!line.isTitle && line.columns.isNotEmpty) {
          debugPrint('正文行首列 start=${line.columns.first.start} (应≈0)');
          expect(line.columns.first.start, lessThan(0.5),
              reason: '正文行即使 isMiddleTitle=true 也应左对齐');
        }
      }
    }
  });
}
