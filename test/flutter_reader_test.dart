import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  group('Book', () {
    test('should create book with chapters', () {
      final book = Book(
        id: '1',
        title: 'Test Book',
        author: 'Author',
        chapters: [
          Chapter(id: '1', title: 'Chapter 1', content: 'Content 1', index: 0),
          Chapter(id: '2', title: 'Chapter 2', content: 'Content 2', index: 1),
        ],
      );

      expect(book.title, 'Test Book');
      expect(book.chapters.length, 2);
      expect(book.currentChapter?.title, 'Chapter 1');
    });
  });

  group('ReadingSettings', () {
    test('should copy with new values', () {
      final settings = ReadingSettings();
      // 默认值为微信读书预设(fontSize=24), copyWith 成区分值验证不变性
      final newSettings = settings.copyWith(fontSize: 20.0);

      expect(newSettings.fontSize, 20.0);
      expect(settings.fontSize, 24.0, reason: '默认预设=微信读书 textSize=24');
    });
  });
}
