import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/core/models/reading_settings_codec.dart';
import 'package:flutter_reader/src/core/models/bookmark.dart';

void main() {
  /// ReadingSettings 编解码往返一致性: 默认值往返不丢字段。
  test('ReadingSettings 默认值 encode→decode 往返一致', () {
    final original = ReadingSettings();
    final json = encodeReadingSettings(original);
    final restored = decodeReadingSettings(json);

    expect(restored.fontSize, original.fontSize);
    expect(restored.lineHeight, original.lineHeight);
    expect(restored.paragraphSpacing, original.paragraphSpacing);
    expect(restored.letterSpacing, original.letterSpacing);
    expect(restored.backgroundColor, original.backgroundColor);
    expect(restored.textColor, original.textColor);
    expect(restored.tipColor, original.tipColor);
    // tipDividerColor 默认 null(跟随文字), 往返后仍为 null。
    expect(restored.tipDividerColor, original.tipDividerColor);
    // 自定义 tipDividerColor 往返(对齐原生 ReadTipConfig.tipDividerColor 自定义 ARGB)。
    final withDivider = original.copyWith(tipDividerColor: const Color(0xFF123456));
    expect(
      decodeReadingSettings(encodeReadingSettings(withDivider)).tipDividerColor,
      const Color(0xFF123456),
    );
    expect(restored.fontFamily, original.fontFamily);
    expect(restored.backgroundImage, original.backgroundImage);
    expect(restored.fontWeight, original.fontWeight);
    expect(restored.pageAnimMode, original.pageAnimMode);
    // 嵌套 config
    expect(restored.headerConfig.left, original.headerConfig.left);
    expect(restored.headerConfig.right, original.headerConfig.right);
    expect(restored.headerConfig.hidden, original.headerConfig.hidden);
    expect(restored.footerConfig.left, original.footerConfig.left);
    expect(restored.footerConfig.right, original.footerConfig.right);
    expect(restored.padding.top, original.padding.top);
    expect(restored.padding.footerHeight, original.padding.footerHeight);
    expect(restored.clickConfig.center, original.clickConfig.center);
    expect(restored.clickConfig.bottomRight, original.clickConfig.bottomRight);
    // bool / int 字段
    expect(restored.keepScreenOn, original.keepScreenOn);
    expect(restored.textFullJustify, original.textFullJustify);
    expect(restored.textIndent, original.textIndent);
    expect(restored.titleMode, original.titleMode);
    expect(restored.titleSize, original.titleSize);
  });

  /// 修改后的设置往返一致(覆盖非默认值)。
  test('ReadingSettings 自定义值 encode→decode 往返一致', () {
    final original = ReadingSettings().copyWith(
      fontSize: 32,
      lineHeight: 1.5,
      paragraphSpacing: 3.0,
      letterSpacing: 0.3,
      backgroundColor: const Color(0xFF123456),
      textColor: const Color(0xFFABCDEF),
      fontWeight: FontWeight.bold,
      pageAnimMode: PageAnimMode.scroll,
      headerConfig: const HeaderFooterConfig(
        left: TipPosition.time,
        center: TipPosition.battery,
        right: TipPosition.bookName,
        hidden: true,
      ),
      padding: const ReaderPadding(top: 30, footerHeight: 40),
      clickConfig: const ClickRegionConfig(
        center: ClickAction.nextPage,
        bottomRight: ClickAction.prevChapter,
      ),
      titleMode: 1,
      keepScreenOn: false,
    );
    final restored = decodeReadingSettings(encodeReadingSettings(original));

    expect(restored.fontSize, 32);
    expect(restored.lineHeight, 1.5);
    expect(restored.paragraphSpacing, 3.0);
    expect(restored.letterSpacing, 0.3);
    expect(restored.backgroundColor, const Color(0xFF123456));
    expect(restored.textColor, const Color(0xFFABCDEF));
    expect(restored.fontWeight, FontWeight.bold);
    expect(restored.pageAnimMode, PageAnimMode.scroll);
    expect(restored.headerConfig.left, TipPosition.time);
    expect(restored.headerConfig.center, TipPosition.battery);
    expect(restored.headerConfig.right, TipPosition.bookName);
    expect(restored.headerConfig.hidden, isTrue);
    expect(restored.padding.top, 30);
    expect(restored.padding.footerHeight, 40);
    expect(restored.clickConfig.center, ClickAction.nextPage);
    expect(restored.clickConfig.bottomRight, ClickAction.prevChapter);
    expect(restored.titleMode, 1);
    expect(restored.keepScreenOn, isFalse);
  });

  /// 解码部分字段缺失的旧 schema 时回落默认, 不报错(向前兼容)。
  test('decode 缺失字段时回落默认值(向前兼容)', () {
    final restored = decodeReadingSettings({
      'fontSize': 28,
      '_version': 1,
      // 其余字段缺失
    });
    expect(restored.fontSize, 28);
    expect(restored.lineHeight, ReadingSettings().lineHeight);
    expect(restored.padding.top, ReadingSettings().padding.top);
    expect(restored.pageAnimMode, ReadingSettings().pageAnimMode);
  });

  /// encode 输出可被 jsonEncode 序列化(无 Color/枚举等不可序列化对象)。
  test('encodeReadingSettings 输出可 JSON 字符串化', () {
    // 用 jsonEncode 检验: 若含 Color/枚举对象会抛异常
    final json = encodeReadingSettings(ReadingSettings());
    // 遍历所有值, 应都是基础类型
    void checkValue(dynamic v) {
      if (v is Map) {
        v.values.forEach(checkValue);
      } else if (v is List) {
        v.forEach(checkValue);
      } else {
        expect(v is String || v is num || v is bool || v == null, isTrue,
            reason: '值应为 JSON 基础类型, 实际 ${v.runtimeType}: $v');
      }
    }

    checkValue(json);
  });

  /// Bookmark toJson/fromJson 往返一致。
  test('Bookmark encode→decode 往返一致', () {
    final original = Bookmark(
      id: 'b1',
      bookId: 'book-1',
      chapterIndex: 3,
      pageIndex: 5,
      content: '某页首行内容',
      createdAt: DateTime(2026, 6, 29, 10, 30),
      chapterCharOffset: 128,
      userId: 'u1',
    );
    final json = original.toJson();
    final restored = Bookmark.fromJson(json, userId: 'u1');

    expect(restored.id, original.id);
    expect(restored.bookId, original.bookId);
    expect(restored.chapterIndex, original.chapterIndex);
    expect(restored.pageIndex, original.pageIndex);
    expect(restored.content, original.content);
    expect(restored.createdAt, original.createdAt);
    expect(restored.chapterCharOffset, original.chapterCharOffset);
    expect(restored.userId, 'u1');
  });

  /// 旧书签(无 chapterCharOffset)解码不报错, 该字段为 null。
  test('旧 Bookmark(无 charOffset)解码 charOffset 为 null', () {
    final restored = Bookmark.fromJson({
      'id': 'b2',
      'bookId': 'book-1',
      'chapterIndex': 0,
      'pageIndex': 0,
      'content': '',
      'createdAt': '2026-06-29T10:30:00.000',
    });
    expect(restored.chapterCharOffset, isNull);
    expect(restored.pageIndex, 0);
  });
}
