import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/reading_settings.dart';
import '../../reader/entities/text_page.dart';
import '../models/bookmark.dart';
import '../../reader/engine/page_engine.dart';
import '../content_processor.dart';

/// 预取(peek)的翻页目标信息。
///
/// 翻页动画在提交前需要知道目标页(及其所属章节/页码), 以便:
/// 1. 动画期间把目标页画到 prev/next 缓存槽;
/// 2. 动画结束时按 [chapterIndex] 判断是章内翻页还是跨章翻页, 精确提交。
///
/// 对齐原生 legado ReadView 三页缓存(prev/cur/nextPage)始终持有相邻页的做法,
/// 但 Flutter 端按需预取(仅在拖拽/动画期间持有), 避免常驻三页内存。
class PeekInfo {
  final TextPage page;
  final int chapterIndex;
  final int pageIndex;

  const PeekInfo({
    required this.page,
    required this.chapterIndex,
    required this.pageIndex,
  });
}

class ReadingController extends ChangeNotifier {
  Book? _book;
  ReadingSettings _settings = ReadingSettings();
  int _currentChapterIndex = 0;
  int _currentPageIndex = 0;
  List<TextPage> _pages = [];
  final List<Bookmark> _bookmarks = [];
  bool _menuVisible = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  List<int> _searchResults = [];
  int _searchResultIndex = -1;
  Size _pageSize = Size.zero;

  final PageEngine _pageEngine = PageEngine();

  /// 相邻章分页预计算缓存(章索引 → 分页结果)。
  ///
  /// 跨章 peek 时避免在翻页关键帧同步重排整章(实测一整章 100~140ms, 阻塞 6~8 帧
  /// → 跨章卡顿)。peekNext/peekPrev/_rePaginate 都走 [_paginateChapterCached]:
  /// 首次重排后结果入缓存, 后续 O(1) 命中。
  ///
  /// 缓存键 = 章索引; 整表失效条件见 [_invalidateAdjacentCache]:
  /// `_settings` 引用变或 `_pageSize` 变(两者决定分页结果)。
  final Map<int, List<TextPage>> _adjacentChapterCache = {};
  ReadingSettings? _cacheSettingsRef;
  Size _cachePageSize = Size.zero;

  Book? get book => _book;
  ReadingSettings get settings => _settings;
  int get currentChapterIndex => _currentChapterIndex;
  int get currentPageIndex => _currentPageIndex;
  List<TextPage> get pages => _pages;
  List<Bookmark> get bookmarks => _bookmarks;
  bool get menuVisible => _menuVisible;
  bool get searchVisible => _searchVisible;
  String get searchQuery => _searchQuery;
  List<int> get searchResults => _searchResults;
  int get searchResultIndex => _searchResultIndex;
  int get totalPages => _pages.length;
  bool get canGoNext => _currentPageIndex < _pages.length - 1 || _currentChapterIndex < (_book?.chapters.length ?? 0) - 1;
  bool get canGoPrevious => _currentPageIndex > 0 || _currentChapterIndex > 0;

  Chapter? get currentChapter =>
      _book != null && _book!.chapters.isNotEmpty
          ? _book!.chapters[_currentChapterIndex]
          : null;

  void loadBook(Book book) {
    _book = book;
    _currentChapterIndex = book.currentChapterIndex;
    _currentPageIndex = 0;
    _rePaginate();
    notifyListeners();
  }

  void updateSettings(ReadingSettings settings) {
    _settings = settings;
    _rePaginate();
    notifyListeners();
  }

  void updatePageSize(Size size) {
    if (_pageSize != size) {
      _pageSize = size;
      _rePaginate();
      notifyListeners();
    }
  }

  void goToPage(int page) {
    if (page >= 0 && page < _pages.length) {
      _currentPageIndex = page;
      notifyListeners();
    }
  }

  void setCurrentPageIndex(int page) {
    if (page >= 0 && page < _pages.length && page != _currentPageIndex) {
      _currentPageIndex = page;
      notifyListeners();
    }
  }

  void setCurrentChapterIndex(int index) {
    if (index >= 0 && index < totalChapters) {
      _currentChapterIndex = index;
    }
  }

  void nextPage() {
    if (_currentPageIndex < _pages.length - 1) {
      _currentPageIndex++;
      notifyListeners();
    } else if (_currentChapterIndex < (_book?.chapters.length ?? 0) - 1) {
      nextChapter();
    }
  }

  void previousPage() {
    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      notifyListeners();
    } else if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      if (_pages.isNotEmpty) {
        _currentPageIndex = _pages.length - 1;
      }
      notifyListeners();
    }
  }

  void nextChapter() {
    if (_book == null) return;
    if (_currentChapterIndex < _book!.chapters.length - 1) {
      _currentChapterIndex++;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
    }
  }

  void previousChapter() {
    if (_book == null) return;
    if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
    }
  }

  void goToChapter(int index) {
    if (_book == null || index < 0 || index >= _book!.chapters.length) return;
    _currentChapterIndex = index;
    _currentPageIndex = 0;
    _rePaginate();
    notifyListeners();
  }

  void toggleMenu() {
    _menuVisible = !_menuVisible;
    if (_menuVisible) _searchVisible = false;
    notifyListeners();
  }

  void hideMenu() {
    _menuVisible = false;
    notifyListeners();
  }

  void toggleSearch() {
    _searchVisible = !_searchVisible;
    _menuVisible = false;
    if (!_searchVisible) {
      _searchQuery = '';
      _searchResults = [];
      _searchResultIndex = -1;
    }
    notifyListeners();
  }

  void search(String query) {
    _searchQuery = query;
    _searchResults = [];
    _searchResultIndex = -1;
    if (query.isEmpty || _book == null) {
      notifyListeners();
      return;
    }
    for (var i = 0; i < _book!.chapters.length; i++) {
      if (_book!.chapters[i].content.contains(query)) {
        _searchResults.add(i);
      }
    }
    if (_searchResults.isNotEmpty) {
      _searchResultIndex = 0;
      goToChapter(_searchResults[0]);
    }
    notifyListeners();
  }

  void nextSearchResult() {
    if (_searchResults.isEmpty) return;
    _searchResultIndex = (_searchResultIndex + 1) % _searchResults.length;
    goToChapter(_searchResults[_searchResultIndex]);
    notifyListeners();
  }

  void previousSearchResult() {
    if (_searchResults.isEmpty) return;
    _searchResultIndex = (_searchResultIndex - 1 + _searchResults.length) % _searchResults.length;
    goToChapter(_searchResults[_searchResultIndex]);
    notifyListeners();
  }

  void addBookmark() {
    if (_book == null || currentChapter == null) return;
    final existing = _bookmarks.indexWhere(
      (b) => b.bookId == _book!.id && b.chapterIndex == _currentChapterIndex && b.pageIndex == _currentPageIndex,
    );
    if (existing >= 0) {
      _bookmarks.removeAt(existing);
    } else {
      final page = _pages.isNotEmpty && _currentPageIndex < _pages.length
          ? _pages[_currentPageIndex]
          : null;
      final content = page?.lines.take(2).map((l) => l.text).join() ?? '';
      _bookmarks.add(Bookmark(
        id: '${_book!.id}_${_currentChapterIndex}_$_currentPageIndex',
        bookId: _book!.id,
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex,
        content: content,
        createdAt: DateTime.now(),
      ));
    }
    notifyListeners();
  }

  bool isCurrentPageBookmarked() {
    if (_book == null) return false;
    return _bookmarks.any(
      (b) => b.bookId == _book!.id && b.chapterIndex == _currentChapterIndex && b.pageIndex == _currentPageIndex,
    );
  }

  ClickAction getClickAction(Offset position, Size size) {
    final col = position.dx < size.width / 3 ? 0 : (position.dx < size.width * 2 / 3 ? 1 : 2);
    final row = position.dy < size.height / 3 ? 0 : (position.dy < size.height * 2 / 3 ? 1 : 2);
    final config = _settings.clickConfig;
    if (row == 0 && col == 0) return config.topLeft;
    if (row == 0 && col == 1) return config.topCenter;
    if (row == 0 && col == 2) return config.topRight;
    if (row == 1 && col == 0) return config.middleLeft;
    if (row == 1 && col == 1) return config.center;
    if (row == 1 && col == 2) return config.middleRight;
    if (row == 2 && col == 0) return config.bottomLeft;
    if (row == 2 && col == 1) return config.bottomCenter;
    return config.bottomRight;
  }

  void handleClickAction(ClickAction action) {
    switch (action) {
      case ClickAction.menu:
        toggleMenu();
        break;
      case ClickAction.nextPage:
        nextPage();
        break;
      case ClickAction.prevPage:
        previousPage();
        break;
      case ClickAction.nextChapter:
        nextChapter();
        break;
      case ClickAction.prevChapter:
        previousChapter();
        break;
      case ClickAction.bookmark:
        addBookmark();
        break;
      case ClickAction.search:
        toggleSearch();
        break;
      case ClickAction.none:
        debugPrint('[Controller] clickAction is none, doing nothing');
        break;
    }
  }

  List<TextPage> paginateChapter(int chapterIndex) {
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= _book!.chapters.length) return [];
    return _pageEngine.paginate(
      content: _book!.chapters[chapterIndex].content,
      pageSize: _pageSize,
      settings: _settings,
    );
  }

  Chapter? getChapter(int index) {
    if (_book == null || index < 0 || index >= _book!.chapters.length) return null;
    return _book!.chapters[index];
  }

  int get totalChapters => _book?.chapters.length ?? 0;

  void _rePaginate() {
    if (_book == null || _pageSize == Size.zero) return;
    final chapter = currentChapter;
    if (chapter == null) {
      _pages = [];
      return;
    }
    _pages = _paginateChapterWithPipeline(_currentChapterIndex);
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.isEmpty ? 0 : _pages.length - 1;
    }
  }

  /// 对指定章节跑完整的内容预处理 + 排版管线, 返回分页结果。
  ///
  /// 抽取自原 `_rePaginate` 的内容管线(ContentProcessor → join → PageEngine.paginate),
  /// 供「重新分页当前章」与「预取相邻章(peek)」共用, 保证两者产出的页面完全一致——
  /// 否则 `paginateChapter()`(跳过 ContentProcessor) 与 `_rePaginate` 产出的页不同,
  /// 翻页动画展示的页与提交后看到的页会错位。
  ///
  /// 不修改 `_pages`/`_currentPageIndex` 等状态, 纯函数。
  List<TextPage> _paginateChapterWithPipeline(int chapterIndex) {
    return _paginateChapterCached(chapterIndex);
  }

  /// 带缓存的整章重排(供 peekNext/peekPrev/_rePaginate 共用)。
  ///
  /// 缓存键 = chapterIndex; 失效条件 = `_settings` 引用变 / `_pageSize` 变。
  /// 命中 → O(1) 返回; 未命中 → 同步重排(首次或失效后)。
  List<TextPage> _paginateChapterCached(int chapterIndex) {
    _invalidateAdjacentCacheIfNeeded();
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= _book!.chapters.length) return [];
    final cached = _adjacentChapterCache[chapterIndex];
    if (cached != null) return cached;

    final chapter = _book!.chapters[chapterIndex];
    final bookContent = ContentProcessor.getContent(
      title: chapter.title,
      content: chapter.content,
      bookName: _book!.title,
      textIndent: _settings.textIndent,
    );
    final processedContent = bookContent.textList.join('\n');
    final pages = _pageEngine.paginate(
      content: processedContent,
      pageSize: _pageSize,
      settings: _settings,
    );
    _adjacentChapterCache[chapterIndex] = pages;
    return pages;
  }

  /// 若影响分页结果的输入(settings / pageSize)发生变化, 清空整个相邻章缓存。
  /// `_settings` 每次 updateSettings 传入新对象, 引用比较即可判断变化。
  void _invalidateAdjacentCacheIfNeeded() {
    if (!identical(_settings, _cacheSettingsRef) || _pageSize != _cachePageSize) {
      _adjacentChapterCache.clear();
      _cacheSettingsRef = _settings;
      _cachePageSize = _pageSize;
    }
  }

  /// 预取下一页(无副作用: 不改变 currentPageIndex/chapterIndex/pages)。
  ///
  /// 章内有下一页 → 该页; 否则若存在下一章 → 下一章首页; 否则 null(无下一页)。
  /// 翻页动画据此把目标页画到 next 缓存槽, 动画结束按 info 提交。
  PeekInfo? peekNext() {
    if (_book == null) return null;
    if (_currentPageIndex < _pages.length - 1) {
      return PeekInfo(
        page: _pages[_currentPageIndex + 1],
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex + 1,
      );
    }
    // 当前章末页 → 下一章首页
    if (_currentChapterIndex < _book!.chapters.length - 1) {
      final nextChapterPages = _paginateChapterWithPipeline(_currentChapterIndex + 1);
      if (nextChapterPages.isNotEmpty) {
        return PeekInfo(
          page: nextChapterPages.first,
          chapterIndex: _currentChapterIndex + 1,
          pageIndex: 0,
        );
      }
    }
    return null;
  }

  /// 预取上一页(无副作用: 不改变 currentPageIndex/chapterIndex/pages)。
  ///
  /// 当前页 > 0 → 上一页; 否则若存在上一章 → 上一章末页; 否则 null(无上一页)。
  PeekInfo? peekPrev() {
    if (_book == null) return null;
    if (_currentPageIndex > 0) {
      return PeekInfo(
        page: _pages[_currentPageIndex - 1],
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex - 1,
      );
    }
    // 当前章首页 → 上一章末页
    if (_currentChapterIndex > 0) {
      final prevChapterPages = _paginateChapterWithPipeline(_currentChapterIndex - 1);
      if (prevChapterPages.isNotEmpty) {
        return PeekInfo(
          page: prevChapterPages.last,
          chapterIndex: _currentChapterIndex - 1,
          pageIndex: prevChapterPages.length - 1,
        );
      }
    }
    return null;
  }

  /// 预热当前章的相邻章(±1)到分页缓存。
  ///
  /// 由 reader_view 在章/页变化后通过 PostFrame 调用(不阻塞当前帧):
  /// 当用户还在章内逐页阅读时, 下一/上一章早已算好入缓存 → 翻到末页时
  /// peekNext 命中缓存(O(1)), 跨章不再卡顿。重排开销被摊到「用户刚进入
  /// 本章、尚未快速翻页」的时刻, 用户无感。
  ///
  /// 幂等: 命中缓存则跳过, 多次调用安全。
  void prefetchAdjacentChapters() {
    if (_book == null || _pageSize == Size.zero) return;
    final next = _currentChapterIndex + 1;
    final prev = _currentChapterIndex - 1;
    _paginateChapterCached(next);
    _paginateChapterCached(prev);
  }

  ///
  /// 翻页动画结束时调用: 把动画展示的目标页真正落到 controller 状态。
  /// 跨章时 goToChapter 会重排目标章(与 peek 跑的是同一管线, 页面一致),
  /// 再用 setCurrentPageIndex 落到目标页; 章内直接 goToPage。
  /// 对齐原生 legado `fillPage` → `moveToNext/moveToPrev`。
  void commitTurn(PeekInfo target) {
    if (target.chapterIndex == _currentChapterIndex) {
      // 章内翻页
      if (target.pageIndex != _currentPageIndex) {
        _currentPageIndex = target.pageIndex;
        notifyListeners();
      }
    } else {
      // 跨章翻页: goToChapter 会重排目标章并落到首页, 再定位到目标页。
      _currentChapterIndex = target.chapterIndex;
      _currentPageIndex = 0;
      _rePaginate();
      if (target.pageIndex < _pages.length) {
        _currentPageIndex = target.pageIndex;
      }
      notifyListeners();
    }
  }
}
