import 'package:flutter/material.dart';
import '../../controller/reading_controller.dart';
import '../../models/reading_settings.dart';
import '../../models/text_page.dart';
import '../page_view.dart' as pv;

typedef PageBuilder = Widget Function(TextPage page, int index);

class ScrollModeHandler {
  final ScrollController scrollController = ScrollController();
  final ReadingController controller;
  VoidCallback? onStateChanged;

  int _chapterIndex;
  List<TextPage> _prevPages = [];
  List<TextPage> _currentPages = [];
  List<TextPage> _nextPages = [];
  bool _switchingChapter = false;
  bool _justSwitched = false;

  bool _loadingPages = false;

  ScrollModeHandler(this.controller)
      : _chapterIndex = controller.currentChapterIndex {
    _currentPages = List.from(controller.pages);
    _loadAdjacentPagesAsync();
  }

  void dispose() {
    scrollController.dispose();
  }

  List<TextPage> get _combinedPages => [..._prevPages, ..._currentPages, ..._nextPages];

  int get _currentChapterStart => _prevPages.length;
  int get _currentChapterEnd => _prevPages.length + _currentPages.length;

  void _loadAdjacentPages() {
    if (_currentPages.isEmpty && controller.pages.isNotEmpty) {
      _currentPages = List.from(controller.pages);
    }
    if (_chapterIndex > 0) {
      _prevPages = controller.paginateChapter(_chapterIndex - 1);
    } else {
      _prevPages = [];
    }
    if (_chapterIndex < controller.totalChapters - 1) {
      _nextPages = controller.paginateChapter(_chapterIndex + 1);
    } else {
      _nextPages = [];
    }
  }

  void _loadAdjacentPagesAsync() {
    if (_loadingPages) return;
    _loadingPages = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadingPages = false;
      if (_currentPages.isEmpty && controller.pages.isNotEmpty) {
        _currentPages = List.from(controller.pages);
      }
      _loadAdjacentPages();
      onStateChanged?.call();
    });
  }

  void onPageChangedFromController() {
    final ci = controller.currentChapterIndex;
    if (ci != _chapterIndex) {
      _chapterIndex = ci;
      _currentPages = List.from(controller.pages);
      _loadAdjacentPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });
      onStateChanged?.call();
    } else if (controller.pages.isNotEmpty &&
        !identical(controller.pages, _currentPages) &&
        controller.pages.length != _currentPages.length) {
      _currentPages = List.from(controller.pages);
      _loadAdjacentPagesAsync();
      onStateChanged?.call();
    }
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _switchingChapter = false;
      }
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      _checkChapterBoundary(notification.metrics);
      _syncCurrentPage();
    }

    if (notification is ScrollEndNotification) {
      _justSwitched = false;
      _syncCurrentPage();
    }
    return false;
  }

  void _checkChapterBoundary(ScrollMetrics metrics) {
    if (_switchingChapter || _justSwitched) return;

    final threshold = metrics.viewportDimension * 0.3;

    if (metrics.pixels >= metrics.maxScrollExtent - threshold) {
      _appendNextChapter();
    } else if (metrics.pixels <= threshold && _prevPages.isNotEmpty) {
      _prependPrevChapter();
    }
  }

  void _appendNextChapter() {
    final nextChapterIdx = _chapterIndex + 1;
    if (nextChapterIdx >= controller.totalChapters) return;
    if (_nextPages.isEmpty) return;

    _switchingChapter = true;
    _justSwitched = true;
    _chapterIndex = nextChapterIdx;
    _currentPages = _nextPages;

    if (nextChapterIdx < controller.totalChapters - 1) {
      _nextPages = controller.paginateChapter(nextChapterIdx + 1);
    } else {
      _nextPages = [];
    }

    _prevPages = controller.paginateChapter(_chapterIndex - 1);
    _updateControllerSilent(_chapterIndex, 0);
    onStateChanged?.call();
  }

  void _prependPrevChapter() {
    final prevChapterIdx = _chapterIndex - 1;
    if (prevChapterIdx < 0) return;
    if (_prevPages.isEmpty) return;

    _switchingChapter = true;
    _justSwitched = true;
    final prependedHeight = _prevPages.length * _pageHeight + (_prevPages.length) * 0.5;

    _chapterIndex = prevChapterIdx;
    _currentPages = _prevPages;

    if (prevChapterIdx > 0) {
      _prevPages = controller.paginateChapter(prevChapterIdx - 1);
    } else {
      _prevPages = [];
    }

    _nextPages = controller.paginateChapter(_chapterIndex + 1);
    _updateControllerSilent(_chapterIndex, _currentPages.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.offset + prependedHeight);
      }
      _switchingChapter = false;
      onStateChanged?.call();
    });
  }

  void _updateControllerSilent(int chapterIndex, int pageIndex) {
    controller.setCurrentChapterIndex(chapterIndex);
    controller.setCurrentPageIndex(pageIndex);
  }

  void _syncCurrentPage() {
    if (!scrollController.hasClients) return;
    final offset = scrollController.offset;
    final combined = _combinedPages;
    if (combined.isEmpty) return;

    final pageIdx = _offsetToPage(offset);
    if (pageIdx < 0 || pageIdx >= combined.length) return;

    if (pageIdx >= _currentChapterStart && pageIdx < _currentChapterEnd) {
      final relIdx = pageIdx - _currentChapterStart;
      controller.setCurrentPageIndex(relIdx);
    }
  }

  int _offsetToPage(double offset) {
    if (_pageHeight <= 0) return 0;
    return (offset / (_pageHeight + 0.5)).floor().clamp(0, _combinedPages.length - 1);
  }

  double _pageHeight = 0;

  Widget buildContent(
    BuildContext context,
    List<TextPage> pages,
    PageBuilder buildPage,
  ) {
    if (_chapterIndex != controller.currentChapterIndex) {
      _chapterIndex = controller.currentChapterIndex;
      _currentPages = List.from(pages);
      _loadAdjacentPages();
    } else if (_currentPages.isEmpty && pages.isNotEmpty) {
      _currentPages = List.from(pages);
      _loadAdjacentPagesAsync();
    }

    final combined = _combinedPages;
    final settings = controller.settings;
    final padding = MediaQuery.of(context).padding;
    final showHeader = settings.hideStatusBar;
    final topInset = showHeader ? 0.0 : padding.top;

    return Container(
      color: settings.backgroundColor,
      child: Column(
        children: [
          if (topInset > 0) SizedBox(height: topInset),
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildChrome(context, settings),
            ),
          if (showHeader && settings.showHeaderDivider)
            Container(height: 0.5, color: settings.backgroundColor),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _pageHeight = constraints.maxHeight;
                return NotificationListener<ScrollNotification>(
                  onNotification: handleScrollNotification,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        for (var i = 0; i < combined.length; i++) ...[
                          SizedBox(
                            height: _pageHeight,
                            child: buildPage(combined[i], i),
                          ),
                          if (i < combined.length - 1)
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
        ],
      ),
    );
  }

  Widget _buildChrome(BuildContext context, ReadingSettings settings) {
    return pv.PageView(
      page: null,
      settings: settings,
      pageIndex: controller.currentPageIndex,
      totalPages: controller.totalPages,
      chapterTitle: controller.currentChapter?.title,
      bookName: controller.book?.title,
      useSafeArea: false,
      showHeaderOnly: true,
    );
  }
}
