import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';

/// 底部对齐(bottomJustify)回归测试。
///
/// 对齐原生 legado TextPage.upLinesPosition 行为: 非末页每页撑满到底,
/// 末行贴 visibleBottom → 到页脚分割线距离恒定; 末页不撑(顶对齐 + endPadding)。
void main() {
  final engine = PageEngine();
  final settings = ReadingSettings();
  final pageSize = const Size(360.0, 600.0);
  final available =
      pageSize.height - settings.padding.top - settings.padding.bottom;

  /// 复现 page_view._buildLines 渲染逻辑, 计算一页的实际渲染总高度。
  double renderHeightOf(List lines) {
    double renderHeight = 0;
    double prevLineTop = 0;
    for (final line in lines) {
      if (!line.isEmptyParagraph && line.lineTop > 0) {
        final extra = line.lineTop - prevLineTop;
        if (extra > 0) renderHeight += extra;
        prevLineTop = line.lineTop;
      }
      renderHeight += line.height;
    }
    return renderHeight;
  }

  test('非末页每页撑满, 末行到页底距离恒定', () {
    final content = List.generate(100, (i) => '这是第${i + 1}段测试内容文字啊啊啊啊')
        .join('\n');
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(pages.length, greaterThan(1), reason: '应分多页');

    final nonLastGaps = <double>[];
    for (var p = 0; p < pages.length - 1; p++) {
      final gap = available - renderHeightOf(pages[p].lines);
      nonLastGaps.add(gap);
    }
    final maxGap = nonLastGaps.reduce((a, b) => a > b ? a : b);
    final minGap = nonLastGaps.reduce((a, b) => a < b ? a : b);
    expect(maxGap - minGap < 1.0, isTrue,
        reason: '各非末页末行到页底距离差应 < 1px(恒定), 实测 min=$minGap max=$maxGap');
    // 每页都应接近撑满(差 < 一行高度)
    expect(nonLastGaps.every((g) => g.abs() < 1.0), isTrue,
        reason: '非末页应撑满到底 gap≈0');
  });

  test('末页不撑满(顶对齐 + 留白)', () {
    final content = List.generate(100, (i) => '这是第${i + 1}段测试内容文字啊啊啊啊')
        .join('\n');
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    final lastGap = available - renderHeightOf(pages.last.lines);
    expect(lastGap > 1.0, isTrue,
        reason: '末页内容少, 应回到不撑满状态(留白 > 1px)');
  });
}
