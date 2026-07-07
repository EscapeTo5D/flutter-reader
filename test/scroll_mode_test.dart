import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/controller/reading_controller.dart';
import 'package:flutter_reader/src/core/models/book.dart';
import 'package:flutter_reader/src/reader/page_animations/scroll_mode_handler.dart';

/// 滚动翻页模式核心状态机测试, 对齐原生 legado `ContentTextView.scroll`。
///
/// 验证单一 pageOffset 状态机的边界翻章/翻页、章首末钳制、点击翻页保留一行、
/// 跨章无缝衔接。用真实 ReadingController(真实 PageEngine 排版), 保证
/// TextLine.lineTop / chapterPosition 字段有意义。
void main() {
  const pageWidth = 360.0;
  const pageHeight = 120.0;

  /// 构造一本 3 章、每章足够多段(强制多页)的假书。返回 (controller, handler)。
  /// handler 的 _curPages 从 controller.pages 同步(走真实排版管线)。
  Future<(ReadingController, ScrollModeHandler)> makeBook() async {
    final controller = ReadingController();
    final chapters = <Chapter>[
      for (var i = 0; i < 3; i++)
        Chapter(
          id: 'ch$i',
          title: '第${i + 1}章',
          content: List.generate(
            40,
            (j) => '第${i + 1}章第${j + 1}段正文内容',
          ).join('\n'),
          index: i,
        ),
    ];
    final book = Book(id: 'test', title: '测试书', author: '', chapters: chapters);
    controller.loadBook(book);
    controller.updatePageSize(const Size(pageWidth, pageHeight));
    // updatePageSize 触发的重排是同步的, 但保险起见让微任务跑完。
    await Future.microtask(() {});
    final handler = ScrollModeHandler(controller, _TestVsync());
    handler.updatePageHeight(pageHeight);
    return (controller, handler);
  }

  testWidgets('pageOffset 初始为 0(当前页顶部对齐视口顶)', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    expect(handler.pageOffset, 0.0);
    expect(handler.chapterIndex, 0);
    expect(handler.pageInChapter, 0);
  });

  testWidgets('章内向下滚动不翻页: offset 仍在 [-pageHeight, 0] 内', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    handler.applyDragDelta(-60.0);
    expect(handler.pageOffset, closeTo(-60.0, 0.5));
    expect(handler.chapterIndex, 0);
    expect(handler.pageInChapter, 0);
  });

  testWidgets('越过底部(offset < -pageHeight)翻到下一页, offset 修正保持连续', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    final oldPage = handler.pageInChapter;
    handler.applyDragDelta(-60.0);
    handler.applyDragDelta(-70.0); // 累计 -130 < -120 → 翻下一页
    expect(handler.pageInChapter, oldPage + 1, reason: '越过底部应翻到下一页');
    expect(
      handler.pageOffset,
      closeTo(-10.0, 0.5),
      reason: '翻页后 offset += pageHeight(-130+120=-10), 保持连续',
    );
  });

  testWidgets('越过顶部(offset > 0)翻到上一页, offset 修正保持连续', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    handler.applyDragDelta(-130.0); // 翻到第2页, offset=-10
    expect(handler.pageInChapter, 1);
    handler.applyDragDelta(30.0); // offset: -10+30=20 > 0 → 翻上一页
    expect(handler.pageInChapter, 0, reason: '越过顶部应翻回上一页');
    expect(
      handler.pageOffset,
      closeTo(-100.0, 0.5),
      reason: '翻上一页后 offset -= pageHeight(20-120=-100)',
    );
  });

  testWidgets('首章首页继续向下滚 → 钳 0(回弹), 不翻页', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    handler.applyDragDelta(50.0);
    expect(handler.pageOffset, 0.0, reason: '首章首页向下滚应钳 0');
    expect(handler.chapterIndex, 0);
    expect(handler.pageInChapter, 0);
  });

  testWidgets('章末继续向下越过底部 → 翻到下一章首页', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    final chapterPages = handler.curPages.length;
    // 翻到第0章末页: 每次翻一页并校准 offset 到 0(分离翻页与偏移)。
    for (var i = 0; i < chapterPages - 1; i++) {
      handler.applyDragDelta(-(pageHeight + 0.5));
    }
    expect(handler.chapterIndex, 0);
    expect(handler.pageInChapter, chapterPages - 1);
    // 末页再向下越过底部 → 翻下一章首页。
    handler.applyDragDelta(-(pageHeight + 0.5));
    expect(handler.chapterIndex, 1, reason: '末页越过底部应翻到下一章');
    expect(handler.pageInChapter, 0);
  });

  testWidgets('下一章首页向上越过顶部 → 翻回上一章末页', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    final chapterPages = handler.curPages.length;
    // 翻到下一章首页(整章 + 跨章1次)。
    for (var i = 0; i < chapterPages; i++) {
      handler.applyDragDelta(-(pageHeight + 0.5));
    }
    expect(handler.chapterIndex, 1, reason: '应到下一章');
    expect(handler.pageInChapter, 0);
    // 向上越过顶部(offset > 0) → 翻回上一章末页。
    handler.applyDragDelta(pageHeight + 0.5);
    expect(handler.chapterIndex, 0, reason: '首页向上越过顶部应翻回上一章');
    expect(
      handler.pageInChapter,
      handler.curPages.length - 1,
      reason: '应到上一章末页(curPages.length-1)',
    );
  });

  testWidgets('末章末页继续向下 → 钳制不翻(无下一章)', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    final c0Pages = handler.curPages.length;
    // 翻到末章末页: 第0章整章 + 跨章到第1章 + 整章 + 跨章到第2章 + 整章。
    final totalSteps = c0Pages * 3 + 2; // 跨3章(含两次跨章翻页)
    for (var i = 0; i < totalSteps; i++) {
      handler.applyDragDelta(-(pageHeight + 0.5));
    }
    expect(handler.chapterIndex, 2, reason: '应到末章');
    final lastPage = handler.pageInChapter;
    // 再向下滚 → 钳制, 不再翻。
    handler.applyDragDelta(-(pageHeight + 0.5));
    expect(handler.chapterIndex, 2);
    expect(handler.pageInChapter, lastPage, reason: '末章末页不再翻页');
    expect(
      handler.pageOffset,
      closeTo(-pageHeight, 0.5),
      reason: '末页钳到 -pageHeight',
    );
    // 避免未使用警告。
    c0Pages;
  });

  testWidgets('点击翻页 turnByClick(noAnim) 向下推进', (tester) async {
    final (_, handler) = await makeBook();
    addTearDown(handler.dispose);
    final before = handler.pageInChapter;
    handler.turnByClick(true, noAnim: true);
    expect(handler.pageInChapter, greaterThan(before), reason: '向下点击翻页应推进');
  });

  testWidgets('setCurrentPageSilent 静默更新不触发 notifyListeners', (tester) async {
    final (controller, _) = await makeBook();
    addTearDown(controller.dispose);
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);
    controller.setCurrentPageSilent(0, 2);
    expect(controller.currentPageIndex, 2, reason: '字段应被更新');
    expect(notifyCount, 0, reason: '静默 setter 不应 notify');
  });

  testWidgets('scheduleProgressSave 公开入口存在且不抛', (tester) async {
    final (controller, _) = await makeBook();
    addTearDown(controller.dispose);
    // 无仓库时是空操作, 不应抛异常。
    controller.scheduleProgressSave();
  });
}

/// 测试用 TickerProvider 桩: AnimationController 需要它做 vsync。
/// 单测不驱动 ticker(测 applyDragDelta 的纯数据逻辑, 不测 fling 动画帧),
/// 故 createTicker 返回一个不会被触发的 Ticker。
class _TestVsync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick, [bool disableAnimations = false]) {
    return Ticker(onTick);
  }
}
