import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';

void main() {
  final engine = PageEngine();
  final settings = ReadingSettings();
  // 宽度足够一行放下短句, 高度限制 4-5 行, 便于测分页。
  final pageSize = const Size(360.0, 120.0);

  /// 断言: [newpage] 标记强制分页, 后续内容从新页开始, 标记本身不显示。
  test('[newpage] 强制换页, 标记不显示', () {
    final content = '第一段第一行\n[newpage]\n第二段新页';
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );

    // 应产生 >= 2 页
    expect(pages.length, greaterThanOrEqualTo(2),
        reason: '[newpage] 应强制分页');

    // 任何页都不应含 [newpage] 文字(脏字符)
    for (final page in pages) {
      for (final line in page.lines) {
        expect(line.text.contains('[newpage]'), isFalse,
            reason: '[newpage] 标记不应作为正文显示');
      }
    }

    // "第二段新页" 必须在第二页(索引1)或之后, 不能和"第一段第一行"同页
    final firstPageText = pages[0].lines
        .where((l) => l.text.isNotEmpty)
        .map((l) => l.text)
        .join();
    final secondPageText = pages
        .skip(1)
        .expand((p) => p.lines)
        .where((l) => l.text.isNotEmpty)
        .map((l) => l.text)
        .join();
    expect(firstPageText.contains('第一段'), isTrue);
    expect(firstPageText.contains('第二段'), isFalse,
        reason: '第二段应在 [newpage] 之后的新页');
    expect(secondPageText.contains('第二段'), isTrue);
  });

  /// 断言: 不含 [newpage] 时行为不变(回归保护)。
  test('无 [newpage] 时正常分页', () {
    final content = '第一段第一行\n第二段第二行\n第三段第三行';
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(pages, isNotEmpty);
    final allText = pages
        .expand((p) => p.lines)
        .where((l) => l.text.isNotEmpty)
        .map((l) => l.text)
        .join();
    expect(allText, contains('第一段'));
    expect(allText, contains('第三段'));
  });

  /// 断言: 末尾 [newpage] 不产生多余空白尾页。
  test('末尾 [newpage] 不产生多余尾页', () {
    final content = '一段内容\n[newpage]';
    final pages = engine.paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    // [newpage] 前的内容成第 1 页, 标记触发结束但 currentPageLines 已在标记前处理;
    // 末尾 currentPageLines 为空, 不再追加尾页。
    expect(pages.length, 1);
    final text = pages[0].lines
        .where((l) => l.text.isNotEmpty)
        .map((l) => l.text)
        .join();
    expect(text, contains('一段内容'));
  });
}
