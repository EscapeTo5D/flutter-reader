import 'package:flutter/material.dart';
import '../controller/reading_controller.dart';
import 'legado_icons.dart';

class ChapterListPage extends StatefulWidget {
  final ReadingController controller;

  const ChapterListPage({super.key, required this.controller});

  @override
  State<ChapterListPage> createState() => _ChapterListPageState();
}

class _ChapterListPageState extends State<ChapterListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: LegadoIcons.arrowBack(size: 24, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TabBar(
          controller: _tabController,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Theme.of(context).colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '目录'),
            Tab(text: '书签'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ChapterListView(controller: widget.controller),
          _BookmarkListView(controller: widget.controller),
        ],
      ),
    );
  }
}

class _ChapterListView extends StatefulWidget {
  final ReadingController controller;
  const _ChapterListView({required this.controller});

  @override
  State<_ChapterListView> createState() => _ChapterListViewState();
}

class _ChapterListViewState extends State<_ChapterListView> {
  late final ScrollController _scrollController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentIndex = widget.controller.currentChapterIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final offset =
        (_currentIndex * 48.0) -
        (_scrollController.position.viewportDimension / 2) +
        24;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) return const SizedBox();
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final currentChapter = widget.controller.currentChapter;
    final currentTitle = currentChapter?.title ?? '';
    final total = book.chapters.length;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: total,
            itemExtent: 48,
            itemBuilder: (ctx, i) {
              final isCurrent = i == _currentIndex;
              return InkWell(
                onTap: () {
                  widget.controller.goToChapter(i);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.chapters[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black87,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        LegadoIcons.check(
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildBottomInfoBar(
          context,
          currentTitle: currentTitle,
          currentIndex: _currentIndex,
          total: total,
          bottomPadding: bottomPadding,
          onScrollToCurrent: _scrollToCurrent,
          onScrollToTop: _scrollToTop,
          onScrollToBottom: _scrollToBottom,
        ),
      ],
    );
  }
}

class _BookmarkListView extends StatefulWidget {
  final ReadingController controller;
  const _BookmarkListView({required this.controller});

  @override
  State<_BookmarkListView> createState() => _BookmarkListViewState();
}

class _BookmarkListViewState extends State<_BookmarkListView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) return const SizedBox();
    final bookmarks = widget.controller.bookmarks;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (bookmarks.isEmpty) {
      return const Center(
        child: Text('暂无书签', style: TextStyle(color: Colors.black54, fontSize: 14)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: bookmarks.length,
            itemBuilder: (ctx, i) {
              final bm = bookmarks[i];
              final chapterName = bm.chapterIndex < book.chapters.length
                  ? book.chapters[bm.chapterIndex].title
                  : '未知章节';
              return InkWell(
                onTap: () {
                  widget.controller.goToChapter(bm.chapterIndex);
                  widget.controller.goToPage(bm.pageIndex);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      if (bm.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bm.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: bottomPadding),
      ],
    );
  }
}

Widget _buildBottomInfoBar(
  BuildContext context, {
  required String currentTitle,
  required int currentIndex,
  required int total,
  required double bottomPadding,
  required VoidCallback onScrollToCurrent,
  required VoidCallback onScrollToTop,
  required VoidCallback onScrollToBottom,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, -1),
        ),
      ],
    ),
    padding: EdgeInsets.only(left: 10, right: 10, bottom: bottomPadding),
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onScrollToCurrent,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  '$currentTitle(${currentIndex + 1}/$total)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onScrollToTop,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LegadoIcons.arrowDropUp(size: 20, color: Colors.black54),
            ),
          ),
          InkWell(
            onTap: onScrollToBottom,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LegadoIcons.arrowDropDown(size: 20, color: Colors.black54),
            ),
          ),
        ],
      ),
    ),
  );
}
