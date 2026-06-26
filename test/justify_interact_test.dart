import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/reader/entities/text_page.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 【缩进行两端对齐修复 - 回归测试】
///
/// 根因: _buildColumns 在缩进行上把 perCharExtra 错误施加到缩进字符之间的间隙,
/// 导致末列 end 超出 maxWidth (实测 0.53px, 仅缩进行发生)。
///
/// 对齐原生 legado: 缩进字符用固定宽度, 不参与两端对齐; 仅 indentSize 之后的
/// 字符子列做 middle 对齐。
///
/// 断言: 任何行的末列 end 不得超过 maxWidth + 容差。
void main() {
  test('缩进行末列 end 不得超出 maxWidth', () {
    final settings = ReadingSettings(); // textFullJustify=true, textIndent=2
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();
    final maxW = pageSize.width - settings.padding.left - settings.padding.right;

    final buf = StringBuffer();
    for (var p = 0; p < 15; p++) {
      buf.writeln('　　这是第${p + 1}段比较长的缩进文字用来触发换行一二三四五六七八九十百千万abcdef。');
    }

    final pages = engine.paginate(
      content: buf.toString(),
      pageSize: pageSize,
      settings: settings,
    );

    var violations = 0;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.columns.isEmpty) continue;
        final ov = line.columns.last.end - maxW;
        if (ov > 0.5) {
          violations++;
          debugPrint('违规: indent=${line.indentSize} '
              'lastCol.end=${line.columns.last.end.toStringAsFixed(2)} '
              'maxW=$maxW ov=${ov.toStringAsFixed(2)}');
        }
      }
    }
    expect(violations, 0, reason: '缩进行末列超出 maxWidth, 两端对齐在缩进行上多拉伸');
  });

  test('缩进字符之间的间隙不施加 perCharExtra (缩进宽度恒定)', () {
    // 缩进2个全角空格, 每个宽 ≈ fontSize。无论两端对齐与否,
    // 第二个缩进字符的 end 应 ≈ 2 * indentCharWidth, 不被拉伸。
    final settings = ReadingSettings();
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '　　这是一段用来触发换行的长文字内容一二三四五六七八九十百千万abcdef。',
      pageSize: pageSize,
      settings: settings,
    );

    // 找第一个缩进行
    TextLine? indented;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.indentSize > 0) { indented = line; break; }
      }
      if (indented != null) break;
    }
    expect(indented, isNotNull);
    // 第二个缩进字符(列索引1)的 end, 应严格等于 indentWidth(=2字宽), 不含拉伸
    final secondIndentEnd = indented!.columns[1].end;
    debugPrint('第二个缩进字符 end=${secondIndentEnd.toStringAsFixed(2)} '
        'indentWidth=${indented.indentWidth.toStringAsFixed(2)}');
    // 缩进字符不应被拉伸: end 应等于 indentWidth(列0+列1宽)
    expect((secondIndentEnd - indented.indentWidth).abs(), lessThan(0.01),
        reason: '缩进字符间隙不应施加两端对齐间距');
  });
}
