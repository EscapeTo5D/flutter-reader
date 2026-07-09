import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';

/// 【末页截断回归测试】
///
/// Bug 历史: 末页内容若被底部对齐撑满(或加 endPadding 后超出 availableHeight),
/// 渲染层 ClipRect 会裁掉末行, 表现为末行文字只显示半截。
///
/// 此测试在多种配置/内容下断言: 每一页的渲染总高度 <= availableHeight,
/// 确保任何页的末行都不会被裁。
void main() {
  final engine = PageEngine();
  const pageSize = Size(360.0, 600.0);

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

  /// 生成段落长短不一的内容(模拟真实小说)。
  String makeContent() {
    final paragraphs = <String>[];
    for (var i = 0; i < 80; i++) {
      final len = 15 + (i * 7) % 40;
      paragraphs.add('第${i + 1}段${'内容文字啊' * (len ~/ 3)}');
    }
    return paragraphs.join('\n');
  }

  final content = makeContent();

  final configs = <String, ReadingSettings>{
    '默认': ReadingSettings(),
    '缩进2': ReadingSettings().copyWith(textIndent: 2),
    '段距大': ReadingSettings().copyWith(paragraphSpacing: 8.0),
    '字号大': ReadingSettings().copyWith(fontSize: 22.0),
    '行距大': ReadingSettings().copyWith(lineHeight: 1.6),
    '行距小': ReadingSettings().copyWith(lineHeight: 1.0),
  };

  for (final entry in configs.entries) {
    final label = entry.key;
    final settings = entry.value;

    test('$label: 所有页渲染高度不溢出(末行不被裁)', () {
      // 引擎 availableHeight 现恒为 pageSize.height(正文贴分隔线)。
      final available = pageSize.height;
      final pages = engine.paginate(
        content: content,
        pageSize: pageSize,
        settings: settings,
      );
      expect(pages, isNotEmpty);

      double maxOverflow = 0;
      for (var p = 0; p < pages.length; p++) {
        final renderH = renderHeightOf(pages[p].lines);
        final overflow = renderH - available;
        if (overflow > maxOverflow) maxOverflow = overflow;
      }
      expect(
        maxOverflow,
        lessThan(0.5),
        reason:
            '$label: 第某页溢出 ${maxOverflow.toStringAsFixed(2)}px, '
            '末行会被 ClipRect 裁掉(截断)',
      );
    });
  }
}
