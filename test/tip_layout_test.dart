import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';
import 'package:flutter_reader/src/reader/widgets/tip_layout.dart';

/// 测量页脚内容行高。
///
/// 这些断言锁定 [measureChromeContentHeight] 的逐分支行为:
/// 三槽 none → 0; 文字槽 = 12sp 单行高; battery = 图标 size×aspect;
/// timeAndBattery = max(11sp 单行高, 图标); hidden → 0。
/// 当 page_view 渲染侧的尺寸常量(kTipTextSize 等)被改动时, 此处需同步。
void main() {
  final settings = ReadingSettings();

  group('measureTipContentHeight', () {
    test('none 槽高度为 0', () {
      expect(measureTipContentHeight(settings, TipPosition.none), 0);
    });

    test('文字槽 = 12sp 单行高(>0)', () {
      final h = measureTipContentHeight(settings, TipPosition.pageNumber);
      expect(h, greaterThan(0));
      // 与直接用 12sp 测单行一致
      final p = TextPainter(
        text: const TextSpan(
            text: '0/0', style: TextStyle(fontSize: kTipTextSize)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: double.infinity);
      expect(h, closeTo(p.height, 0.001));
      p.dispose();
    });

    test('battery 槽 = iconSize × aspect = 18 × 0.6 = 10.8', () {
      expect(measureTipContentHeight(settings, TipPosition.battery),
          closeTo(kBatteryIconSize * kBatteryIconAspect, 0.001));
    });

    test('timeAndBattery 槽 = max(11sp 行高, 16×0.6)', () {
      final h = measureTipContentHeight(settings, TipPosition.timeAndBattery);
      final tp = TextPainter(
        text: const TextSpan(
            text: '00:00',
            style: TextStyle(fontSize: kTipTimeBatteryTextSize)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: double.infinity);
      final expected = tp.height > kTimeBatteryIconSize * kBatteryIconAspect
          ? tp.height
          : kTimeBatteryIconSize * kBatteryIconAspect;
      expect(h, closeTo(expected, 0.001));
      tp.dispose();
    });

    test('各文字槽高度一致(都 12sp)', () {
      final h1 = measureTipContentHeight(settings, TipPosition.chapterTitle);
      final h2 = measureTipContentHeight(settings, TipPosition.bookName);
      final h3 = measureTipContentHeight(settings, TipPosition.time);
      expect(h1, closeTo(h2, 0.001));
      expect(h2, closeTo(h3, 0.001));
    });
  });

  group('measureChromeContentHeight', () {
    test('三槽 none → 0', () {
      const cfg =
          HeaderFooterConfig(left: TipPosition.none, right: TipPosition.none);
      expect(measureChromeContentHeight(settings, cfg), 0);
    });

    test('hidden → 0(无论三槽是什么)', () {
      const cfg = HeaderFooterConfig(
        left: TipPosition.bookName,
        right: TipPosition.pageAndTotal,
        hidden: true,
      );
      expect(measureChromeContentHeight(settings, cfg), 0);
    });

    test('取三槽最高者', () {
      const cfg = HeaderFooterConfig(
        left: TipPosition.none,                 // 0
        center: TipPosition.pageNumber,         // ~12sp 行高
        right: TipPosition.battery,             // 10.8
      );
      final h = measureChromeContentHeight(settings, cfg);
      final textOnly =
          measureTipContentHeight(settings, TipPosition.pageNumber);
      expect(h, closeTo(textOnly, 0.001));
      expect(h, greaterThan(measureTipContentHeight(settings, TipPosition.battery)));
    });

    test('默认 footer 配置(bookName + pageAndTotal)高度 > 0', () {
      final h = measureChromeContentHeight(settings, settings.footerConfig);
      expect(h, greaterThan(0));
    });
  });
}
