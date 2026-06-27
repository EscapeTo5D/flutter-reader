import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 【末页 endPadding 对齐原生 legado - 回归测试】
///
/// 原生(ChapterProvider 末尾, TextChapterLayout.kt:499-505):
///   endPadding = 20dp
///   末页只追加 endPadding(内容顶部对齐, 底部留白), 不强制撑满 visibleHeight。
///
/// Flutter 对齐: 末页追加一个 isEndPadding 的间距行(height=20dp)。
void main() {
  const endPadding = 20.0;

  test('末页末尾含 endPadding 行', () {
    final settings = ReadingSettings();
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final buf = StringBuffer();
    for (var p = 0; p < 6; p++) {
      buf.write('　　这是第${p + 1}段文字内容用来撑满页面行数一二三四五六七八九十。');
    }

    final pages = engine.paginate(
      content: buf.toString(),
      pageSize: pageSize,
      settings: settings,
    );

    expect(pages.length, greaterThanOrEqualTo(1));
    final lastPage = pages.last;
    final hasEnd = lastPage.lines.any((l) => l.isEndPadding);
    expect(hasEnd, true, reason: '末页末尾应有 endPadding 行');

    // 非末页不应有 endPadding
    if (pages.length > 1) {
      for (var i = 0; i < pages.length - 1; i++) {
        final hasEndInNonLast = pages[i].lines.any((l) => l.isEndPadding);
        expect(hasEndInNonLast, false,
            reason: '非末页不应有 endPadding');
      }
    }
  });

  test('endPadding 行高度 = 20dp', () {
    final settings = ReadingSettings();
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '　　短内容。', // 单页(末页)
      pageSize: pageSize,
      settings: settings,
    );

    final endLine = pages.last.lines.where((l) => l.isEndPadding).toList();
    expect(endLine.length, 1);
    expect(endLine.first.height, endPadding);
  });

  test('endPadding 不影响末页分页(末页不会被 endPadding 挤出)', () {
    // 内容刚好接近一页, 加 endPadding 不应导致末页内容丢失或溢出
    final settings = ReadingSettings();
    const pageSize = Size(360.0, 600.0);
    final availableHeight =
        pageSize.height - settings.padding.top - settings.padding.bottom;
    final engine = PageEngine();

    final buf = StringBuffer();
    for (var p = 0; p < 14; p++) {
      buf.write('　　这是第${p + 1}段文字内容用来撑满页面行数一二三四五六七八九十。');
    }

    final pages = engine.paginate(
      content: buf.toString(),
      pageSize: pageSize,
      settings: settings,
    );

    // 末页渲染总高(含 endPadding)不应超过 availableHeight
    final lastPage = pages.last;
    double renderH = 0;
    for (final line in lastPage.lines) {
      renderH += line.height;
    }
    debugPrint('末页行数=${lastPage.lines.length} 渲染高=${renderH.toStringAsFixed(1)} '
        'availableHeight=$availableHeight');
    // endPadding 是追加的, 但末页本就留白, 允许接近但不强制
    expect(renderH, lessThanOrEqualTo(availableHeight + endPadding),
        reason: '末页含 endPadding 后不应严重溢出');
  });
}
