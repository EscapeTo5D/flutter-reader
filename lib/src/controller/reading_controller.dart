import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/reading_settings.dart';
import '../models/text_page.dart';
import '../models/bookmark.dart';
import '../engine/page_engine.dart';

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

  void _rePaginate() {
    if (_book == null || _pageSize == Size.zero) return;
    final chapter = currentChapter;
    if (chapter == null) {
      _pages = [];
      return;
    }
    _pages = _pageEngine.paginate(
      content: chapter.content,
      pageSize: _pageSize,
      settings: _settings,
    );
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.isEmpty ? 0 : _pages.length - 1;
    }
  }
}
