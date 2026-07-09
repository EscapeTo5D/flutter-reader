import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/controller/reading_controller.dart';
import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 验证 updateSettings 的「排版指纹」短路逻辑:
/// 只改不影响排版的字段(pageAnimMode / 颜色 / headerConfig / 屏幕开关等)
/// 不应触发重排; 改影响排版的字段(字号 / 行距 / padding 等)才重排。
///
/// 这条线是「切换翻页动画卡顿」的根因修复——pageAnimMode 完全不进
/// page_engine.paginate, 改它却重排(~100-260ms/章 + 清相邻章缓存 + loading)
/// 是纯浪费, 用户能明显感知。
void main() {
  ReadingController makeController() {
    final chapters = <Chapter>[];
    for (var i = 0; i < 3; i++) {
      final content = List.generate(40, (j) => '第${i + 1}章 第${j + 1}段内容文字').join('\n');
      chapters.add(Chapter(
        id: 'c$i',
        title: '第${i + 1}章 标题',
        content: content,
        index: i,
      ));
    }
    final book = Book(id: 'b1', title: '测试书', author: '', chapters: chapters);
    final c = ReadingController();
    c.loadBook(book);
    c.updatePageSize(const Size(360.0, 120.0));
    return c;
  }

  group('updateSettings 排版指纹短路', () {
    test('改 pageAnimMode 不触发重排 (pages 引用不变)', () {
      final c = makeController();
      final pagesBefore = c.pages;
      expect(pagesBefore, isNotEmpty);
      final pageCountBefore = c.pages.length;
      final pageRefBefore = identical(c.pages, pagesBefore);

      // 只改翻页动画模式, 不动任何排版字段。
      c.updateSettings(c.settings.copyWith(pageAnimMode: PageAnimMode.simulation));

      // pages 列表对象引用保持不变 → 没有重新分页。
      expect(identical(c.pages, pagesBefore), isTrue,
          reason: 'pageAnimMode 不影响排版, pages 应复用旧实例');
      expect(c.pages.length, pageCountBefore);
      // pageRefBefore 为 true 只证明 before 取值时就是同一引用(自检)。
      expect(pageRefBefore, isTrue);
      // 进度/页索引不应变。
      expect(c.currentPageIndex, 0);
      c.dispose();
    });

    test('切到/切出 scroll 模式不触发重排(所有模式排版行为一致)', () {
      // 所有翻页模式正文都贴分隔线(availableHeight 恒为 pageSize.height),
      // pageAnimMode 不进 paginate → 切换翻页模式 pages 通用, 不需重排。
      final c = makeController();
      final pagesBefore = c.pages;

      // slide(默认) → scroll: 排版参数不变, 不重排。
      c.updateSettings(c.settings.copyWith(pageAnimMode: PageAnimMode.scroll));
      expect(identical(c.pages, pagesBefore), isTrue,
          reason: '所有模式排版行为一致, 切到 scroll 不应重排');

      // scroll → simulation: 同样不重排。
      final pagesScroll = c.pages;
      c.updateSettings(c.settings.copyWith(pageAnimMode: PageAnimMode.simulation));
      expect(identical(c.pages, pagesScroll), isTrue,
          reason: '切出 scroll 排版参数不变, 不应重排');

      c.dispose();
    });

    test('改 UI 字段 (颜色/keepScreenOn/headerConfig) 都不触发重排', () {
      final c = makeController();
      final pagesBefore = c.pages;

      c.updateSettings(c.settings.copyWith(
        backgroundColor: Colors.red,
        textColor: Colors.blue,
        tipColor: Colors.green,
        keepScreenOn: !c.settings.keepScreenOn,
        hideStatusBar: !c.settings.hideStatusBar,
        selectable: !c.settings.selectable,
        shareLayout: !c.settings.shareLayout,
      ));
      expect(identical(c.pages, pagesBefore), isTrue,
          reason: '颜色/屏幕开关等不进 paginate, 不应重排');

      // headerConfig / footerConfig 的 hidden 会改 nonContentHeight, 但那是走
      // updatePageSize 独立路径, 不该由 updateSettings 触发重排。
      c.updateSettings(c.settings.copyWith(
        headerConfig: c.settings.headerConfig.copyWith(hidden: true),
      ));
      expect(identical(c.pages, pagesBefore), isTrue,
          reason: 'headerConfig.hidden 走 pageSize 路径, 不走 updateSettings 重排');

      c.dispose();
    });

    test('改字号 (排版字段) 触发重排', () {
      final c = makeController();
      final pagesBefore = c.pages;
      final countBefore = c.pages.length;

      c.updateSettings(c.settings.copyWith(fontSize: 36.0));

      // 字号变 → 重排 → pages 是新对象, 页数很可能变。
      expect(identical(c.pages, pagesBefore), isFalse,
          reason: '字号变化应触发重排, 产生新的 pages 列表');
      // 大字号下每页能放的字更少, 页数应增加 (或至少不减少)。
      expect(c.pages.length, greaterThanOrEqualTo(countBefore));
      c.dispose();
    });

    test('改 padding 左右边距(排版字段) 触发重排', () {
      final c = makeController();
      final pagesBefore = c.pages;

      final p = c.settings.padding;
      // left/right 仍进签名(影响正文可用宽度); top/bottom 已不参与排版(正文贴分隔线)。
      c.updateSettings(c.settings.copyWith(
        padding: p.copyWith(left: 50, right: 50),
      ));

      expect(identical(c.pages, pagesBefore), isFalse,
          reason: '左右边距变化应触发重排');
      c.dispose();
    });

    test('只改 padding 上下边距不触发重排(正文贴分隔线)', () {
      final c = makeController();
      final pagesBefore = c.pages;

      final p = c.settings.padding;
      // top/bottom 已移出排版签名(正文不再消费 body 上下 padding)。
      c.updateSettings(c.settings.copyWith(
        padding: p.copyWith(top: 50, bottom: 50),
      ));

      expect(identical(c.pages, pagesBefore), isTrue,
          reason: '上下边距不再影响排版, 不应重排');
      c.dispose();
    });

    test('改 titleMode (排版字段) 触发重排', () {
      final c = makeController();
      final pagesBefore = c.pages;

      // titleMode 2 = 隐藏标题, 会改变分页结果。
      c.updateSettings(c.settings.copyWith(titleMode: 2));

      expect(identical(c.pages, pagesBefore), isFalse,
          reason: 'titleMode 变化应触发重排');
      c.dispose();
    });
  });
}
