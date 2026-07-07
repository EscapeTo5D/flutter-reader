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
  /// handler 自带 ChangeNotifier, 内部 setState 局部驱动偏移重绘, 不经过
  /// controller.notify(避免整树 rebuild)。
  void _ensureScrollHandler() {
    final wantScroll =
        widget.controller.settings.pageAnimMode == PageAnimMode.scroll;
    if (wantScroll && _scrollHandler == null) {
      _scrollHandler = ScrollModeHandler(widget.controller, this)
        ..addListener(_onScrollUpdate);
    } else if (!wantScroll && _scrollHandler != null) {
      _scrollHandler!.removeListener(_onScrollUpdate);
      _scrollHandler!.dispose();
      _scrollHandler = null;
    }
  }

  /// handler 的 pageOffset/章页码变化时局部 setState 重绘(仅正文偏移 + chrome 文本)。
  void _onScrollUpdate() {
    if (mounted) setState(() {});
  }

  Widget _buildScrollContent() {
    final h = _scrollHandler!;
    final c = widget.controller;
    final settings = c.settings;
    final ph = h.pageHeight;
    final cur = h.curPage;
    if (cur == null || ph <= 0) {
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

    // 章内"下一页": 当前章下一页; 当前页已是末页则用下一章首页。
    TextPage? nextPage;
    if (h.pageInChapter < h.curPages.length - 1) {
      nextPage = h.curPages[h.pageInChapter + 1];
    } else if (h.chapterIndex < c.totalChapters - 1) {
      nextPage = (h.nextPages != null && h.nextPages!.isNotEmpty)
          ? h.nextPages!.first
          : null;
    }
    // 章内"上一页": 当前章上一页; 当前页是首页则用上一章末页。
    TextPage? prevPage;
    if (h.pageInChapter > 0) {
      prevPage = h.curPages[h.pageInChapter - 1];
    } else if (h.chapterIndex > 0) {
      prevPage = (h.prevPages != null && h.prevPages!.isNotEmpty)
          ? h.prevPages!.last
          : null;
    }

    // 纯正文页 widget(showChrome:false 只画正文行)。每页高度 = pageHeight。
    // pageIndex: 根据实际页码传入(前一页/当前页/后一页), 保证页脚页码正确。
    Widget textPage(TextPage p, int index) => SizedBox(
          height: ph,
          child: pv.PageView(
            page: p,
            settings: settings,
            pageIndex: index,
            totalPages: h.curChapterPageCount,
            chapterIndex: h.chapterIndex,
            chapterSize: c.totalChapters,
            chapterTitle: h.curChapterTitle,
            bookName: c.book?.title,
            searchQuery: c.searchQuery.isNotEmpty ? c.searchQuery : null,
            useSafeArea: false,
            showChrome: false,
          ),
        );

    // 计算各页的实际 pageIndex:
    // - prevPage: 同章 = h.pageInChapter - 1; 跨章 = 上一章末页索引
    // - curPage: h.pageInChapter
    // - nextPage: 同章 = h.pageInChapter + 1; 跨章 = 0(下一章首页)
    final prevIndex = h.pageInChapter > 0
        ? h.pageInChapter - 1
        : (h.prevPages?.isNotEmpty == true ? h.prevPages!.length - 1 : 0);
    final curIndex = h.pageInChapter;
    final nextIndex = h.pageInChapter < h.curPages.length - 1
        ? h.pageInChapter + 1
        : 0; // 跨章首页

    final offset = h.pageOffset;
    return ColoredBox(
      color: settings.backgroundColor,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (prevPage != null)
              Positioned(
                top: offset - ph,
                left: 0,
                right: 0,
                child: textPage(prevPage, prevIndex),
              ),
            Positioned(
                top: offset, left: 0, right: 0, child: textPage(cur, curIndex)),
            if (nextPage != null)
              Positioned(
                top: offset + ph,
                left: 0,
                right: 0,
                child: textPage(nextPage, nextIndex),
              ),
          ],
        ),
      ),
    );
  }

  /// scroll 模式 chrome 浮层(固定在视口, 不随滚动)。由 reader_view.build
  /// 在 _buildPageContent 之外的同级 Stack 挂载, 覆盖在正文之上。页码/进度
  /// 取 handler 当前可见页(滚动中实时变), 对齐原生 `setProgress` 每帧更新。
  Widget? _buildScrollChrome() {
    final h = _scrollHandler;
    if (h == null) return null;
    final c = widget.controller;
    final settings = c.settings;
    final showHeader = settings.hideStatusBar && !settings.headerConfig.hidden;
    final showFooter = !settings.footerConfig.hidden;
    if (!showHeader && !showFooter) return null;
    return IgnorePointer(
      child: Stack(
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
                    pageIndex: h.pageInChapter,
                    totalPages: h.curChapterPageCount,
                    chapterIndex: h.chapterIndex,
                    chapterSize: c.totalChapters,
                    chapterTitle: h.curChapterTitle,
                    bookName: c.book?.title,
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
                    pageIndex: h.pageInChapter,
                    totalPages: h.curChapterPageCount,
                    chapterIndex: h.chapterIndex,
                    chapterSize: c.totalChapters,
                    chapterTitle: h.curChapterTitle,
                    bookName: c.book?.title,
                    useSafeArea: false,
                    showChrome: false,
                    showFooterOnly: true,
                    batteryLevel: BatteryProvider.instance.value,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
