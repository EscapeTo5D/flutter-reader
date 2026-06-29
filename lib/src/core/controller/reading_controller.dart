import 'dart:async';

import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/reading_settings.dart';
import '../../reader/entities/text_page.dart';
import '../models/bookmark.dart';
import '../../reader/engine/page_engine.dart';
import '../content_processor.dart';
import '../storage/reader_repository.dart';
import '../storage/reading_progress.dart';

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

  // ─────────────────────────── 持久化 ───────────────────────────
  /// 持久化仓库(null = 纯内存模式, 退化为不落盘, 兼容旧用法)。
  ReaderRepository? _repository;

  /// 当前用户 id(null = 未绑定, 此时进度等不落盘)。
  String? _userId;

  /// 进度落盘防抖定时器: 翻页/翻章后延迟 [_progressSaveDebounce] 落盘, 期间
  /// 新动作重置定时器, 避免连续翻页每页一次 IO。
  Timer? _progressSaveTimer;

  /// 设置落盘防抖定时器。
  Timer? _settingsSaveTimer;

  /// 进度/设置防抖延迟。1.5s 覆盖典型连续翻页节奏, 又不至于太晚(用户秒退也兜得住)。
  static const Duration _progressSaveDebounce = Duration(milliseconds: 1500);

  /// 是否已 dispose。异步恢复(loadBook/restoreProgress)回调里用它防止
  /// dispose 后还 notifyListeners(ChangeNotifier 此版本无 mounted getter, 自管标志位)。
  bool _disposed = false;

  ReadingController({ReaderRepository? repository, String? userId})
      : _repository = repository,
        _userId = userId;

  /// 绑定持久化仓库与用户。两者任一为 null 则进入纯内存模式(不落盘)。
  /// 可在 [loadBook] 前后任意时刻调用; 已加载的书会立即触发一次进度恢复。
  void attachRepository(ReaderRepository repository, {String? userId}) {
    _repository = repository;
    if (userId != null) _userId = userId;
    // 若书已加载, 尝试用新用户恢复进度
    if (_book != null && _userId != null) {
      restoreProgress();
    }
  }

  /// 绑定/切换用户 id。切换后若书已加载, 立即恢复该用户在此书的进度。
  void bindUser(String userId) {
    _userId = userId;
    if (_book != null && _repository != null) {
      restoreProgress();
    }
  }

  ReaderRepository? get repository => _repository;
  String? get userId => _userId;

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
    // 书加载完(分页就绪)后, 异步从仓库恢复该用户的进度。
    // 不阻塞渲染: 即使恢复晚一帧也无妨, 用户先看到首页再被定位到上次位置。
    if (_repository != null && _userId != null) {
      restoreProgress();
    }
  }

  /// 从仓库恢复当前用户在当前书的进度。
  ///
  /// 流程: 取持久化的 (chapterIndex, chapterCharOffset) → 跳到该章 →
  /// 用 charOffset 二分 `_pages` 各页首行 chapterPosition 定位回页码 → 落位。
  /// 跨字号/换设备重排后仍能定位到正确页(charOffset 不随排版变), 不丢进度。
  ///
  /// 找不到记录或 charOffset 越界时保持首页(0), 不报错。
  /// 仅在 _pageSize 就绪(分页已完成)时生效; 否则等 updatePageSize 后再恢复。
  Future<void> restoreProgress() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    if (_pageSize == Size.zero) return; // 分页未就绪, 等尺寸回调

    final p = await repo.getProgress(uid, book.id);
    if (_disposed) return;

    if (p != null) {
      // 章节越界保护
      final targetChapter = p.chapterIndex.clamp(0, totalChapters - 1);
      if (targetChapter != _currentChapterIndex) {
        _currentChapterIndex = targetChapter;
        _currentPageIndex = 0;
        _rePaginate();
      }
      // charOffset → 页码
      final page = _pageIndexForCharOffset(p.chapterCharOffset);
      _currentPageIndex = page;
      notifyListeners();
    }
    // 无论有无进度记录, 都恢复该书的书签(书签独立于进度存在)。
    await loadBookmarks();
  }

  /// 把当前阅读位置(章+页)转成 [ReadingProgress] 落盘。
  ///
  /// charOffset 取当前页首行的 chapterPosition(页起点偏移, 比"页内某字"更稳定)。
  ReadingProgress? _currentProgress() {
    final book = _book;
    final uid = _userId;
    if (book == null || uid == null) return null;
    return ReadingProgress(
      userId: uid,
      bookId: book.id,
      chapterIndex: _currentChapterIndex,
      chapterCharOffset: _charOffsetForCurrentPage(),
      pageIndex: _currentPageIndex,
      lastReadAt: DateTime.now(),
    );
  }

  /// 当前页首行(第一个非空文字行)的 chapterPosition = 该页起始字符偏移。
  /// 找不到文字行时返回 0(降级到章首)。
  int _charOffsetForCurrentPage() {
    if (_pages.isEmpty || _currentPageIndex >= _pages.length) return 0;
    for (final line in _pages[_currentPageIndex].lines) {
      if (line.text.isNotEmpty) return line.chapterPosition;
    }
    return 0;
  }

  /// charOffset → 页码(二分各页首行 chapterPosition)。
  ///
  /// 找到「首行偏移 <= offset」的最后一页; offset 超过末页首行则落末页。
  /// 用于跨字号/换设备恢复进度——重排后页数变了, 但 charOffset 不变, 仍能定位。
  int _pageIndexForCharOffset(int charOffset) {
    if (_pages.isEmpty) return 0;
    var result = 0;
    for (var i = _pages.length - 1; i >= 0; i--) {
      final firstOffset = _firstCharOffsetOfPage(_pages[i]);
      if (firstOffset <= charOffset) {
        result = i;
        break;
      }
    }
    return result;
  }

  int _firstCharOffsetOfPage(TextPage page) {
    for (final line in page.lines) {
      if (line.text.isNotEmpty) return line.chapterPosition;
    }
    return 0;
  }

  /// 防抖落盘进度。翻页/翻章/恢复后调用, 1.5s 内无新动作才真正写库。
  void _scheduleProgressSave() {
    if (_repository == null || _userId == null || _book == null) return;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(_progressSaveDebounce, () {
      final p = _currentProgress();
      if (p != null) {
        _repository!.saveProgress(p);
      }
    });
  }

  /// 立即落盘进度(取消防抖定时器, 同步写)。dispose 时调用确保不丢。
  Future<void> flushProgress() async {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
    final p = _currentProgress();
    if (p != null && _repository != null) {
      await _repository!.saveProgress(p);
    }
  }

  void updateSettings(ReadingSettings settings) {
    _settings = settings;
    _rePaginate();
    notifyListeners();
    _scheduleSettingsSave();
    // 设置变了会重排, 重新按当前 charOffset 定位回对应页(避免因排版变而停在错误的页)
    _scheduleProgressSave();
  }

  void updatePageSize(Size size) {
    if (_pageSize != size) {
      _pageSize = size;
      _rePaginate();
      notifyListeners();
      // 尺寸就绪后, 若仓库里有进度且尚未恢复(loadBook 时可能 pageSize 还是 zero), 现在恢复。
      if (_repository != null && _userId != null && _book != null) {
        restoreProgress();
      }
    }
  }

  /// 防抖落盘设置。改字号/行距/颜色等频繁操作时, 1.5s 内最后状态写一次。
  void _scheduleSettingsSave() {
    if (_repository == null) return;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(_progressSaveDebounce, () {
      _repository!.saveSettings(_settings, userId: _userId);
    });
  }

  void goToPage(int page) {
    if (page >= 0 && page < _pages.length) {
      _currentPageIndex = page;
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void setCurrentPageIndex(int page) {
    if (page >= 0 && page < _pages.length && page != _currentPageIndex) {
      _currentPageIndex = page;
      notifyListeners();
      _scheduleProgressSave();
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
      _scheduleProgressSave();
    } else if (_currentChapterIndex < (_book?.chapters.length ?? 0) - 1) {
      nextChapter();
    }
  }

  void previousPage() {
    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      notifyListeners();
      _scheduleProgressSave();
    } else if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      if (_pages.isNotEmpty) {
        _currentPageIndex = _pages.length - 1;
      }
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void nextChapter() {
    if (_book == null) return;
    if (_currentChapterIndex < _book!.chapters.length - 1) {
      _currentChapterIndex++;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void previousChapter() {
    if (_book == null) return;
    if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void goToChapter(int index) {
    if (_book == null || index < 0 || index >= _book!.chapters.length) return;
    _currentChapterIndex = index;
    _currentPageIndex = 0;
    _rePaginate();
    notifyListeners();
    _scheduleProgressSave();
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
      final removed = _bookmarks.removeAt(existing);
      // 同步删除持久化书签
      if (_repository != null && removed.userId == _userId) {
        _repository!.deleteBookmark(removed.id);
      }
    } else {
      final page = _pages.isNotEmpty && _currentPageIndex < _pages.length
          ? _pages[_currentPageIndex]
          : null;
      final content = page?.lines.take(2).map((l) => l.text).join() ?? '';
      final bookmark = Bookmark(
        id: '${_book!.id}_${_currentChapterIndex}_$_currentPageIndex',
        bookId: _book!.id,
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex,
        content: content,
        createdAt: DateTime.now(),
        chapterCharOffset: _charOffsetForCurrentPage(),
        userId: _userId,
      );
      _bookmarks.add(bookmark);
      // 同步落库
      if (_repository != null && _userId != null) {
        _repository!.saveBookmark(bookmark);
      }
    }
    notifyListeners();
  }

  /// 从仓库恢复当前用户在当前书的所有书签到内存 [_bookmarks]。
  /// 仅在仓库/用户已绑定时生效; 失败则保持现有内存书签。
  Future<void> loadBookmarks() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    final stored = await repo.getBookmarks(uid, book.id);
    if (_disposed) return;
    // 合并: 移除该书旧的内存书签, 用持久化数据替换
    _bookmarks.removeWhere((b) => b.bookId == book.id);
    _bookmarks.addAll(stored);
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
        _scheduleProgressSave();
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
      _scheduleProgressSave();
    }
  }

  /// 从仓库恢复阅读设置(优先当前用户, 回退全局)。
  ///
  /// 典型用法: 宿主在创建 controller 并 attachRepository 后、loadBook 前调用,
  /// 让字号/行距/颜色等恢复到上次状态。无记录时保持默认不动。
  Future<void> loadSettings() async {
    final repo = _repository;
    if (repo == null) return;
    // 优先取用户设置, 没有再取全局
    final s = (await repo.getSettings(userId: _userId)) ??
        await repo.getSettings();
    if (s != null && !_disposed) {
      _settings = s;
      _rePaginate();
      notifyListeners();
    }
  }

  /// 把当前书加入书架(保存元信息)。仅在有仓库+用户时生效。
  Future<void> saveToShelf() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    await repo.saveBookMeta(uid, book);
  }

  @override
  void dispose() {
    _disposed = true;
    // 取消防抖定时器。注意: 这里不 await flushProgress——dispose 不能是 async。
    // 待落盘的进度若关键, 宿主应在 dispose 前手动调 await flushProgress()。
    // 此处做 best-effort: 若定时器正在等待, 立即触发一次同步落盘(忽略返回 future)。
    final pending = _currentProgress();
    _progressSaveTimer?.cancel();
    _settingsSaveTimer?.cancel();
    if (pending != null && _repository != null) {
      _repository!.saveProgress(pending); // fire-and-forget
    }
    super.dispose();
  }
}
