part of 'reader_view.dart';

/// 滚动翻页(scroll 模式)的渲染与 handler 生命周期。
///
/// 状态机本身已抽成独立的 [ScrollModeHandler]（pageOffset 单一状态 + 边界
/// 翻章修正），本 mixin 只负责 handler 的创建/销毁、滚动正文 Stack 的渲染
/// (_buildScrollContent)、固定 chrome 浮层的渲染 (_buildScrollChrome)。
///
/// 对齐原生 legado `ScrollPageDelegate` + `ContentTextView.pageOffset`。
mixin _ScrollMixin on State<ReaderView>, TickerProvider {
  /// scroll 模式的核心状态机。仅在 pageAnimMode == scroll 时创建; 其他模式为 null。
  ScrollModeHandler? _scrollHandler;

  /// scroll 模式专用: 按 pageAnimMode 创建/销毁 [_scrollHandler]。
  /// 切换翻页模式(设置弹窗)时, 从其他模式 ↔ scroll 重建 handler。
  ///
  /// handler 自带 ChangeNotifier, rebuild 由 [_buildScrollContent] /
  /// [_buildScrollChrome] 内的 `ListenableBuilder` 自动驱动(仅重绘依赖
  /// pageOffset/章页码的子树), 不经过 `_ReaderViewState.setState`
  /// (避免每帧整树 rebuild + relayout 的滚动卡顿), 也不经 controller.notify。
  void _ensureScrollHandler() {
    final wantScroll =
        widget.controller.settings.pageAnimMode == PageAnimMode.scroll;
    if (wantScroll && _scrollHandler == null) {
      _scrollHandler = ScrollModeHandler(widget.controller, this);
      // ⚠️ 切到 scroll 模式的首帧防闪: handler 的 _contentHeight 初始为 0,
      // 若不立即初始化, 同帧 build 里 ListenableBuilder 会命中 `ch <= 0` 兜底
      // 渲染一帧纯背景色(原页面内容被空白替换一帧)→ 用户看到闪烁。
      // slide/none/sim 模式不闪是因为它们直接消费 controller.pages(切模式前已有),
      // 无「切模式才创建、要等 LayoutBuilder 回调才有值」的延迟初始化空窗。
      // 切模式时 controller.pageSize 一定已就绪(切前页面就在显示), 这里同步喂一次,
      // 让 _contentHeight 在 build 前就有值, 消除首帧空窗。
      final ps = widget.controller.pageSize;
      if (ps.height > 0) {
        _scrollHandler!.updatePageHeight(ps.height);
      }
    } else if (!wantScroll && _scrollHandler != null) {
      _scrollHandler!.dispose();
      _scrollHandler = null;
    }
  }

  /// handler 的 pageOffset/章页码变化时由 `ListenableBuilder` 自动局部重绘
  /// (仅正文 Stack + chrome 文本), 不再走 `_ReaderViewState.setState`
  /// —— 避免滚动每帧触发整棵 ReaderView rebuild + relayout 的卡顿。
  ///
  /// 对齐原生 `ContentTextView.scroll`: 原生改 `pageOffset` 后只 `postInvalidate()`
  /// (纯 paint, 不 relayout)。Flutter 端用 ListenableBuilder 把 rebuild 范围收敛到
  /// 仅「依赖 pageOffset/章页码」的子树, GestureDetector/LayoutBuilder/菜单层不参与。

  Widget _buildScrollContent() {
    final h = _scrollHandler!;
    final c = widget.controller;
    final settings = c.settings;

    // ⚠️ loading 收敛(修复"切模式闪 loading"): 仅当 curPages 真为空(章节首次加载)
    // 才显示转圈; pageHeight==0(切模式瞬间 LayoutBuilder 尚未回调)显示纯背景色占位,
    // 不闪转圈。对齐原生切模式「直接切、无 loading」。
    if (h.curPages.isEmpty) {
      return ColoredBox(
        color: settings.backgroundColor,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                settings.textColor.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      );
    }

    // ⚠️ 关键性能优化: 用 ListenableBuilder 把 rebuild 范围收敛到本子树。
    // pageOffset/章页码 每帧变化时只重建这里的正文 Stack, 不触发外层
    // _ReaderViewState.build(避免 GestureDetector/LayoutBuilder/菜单层等整树
    // rebuild)。对齐原生 ContentTextView.scroll 改 pageOffset 后只 postInvalidate
    // (仅重画本 View)。
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final hh = _scrollHandler!;
        final cc = widget.controller;
        final curPage = hh.curPage;
        final ch = hh.contentHeight;
        // contentHeight==0(切模式瞬间) → 纯背景色, 同帧 PostFrame updatePageHeight 后立即正常。
        if (curPage == null || ch <= 0) {
          return ColoredBox(color: settings.backgroundColor, child: SizedBox());
        }

        // 渲染模型 cur / next / nextPlus(对齐原生 ContentTextView.drawPage,
        // ⚠️ 不画 prev 页)。原生平移用 relativeOffset, 只在 paint 算坐标; Flutter
        // 用 Transform.translate(paint 阶段平移, 不 relayout)等价。
        final nextPage = hh.nextPage;
        final nextPlusPage = hh.nextPlusPage;
        final offset = hh.pageOffset;

        // 纯正文页 widget(scrollContentMode 跳过 top/bottom padding, 保留左右)。
        // 每页高度 = contentHeight(纯内容高, 对齐原生 visibleHeight)。
        Widget textPage(TextPage p, int pageIndex, int chapterIndex,
            int totalPages, String? chapterTitle) => SizedBox(
              height: ch,
              child: pv.PageView(
                page: p,
                settings: settings,
                pageIndex: pageIndex,
                totalPages: totalPages,
                chapterIndex: chapterIndex,
                chapterSize: cc.totalChapters,
                chapterTitle: chapterTitle,
                bookName: cc.book?.title,
                searchQuery:
                    cc.searchQuery.isNotEmpty ? cc.searchQuery : null,
                useSafeArea: false,
                showChrome: false,
                scrollContentMode: true,
              ),
            );

        // cur 页: offset = pageOffset(对齐原生 relativeOffset(0))。
        // 跨章后 cur 页属于新章, chapterIndex/pageIndex/totalPages 取新章。
        final curWidget = textPage(
          curPage,
          hh.pageInChapter,
          hh.chapterIndex,
          hh.curChapterPageCount,
          hh.curChapterTitle,
        );

        // next 页: offset = pageOffset + contentHeight(对齐原生 relativeOffset(1))。
        // 跨章时 next 属于下一章, chapterIndex = 当前章+1, pageIndex 从 0 起。
        Widget? nextWidget;
        int nextChapterIndex = hh.chapterIndex;
        int nextPageIndex = hh.pageInChapter + 1;
        int nextTotalPages = hh.curChapterPageCount;
        String? nextChapterTitle = hh.curChapterTitle;
        if (nextPage != null) {
          if (hh.pageInChapter >= hh.curPages.length - 1) {
            // 章末: next 在下一章首页。
            nextChapterIndex = hh.chapterIndex + 1;
            nextPageIndex = 0;
            nextTotalPages = hh.nextPages?.length ?? 1;
            nextChapterTitle =
                cc.getChapter(nextChapterIndex)?.title;
          }
          nextWidget = textPage(nextPage, nextPageIndex, nextChapterIndex,
              nextTotalPages, nextChapterTitle);
        }

        // nextPlus 页: offset = pageOffset + 2*contentHeight(对齐原生 relativeOffset(2))。
        // 原生守卫: relativeOffset < visibleHeight 才画(下下页顶部进入可视区)。
        Widget? nextPlusWidget;
        if (nextPlusPage != null && offset + 2 * ch < ch) {
          // 推算 nextPlus 所属章/页(章内/跨章)。
          int npChapterIndex = hh.chapterIndex;
          int npPageIndex = hh.pageInChapter + 2;
          int npTotalPages = hh.curChapterPageCount;
          String? npChapterTitle = hh.curChapterTitle;
          final remaining = hh.curPages.length - 1 - hh.pageInChapter;
          if (remaining <= 1 && hh.nextPages != null) {
            // 涉及下一章。
            npChapterIndex = hh.chapterIndex + 1;
            npPageIndex = nextPageIndex == 0 ? 1 : 0;
            npTotalPages = hh.nextPages!.length;
            npChapterTitle = cc.getChapter(npChapterIndex)?.title;
          }
          nextPlusWidget = textPage(nextPlusPage, npPageIndex, npChapterIndex,
              npTotalPages, npChapterTitle);
        }

        // ⚠️ 固定 padding 条 + 纯内容连续画布(对齐原生 visibleRect 裁剪 +
        // 固定 paddingTop/Bottom 条):
        // - Column: [顶部 padding 条(背景色, 高=paddingTop)] +
        //   [内容区 Expanded: ClipRect + Stack 三页平移, 页步长=contentHeight] +
        //   [底部 padding 条(背景色, 高=paddingBottom)]。
        // - 内容区高度 = contentHeight, 页与页内容紧邻无 padding 空白带。
        // - padding 条不随滚动(固定), 内容在其间流动。
        final padTop = settings.padding.top;
        final padBottom = settings.padding.bottom;

        // Positioned(top:0) 固定定位(不改 top, 不触发 relayout)+ 内层
        // Transform.translate 在 paint 阶段平移, 等价于原生 canvas.translate。
        final contentStack = ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: curWidget,
                ),
              ),
              if (nextWidget != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, offset + ch),
                    child: nextWidget,
                  ),
                ),
              if (nextPlusWidget != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, offset + 2 * ch),
                    child: nextPlusWidget,
                  ),
                ),
            ],
          ),
        );

        return ColoredBox(
          color: settings.backgroundColor,
          child: Column(
            children: [
              // 顶部 padding 条(固定, 不随滚动)。
              Container(height: padTop, color: settings.backgroundColor),
              // 内容区(连续画布, 页在此平移)。
              Expanded(child: contentStack),
              // 底部 padding 条(固定, 不随滚动)。
              Container(height: padBottom, color: settings.backgroundColor),
            ],
          ),
        );
      },
    );
  }

  /// scroll 模式 chrome 浮层(固定在视口, 不随滚动)。由 reader_view.build
  /// 在 _buildPageContent 之外的同级 Stack 挂载, 覆盖在正文之上。页码/进度
  /// 取 handler 当前可见页(滚动中实时变), 对齐原生 `setProgress` 每帧更新。
  ///
  /// 用 ListenableBuilder 收敛 rebuild: 滚动中 pageInChapter 变化时只重建
  /// chrome 的 PageView, 不触发外层 _ReaderViewState.build。
  Widget? _buildScrollChrome() {
    final h = _scrollHandler;
    if (h == null) return null;
    final c = widget.controller;
    final settings = c.settings;
    final showHeader = settings.hideStatusBar && !settings.headerConfig.hidden;
    final showFooter = !settings.footerConfig.hidden;
    if (!showHeader && !showFooter) return null;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: h,
        builder: (context, _) {
          final hh = _scrollHandler;
          if (hh == null) return const SizedBox();
          final cc = widget.controller;
          return Stack(
            children: [
              if (showHeader)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: ColoredBox(
                      color: settings.backgroundColor,
                      child: pv.PageView(
                        settings: settings,
                        pageIndex: hh.pageInChapter,
                        totalPages: hh.curChapterPageCount,
                        chapterIndex: hh.chapterIndex,
                        chapterSize: cc.totalChapters,
                        chapterTitle: hh.curChapterTitle,
                        bookName: cc.book?.title,
                        useSafeArea: false,
                        showChrome: false,
                        showHeaderOnly: true,
                        batteryLevel: BatteryProvider.instance.value,
                      ),
                    ),
                  ),
                ),
              if (showFooter)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: ColoredBox(
                      color: settings.backgroundColor,
                      child: pv.PageView(
                        settings: settings,
                        pageIndex: hh.pageInChapter,
                        totalPages: hh.curChapterPageCount,
                        chapterIndex: hh.chapterIndex,
                        chapterSize: cc.totalChapters,
                        chapterTitle: hh.curChapterTitle,
                        bookName: cc.book?.title,
                        useSafeArea: false,
                        showChrome: false,
                        showFooterOnly: true,
                        batteryLevel: BatteryProvider.instance.value,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
