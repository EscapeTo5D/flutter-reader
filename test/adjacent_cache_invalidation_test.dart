import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/controller/reading_controller.dart';
import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 验证相邻章分页缓存 [_adjacentChapterCache] 的失效判断:
///
/// 缓存失效条件应与 [ReadingController.updateSettings] 的「排版指纹」一致 ——
/// 只有影响 `page_engine.paginate` 结果的字段变化才清空缓存。改 pageAnimMode /
/// 颜色 / headerConfig 等不进排版的字段, 缓存应**保持命中**, 相邻章不必重排/重取。
///
/// 这条线是「切换翻页动画卡顿」的同类根因 —— updateSettings 的重排短路修过了
/// (见 update_settings_layout_signature_test.dart), 但缓存失效判断此前用
/// `identical(_settings, ref)` 对象引用比较, 而 copyWith 每次都产生新对象 →
/// 引用必变 → 误清缓存 → 相邻章被重排/重取(scroll 模式预取、prefetchAdjacentChapters
/// 都会立刻重做), 是切到/切出 scroll 模式时的卡顿源。
void main() {
  ReadingController makeController() {
    final chapters = <Chapter>[];
    for (var i = 0; i < 3; i++) {
      final content =
          List.generate(40, (j) => '第${i + 1}章 第${j + 1}段内容文字').join('\n');
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

  group('相邻章缓存失效判断', () {
    test('改 pageAnimMode 相邻章缓存保持命中(同一 List 对象)', () {
      final c = makeController();
      // 当前章 = 第 1 章(index 1), 预取相邻章(index 0/2)入缓存。
      c.goToChapter(1);
      c.prefetchAdjacentChapters();
      final prevPages = c.paginateChapterPreferSync(0);
      final nextPages = c.paginateChapterPreferSync(2);
      expect(prevPages, isNotEmpty);
      expect(nextPages, isNotEmpty);

      // 改翻页模式(不进排版)。
      c.updateSettings(
          c.settings.copyWith(pageAnimMode: PageAnimMode.scroll));

      // 相邻章缓存应命中同一对象 → 未被清空、未重排。
      expect(identical(c.paginateChapterPreferSync(0), prevPages), isTrue,
          reason: 'pageAnimMode 不进排版, 上一章缓存应保持命中');
      expect(identical(c.paginateChapterPreferSync(2), nextPages), isTrue,
          reason: 'pageAnimMode 不进排版, 下一章缓存应保持命中');
      c.dispose();
    });

    test('改颜色/keepScreenOn/headerConfig 等不进排版的字段, 缓存保持命中', () {
      final c = makeController();
      c.goToChapter(1);
      c.prefetchAdjacentChapters();
      final prevPages = c.paginateChapterPreferSync(0);

      c.updateSettings(c.settings.copyWith(
        backgroundColor: Colors.red,
        textColor: Colors.blue,
        tipColor: Colors.green,
        keepScreenOn: !c.settings.keepScreenOn,
        hideStatusBar: !c.settings.hideStatusBar,
        selectable: !c.settings.selectable,
        shareLayout: !c.settings.shareLayout,
      ));

      expect(identical(c.paginateChapterPreferSync(0), prevPages), isTrue,
          reason: '颜色/屏幕开关等不进排版, 相邻章缓存应保持命中');
      c.dispose();
    });

    test('改字号(排版字段)相邻章缓存失效, 重新分页产生新对象', () {
      final c = makeController();
      c.goToChapter(1);
      c.prefetchAdjacentChapters();
      final prevPages = c.paginateChapterPreferSync(0);

      c.updateSettings(c.settings.copyWith(fontSize: 36.0));

      // 字号变 → 缓存失效 → 重新分页 → 新 List 对象。
      final newPrev = c.paginateChapterPreferSync(0);
      expect(identical(newPrev, prevPages), isFalse,
          reason: '字号变化应使相邻章缓存失效');
      // 大字号下每页字更少, 页数应增加(或至少不同)。
      expect(newPrev.length == prevPages.length, isFalse,
          reason: '大字号下分页结果应不同');
      c.dispose();
    });

    test('改 padding 左右边距(排版字段)相邻章缓存失效', () {
      final c = makeController();
      c.goToChapter(1);
      c.prefetchAdjacentChapters();
      final prevPages = c.paginateChapterPreferSync(0);

      final p = c.settings.padding;
      c.updateSettings(
          c.settings.copyWith(padding: p.copyWith(left: 50, right: 50)));

      expect(identical(c.paginateChapterPreferSync(0), prevPages), isFalse,
          reason: '左右边距变化应使相邻章缓存失效');
      c.dispose();
    });
  });
}
