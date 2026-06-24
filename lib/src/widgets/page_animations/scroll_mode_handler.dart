import 'package:flutter/material.dart';
import '../../controller/reading_controller.dart';
import '../../models/reading_settings.dart';
import '../../models/text_page.dart';
import '../page_view.dart' as pv;

typedef PageBuilder = Widget Function(TextPage page, int index);

class ScrollModeHandler {
  final ScrollController scrollController = ScrollController();
  final ReadingController controller;
  int scrollPageIdx = 0;
  int _targetPageIdx = -1;
  bool _isUserScrolling = false;
  int _previousChapterIndex;

  ScrollModeHandler(this.controller)
      : _previousChapterIndex = controller.currentChapterIndex,
        scrollPageIdx = controller.currentPageIndex {
    scrollController.addListener(_onScrollUpdate);
  }

  void dispose() {
    scrollController.removeListener(_onScrollUpdate);
    scrollController.dispose();
  }

  void onPageChangedFromController() {
    final ci = controller.currentPageIndex;
    if (ci == scrollPageIdx) return;

    if (controller.currentChapterIndex != _previousChapterIndex) {
      _previousChapterIndex = controller.currentChapterIndex;
      if (_switchingToPrevious && controller.pages.isNotEmpty) {
        scrollPageIdx = controller.pages.length - 1;
        _switchingToPrevious = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      } else {
        scrollPageIdx = 0;
        if (scrollController.hasClients) scrollController.jumpTo(0);
      }
      return;
    }
    _scrollToPage(ci);
  }

  bool _handleChapterSwitch = false;
  bool _switchingToPrevious = false;

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _isUserScrolling = true;
        _targetPageIdx = -1;
        _handleChapterSwitch = false;
      }
      return false;
    }

    if (!_isUserScrolling) return false;

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels >= metrics.maxScrollExtent &&
          controller.canGoNext) {
        _handleChapterSwitch = true;
      } else if (metrics.pixels <= 0 && controller.canGoPrevious) {
        _handleChapterSwitch = true;
      }
      final page = _computePage();
      if (page != scrollPageIdx) {
        scrollPageIdx = page;
        controller.setCurrentPageIndex(page);
      }
    }

    if (notification is ScrollEndNotification) {
      _isUserScrolling = false;
      if (_handleChapterSwitch) {
        _handleChapterSwitch = false;
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent && controller.canGoNext) {
          _switchingToPrevious = false;
          controller.nextChapter();
          return true;
        } else if (metrics.pixels <= 0 && controller.canGoPrevious) {
          _switchingToPrevious = true;
          controller.previousChapter();
          return true;
        }
      }
      final page = _computePage();
      if (page != scrollPageIdx) {
        scrollPageIdx = page;
        controller.setCurrentPageIndex(page);
      }
    }
    return false;
  }

  Widget buildContent(
    BuildContext context,
    List<TextPage> pages,
    PageBuilder buildPage,
  ) {
    final settings = controller.settings;
    final padding = MediaQuery.of(context).padding;
    final showHeader = settings.hideStatusBar;
    final topInset = showHeader ? 0.0 : padding.top;
    final bottomInset = settings.hideNavigationBar ? 0.0 : padding.bottom;

    return Container(
      color: settings.backgroundColor,
      child: Column(
        children: [
          if (topInset > 0) SizedBox(height: topInset),
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildChrome(context, settings, header: true),
            ),
          if (showHeader && settings.showHeaderDivider)
            Container(height: 0.5, color: settings.backgroundColor),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                return NotificationListener<ScrollNotification>(
                  onNotification: handleScrollNotification,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        for (var i = 0; i < pages.length; i++) ...[
                          SizedBox(height: h, child: buildPage(pages[i], i)),
                          if (i < pages.length - 1)
                            Container(
                              height: 0.5,
                              color: settings.backgroundColor,
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (settings.showFooterDivider)
            Container(height: 0.5, color: Colors.grey.shade300),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildChrome(context, settings, header: false),
          ),
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildChrome(
    BuildContext context,
    ReadingSettings settings, {
    required bool header,
  }) {
    return pv.PageView(
      page: null,
      settings: settings,
      pageIndex: scrollPageIdx,
      totalPages: controller.totalPages,
      chapterTitle: controller.currentChapter?.title,
      bookName: controller.book?.title,
      useSafeArea: false,
      showHeaderOnly: header,
      showFooterOnly: !header,
    );
  }

  void _onScrollUpdate() {
    if (!scrollController.hasClients || _targetPageIdx < 0) return;
    if (!scrollController.position.isScrollingNotifier.value &&
        _computePage() == _targetPageIdx) {
      scrollPageIdx = _targetPageIdx;
      _targetPageIdx = -1;
    }
  }

  int _computePage() {
    if (!scrollController.hasClients) return scrollPageIdx;
    final ph = scrollController.position.viewportDimension;
    if (ph <= 0) return scrollPageIdx;
    return (scrollController.offset / ph)
        .round()
        .clamp(0, controller.pages.length - 1);
  }

  void _scrollToPage(int pageIdx) {
    if (!scrollController.hasClients) return;
    final ph = scrollController.position.viewportDimension;
    if (ph <= 0) return;
    final target = pageIdx * ph;
    if (controller.settings.noAnimScrollPage) {
      scrollController.jumpTo(target);
      scrollPageIdx = pageIdx;
    } else {
      _targetPageIdx = pageIdx;
      scrollController.animateTo(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }
}
