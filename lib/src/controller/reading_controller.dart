import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/reading_settings.dart';

class ReadingController extends ChangeNotifier {
  Book? _book;
  ReadingSettings _settings = ReadingSettings();
  int _currentPage = 0;

  Book? get book => _book;
  ReadingSettings get settings => _settings;
  int get currentPage => _currentPage;
  bool get canGoNext => _book?.currentChapter != null &&
      _currentPage < (_book?.currentChapter?.content.length ?? 0) - 1;
  bool get canGoPrevious => _currentPage > 0;

  void loadBook(Book book) {
    _book = book;
    _currentPage = 0;
    notifyListeners();
  }

  void updateSettings(ReadingSettings settings) {
    _settings = settings;
    notifyListeners();
  }

  void goToPage(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void nextPage() {
    if (canGoNext) {
      _currentPage++;
      notifyListeners();
    }
  }

  void previousPage() {
    if (canGoPrevious) {
      _currentPage--;
      notifyListeners();
    }
  }

  void nextChapter() {
    if (_book == null) return;
    if (_book!.currentChapterIndex < _book!.chapters.length - 1) {
      _book!.currentChapterIndex++;
      _currentPage = 0;
      notifyListeners();
    }
  }

  void previousChapter() {
    if (_book == null) return;
    if (_book!.currentChapterIndex > 0) {
      _book!.currentChapterIndex--;
      _currentPage = 0;
      notifyListeners();
    }
  }
}
