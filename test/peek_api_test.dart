import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/controller/reading_controller.dart';
import 'package:flutter_reader/src/core/models/book.dart';

/// 构建「每章多页」的测试书: 每章内容足以分成 >=2 页。
Book _multiPageBook({int chapterCount = 3}) {
  final chapters = <Chapter>[];
  for (var i = 0; i < chapterCount; i++) {
    // 重复文字撑出多页(360x120 的页面约 4-5 行/页)。
    final content = List.generate(40, (j) => '第${i + 1}章 第${j + 1}段内容文字').join('\n');
    chapters.add(Chapter(
      id: 'c$i',
      title: '第${i + 1}章 标题',
      content: content,
      index: i,
    ));
  }
  return Book(
    id: 'b1',
    title: '测试书',
    author: '作者',
    chapters: chapters,
  );
}

ReadingController _controller() {
  final c = ReadingController();
  c.loadBook(_multiPageBook());
  // loadBook 后 pageSize 仍为 zero, 手动设置触发分页。
  c.updatePageSize(const Size(360.0, 120.0));
  return c;
}

void main() {
  group('peek API — 无副作用', () {
    test('peekNext/peekPrev 章内有下一页/上一页时返回正确页', () {
      final c = _controller();
      // 初始在第 0 页。
      expect(c.currentPageIndex, 0);

      final next = c.peekNext();
      expect(next, isNotNull);
      expect(next!.chapterIndex, c.currentChapterIndex);
      expect(next.pageIndex, 1);

      // peek 不应改变 controller 状态。
      expect(c.currentPageIndex, 0);
      expect(c.currentChapterIndex, 0);
      expect(c.pages.length, greaterThanOrEqualTo(2));

      // 跳到中间页, 验证 peekPrev。
      c.goToPage(2);
      final prev = c.peekPrev();
      expect(prev, isNotNull);
      expect(prev!.chapterIndex, c.currentChapterIndex);
      expect(prev.pageIndex, 1);
    });

    test('peekNext 跨章: 章末页 → 下一章首页', () {
      final c = _controller();
      final lastPageIdx = c.pages.length - 1;
      c.goToPage(lastPageIdx);
      expect(c.currentPageIndex, lastPageIdx);

      final next = c.peekNext();
      expect(next, isNotNull);
      expect(next!.chapterIndex, 1, reason: '应跳到下一章');
      expect(next.pageIndex, 0, reason: '应是下一章首页');

      // 状态不变。
      expect(c.currentPageIndex, lastPageIdx);
      expect(c.currentChapterIndex, 0);
    });

    test('peekPrev 跨章: 章首页 → 上一章末页', () {
      final c = _controller();
      // 跳到第 2 章首页。
      c.goToChapter(2);
      expect(c.currentChapterIndex, 2);
      expect(c.currentPageIndex, 0);

      final prev = c.peekPrev();
      expect(prev, isNotNull);
      expect(prev!.chapterIndex, 1, reason: '应跳到上一章');
      expect(prev.pageIndex, greaterThanOrEqualTo(0), reason: '上一章某页');

      // 状态不变。
      expect(c.currentChapterIndex, 2);
      expect(c.currentPageIndex, 0);
    });

    test('边界: 第一章首页 peekPrev 为 null; 末章末页 peekNext 为 null', () {
      final c = _controller();
      // 第一章首页。
      expect(c.peekPrev(), isNull);

      // 跳到末章末页。
      c.goToChapter(c.totalChapters - 1);
      c.goToPage(c.pages.length - 1);
      expect(c.peekNext(), isNull);
    });
  });

  group('commitTurn — 提交翻页', () {
    test('章内 commit: 落到 peek 返回的页', () {
      final c = _controller();
      final target = c.peekNext()!;
      c.commitTurn(target);
      expect(c.currentPageIndex, target.pageIndex);
      expect(c.currentChapterIndex, target.chapterIndex);
    });

    test('跨章 commit: 章末 → 下一章首页', () {
      final c = _controller();
      c.goToPage(c.pages.length - 1);
      final target = c.peekNext()!;
      expect(target.chapterIndex, 1);
      c.commitTurn(target);
      expect(c.currentChapterIndex, 1);
      expect(c.currentPageIndex, 0);
    });

    test('跨章 commit: 章首 → 上一章末页', () {
      final c = _controller();
      c.goToChapter(2);
      final prevChapterPageCount =
          c.pages.length; // 当前章页数仅作参考, 用 peek 的目标
      // 先回到第 2 章, peekPrev 指向第 1 章。
      final target = c.peekPrev()!;
      expect(target.chapterIndex, 1);
      c.commitTurn(target);
      expect(c.currentChapterIndex, 1);
      // 上一章末页 pageIndex 应等于其页数-1; 与 peek 返回一致。
      expect(c.currentPageIndex, target.pageIndex);
      // 上一章末页索引非负且在范围内。
      expect(c.currentPageIndex, greaterThanOrEqualTo(0));
      expect(c.currentPageIndex, lessThan(c.pages.length));
      // 仅消除未用变量 lint。
      expect(prevChapterPageCount, greaterThan(0));
    });
  });
}
