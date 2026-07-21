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

  /// scroll 模式专用: 确保 [_scrollHandler] 存在并同步数据。
  ///
  /// **常驻预热架构**(消除切到 scroll 的卡顿): handler 在首次调用时创建一次,
  /// **之后永不 dispose/重建**。scroll 子树([_buildScrollContent])与其 ListenableBuilder
  /// 因此始终挂载在屏外(非 scroll 模式), 切到 scroll 时 element 复用、layer 缓存命中,
  /// 无首次 layout/paint 开销 —— 这正是 slide/none/sim 互切不卡(共用三页 Stack, element
  /// 互相复用)、唯独切 scroll 卡(此前是互斥 return, 子树整体重建)的差异根因。
  ///
  /// handler 持有的 AnimationController 非动画时空转无开销; 相邻章预取在非 scroll 模式
  /// 也保持(顺带预热, 切回时命中)。所有手势调用点都已 guard `pageAnimMode == scroll`,
  /// 非 scroll 模式不会误调 handler。
  ///
  /// handler 自带 ChangeNotifier, rebuild 由 [_buildScrollContent] 内的
  /// `ListenableBuilder` 自动驱动(仅重绘依赖 pageOffset/章页码的子树), 不经过
  /// `_ReaderViewState.setState`(避免每帧整树 rebuild + relayout 的滚动卡顿)。
  void _ensureScrollHandler() {
    if (_scrollHandler != null) {
      // 已存在: 保持挂载, 不重建。切回非 scroll 模式时不 dispose, 让子树常驻预热。
      return;
    }
    _scrollHandler = ScrollModeHandler(widget.controller, this);
    // ⚠️ 首帧防闪: handler 的 _contentHeight 初始为 0, 若不立即初始化, build 里
    // ListenableBuilder 会命中 `ch <= 0` 兜底渲染一帧纯背景色 → 闪烁。
    // 切模式时 controller.pageSize 一定已就绪(切前页面就在显示), 这里同步喂一次,
    // 让 _contentHeight 在 build 前就有值, 消除首帧空窗。
    final ps = widget.controller.pageSize;
    if (ps.height > 0) {
      _scrollHandler!.updatePageHeight(ps.height);
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
    final c = widget.controller;
    final settings = c.settings;

    // scroll handler 常驻预热(永不随模式切换 dispose), 但首次进入阅读页时
    // _ensureScrollHandler 可能尚未执行(initState 末尾才调) → handler 暂为 null。
    // 返回纯背景占位, 不参与手势/渲染内容。
    final h = _scrollHandler;
    if (h == null) {
      return ColoredBox(color: settings.effectiveBackgroundColor, child: SizedBox());
    }

    // ⚠️ loading 收敛(修复"切模式闪 loading"): 仅当 curPages 真为空(章节首次加载)
    // 才显示转圈; pageHeight==0(切模式瞬间 LayoutBuilder 尚未回调)显示纯背景色占位,
    // 不闪转圈。对齐原生切模式「直接切、无 loading」。
    if (h.curPages.isEmpty) {
      return ColoredBox(
        color: settings.effectiveBackgroundColor,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                settings.effectiveTextColor.withValues(alpha: 0.4),
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
        // handler 常驻, _scrollHandler 不会在此期间变 null; ?? h 仅防御。
        final hh = _scrollHandler ?? h;
        final cc = widget.controller;
        final curPage = hh.curPage;
        final ch = hh.contentHeight;
        // contentHeight==0(切模式瞬间) → 纯背景色, 同帧 PostFrame updatePageHeight 后立即正常。
        if (curPage == null || ch <= 0) {
          return ColoredBox(color: settings.effectiveBackgroundColor, child: SizedBox());
        }

        // 渲染模型 cur / next / nextPlus(对齐原生 ContentTextView.drawPage,
        // ⚠️ 不画 prev 页)。原生平移用 relativeOffset, 只在 paint 算坐标; Flutter
        // 用 Transform.translate(paint 阶段平移, 不 relayout)等价。
        final nextPage = hh.nextPage;
        final nextPlusPage = hh.nextPlusPage;
        final offset = hh.pageOffset;

        // 纯正文页 widget(showChrome:false 只画正文行; 正文仅保留左右页边距,
        // 上下贴分隔线)。每页高度 = contentHeight(= pageSize.height, 对齐原生 visibleHeight)。
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

        // ⚠️ chrome 与正文对齐(修复「每页顶部文字被页眉盖住」):
        // 旧实现把 chrome 放外层 Positioned 浮层覆盖正文, 而正文 Column 只留了
        // 5px body padding、没给 header 留位置 → 正文从视口顶 0 起画, header
        // 背景直接盖住每页顶部第一/二行。
        //
        // 对齐普通翻页模式 PageView.build 的结构: SafeArea + Column[header, divider,
        // Expanded(正文), divider, footer]。chrome 与正文在同一 Column, 正文
        // Expanded 天然落在 header 下方, 像素级对齐, 不再用浮层覆盖。
        // chrome 内容(页码/进度)取 handler 当前可见页, 滚动中随 ListenableBuilder
        // 实时更新——与原浮层方案同样每帧刷新, 无额外开销。
        final showHeader = settings.hideStatusBar && !settings.headerConfig.hidden;
        final showFooter = !settings.footerConfig.hidden;
        // ⚠️ 分隔线由 pv.PageView(showHeaderOnly/showFooterOnly) 自带:
        // _buildChromeOnly(page_view.dart:124-135) 已按 showHeaderDivider/
        // showFooterDivider 在 chrome 行下/上方画一条 0.5px 分隔线(对齐原生
        // vw_top_divider 在页眉下方 / vw_bottom_divider 在页脚上方)。
        // 故此处不能再额外加 divider —— 否则与 PageView 自带分隔线重复, 上下两条
        // 0.5px 线中间夹着 headerBottom/footerTop padding, 视觉上是「比分隔线高一点
        // 的带」, 且比 nonContentHeight 预算(每侧只算 0.5px)多占高度, 把正文挤高。
        // 背景直接内联(对齐 page_view.dart 的 _buildBackground, 私有方法无法跨文件复用)。
        final bgDecoration = (settings.backgroundImage != null &&
                settings.backgroundImage!.isNotEmpty)
            ? BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(settings.backgroundImage!,
                      package: 'flutter_reader'),
                  fit: BoxFit.cover,
                ),
              )
            : BoxDecoration(color: settings.effectiveBackgroundColor);
        return DecoratedBox(
          decoration: bgDecoration,
          child: SafeArea(
            top: !settings.hideStatusBar,
            bottom: !settings.hideNavigationBar,
            child: Column(
              children: [
                if (showHeader)
                  pv.PageView(
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
                Expanded(
                  // 内容区 = 连续画布, 占满 Expanded(= pageSize.height)。
                  // 排版 availableHeight = pageSize.height(不减 padding, 见
                  // page_engine._splitIntoPages), 每页 SizedBox 步长 = contentHeight
                  // = pageSize.height, 与 contentStack 高一致 → cur+next 两页在 offset+ch
                  // 对接, contentStack 底 = footer 分隔线, 下一页首行从分隔线处露出
                  // (对齐原生: 滚动时字从分隔线出现)。
                  //
                  // ⚠️ 旧实现用 Column[padTop 条, Expanded(contentStack), padBottom 条]
                  // 两个固定条夹 contentStack, 把它压成 pageSize-padTop-padBottom,
                  // 下方 padBottom 条(默认4px)画在 contentStack 与 footer 分隔线之间 →
                  // 滚动时下一页首行从分隔线上方 4px 处露出, 而非贴分隔线。原生无此固定条,
                  // 故删之, 让 contentStack 直接占满贴 footer。
                  child: contentStack,
                ),
                if (showFooter)
                  pv.PageView(
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
              ],
            ),
          ),
        );
      },
    );
  }

  /// chrome(页眉/页脚)已在 [_buildScrollContent] 的正文 Column 内绘制
  /// (对齐普通翻页模式 PageView 的结构), 不再用外层浮层覆盖。
  /// 旧实现用 Positioned 浮层覆盖正文, 但正文 Column 只留 5px body padding、
  /// 没给 header 留位置 → 每页顶部文字被页眉背景盖住。已废弃。
}
