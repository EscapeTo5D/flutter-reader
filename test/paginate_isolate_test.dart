import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/reader/engine/paginate_isolate.dart';

/// paginateInBackground 测试。
///
/// 测试环境(FlutterTester)无 RootIsolateToken, 故 isolate 路径不会真正执行,
/// 会走回退(主线程同步排)。测试验证:
/// 1. 短内容走主线程直排(content.length < 2000)。
/// 2. 长内容在回退路径下, 产出与同步 [PageEngine.paginate] 逐页逐行一致。
/// 3. 回退结果可正确渲染(字段完整: 行高/baseline/columns/chapterPosition)。
///
/// 真实设备上的 isolate 路径由手动验证覆盖(见 README/验证计划)。
void main() {
  // 构造一段较长正文(>2000 字符), 触发"非短内容"分支(回退路径)。
  String longContent() {
    final buf = StringBuffer();
    for (var i = 0; i < 120; i++) {
      buf.write('这是第$i段的正文内容,用于触发后台排版路径的较长文本,补充一些字数确保超过阈值。');
      buf.write('\n');
    }
    return buf.toString();
  }

  const pageSize = Size(360.0, 600.0);
  final settings = ReadingSettings();

  test('短内容(<2000)走主线程直排, 结果与 PageEngine 一致', () async {
    const content = '短文本内容'; // 远小于 2000
    final bg = await paginateInBackground(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    final sync = PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(bg.length, sync.length);
    expect(bg.first.lines.length, sync.first.lines.length);
  });

  test('长内容回退路径产出 == 同步 PageEngine.paginate(逐页逐行对比)', () async {
    final content = longContent();
    expect(content.length > 2000, isTrue); // 确实触发非短内容分支

    final bg = await paginateInBackground(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    final sync = PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );

    // 页数一致
    expect(bg.length, sync.length);
    // 逐页逐行对比关键字段
    for (var p = 0; p < sync.length; p++) {
      final bgPage = bg[p];
      final syncPage = sync[p];
      expect(bgPage.lines.length, syncPage.lines.length,
          reason: '页 $p 行数不一致');
      for (var l = 0; l < syncPage.lines.length; l++) {
        final bgLine = bgPage.lines[l];
        final syncLine = syncPage.lines[l];
        expect(bgLine.text, syncLine.text, reason: '页$p行$l text 不一致');
        expect(bgLine.height, syncLine.height, reason: '页$p行$l height 不一致');
        expect(bgLine.lineBase, syncLine.lineBase, reason: '页$p行$l lineBase 不一致');
        expect(bgLine.chapterPosition, syncLine.chapterPosition,
            reason: '页$p行$l chapterPosition 不一致(进度恢复关键字段)');
        expect(bgLine.columns.length, syncLine.columns.length,
            reason: '页$p行$l columns 数不一致');
      }
    }
  });

  test('回退产出可正确渲染: 首页含 columns + 各页首行 chapterPosition 单调', () async {
    final content = longContent();
    final pages = await paginateInBackground(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
    expect(pages, isNotEmpty);
    final firstPage = pages.first;
    // 首页应有含字符数据的行
    expect(
      firstPage.lines.any((l) => l.hasCharData && l.columns.isNotEmpty),
      isTrue,
    );
    // 进度恢复二分定位的前提: 各页首行(非空文字行)的 chapterPosition 单调递增。
    // (与 chapter_position_test.dart 的断言口径一致; 段距/段末空行不参与。)
    final firstOffsets = <int>[];
    for (final page in pages) {
      final firstTextLine =
          page.lines.where((l) => l.text.isNotEmpty).toList();
      if (firstTextLine.isNotEmpty) {
        firstOffsets.add(firstTextLine.first.chapterPosition);
      }
    }
    for (var i = 1; i < firstOffsets.length; i++) {
      expect(firstOffsets[i], greaterThan(firstOffsets[i - 1]),
          reason: '页 $i 首行偏移应大于页 ${i - 1}');
    }
  });

  test('isolate 入参均为可发送类型(content/Size/Settings 值类型)', () async {
    // 这是个编译期/类型保证的测试: 若 settings 含不可发送类型(闭包/Stream),
    // Isolate.run 会在运行时报错。这里用回退路径间接验证 settings 可序列化进出。
    final content = longContent();
    final customSettings = ReadingSettings().copyWith(
      fontSize: 18,
      textColor: const Color(0xFF112233),
      fontWeight: FontWeight.w700,
    );
    final result = await paginateInBackground(
      content: content,
      pageSize: pageSize,
      settings: customSettings,
    );
    // 仅验证不抛错 + 产出非空(settings 正确传递的间接证据)
    expect(result, isNotEmpty);
  });
}
