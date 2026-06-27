import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 【行距/段距语义对齐原生 legado - 回归测试】
///
/// 验证 Flutter 行高模型与原生公式一致:
///   textHeight        = 纯字体度量(由 metric.height/lineHeight 反推)
///   lineHeight(系数)  = 默认 1.2  (原生 lineSpacingExtra=12/10)
///   paragraphSpacing  = 默认 2     (原生 paragraphSpacing 配置值)
///   渲染行高 = textHeight * lineHeight
///   段距     = textHeight * paragraphSpacing / 10
void main() {
  test('默认配置: lineHeight=1.2, paragraphSpacing=2', () {
    final settings = ReadingSettings();
    expect(settings.lineHeight, 1.2, reason: '对齐原生 lineSpacingExtra=12/10');
    expect(settings.paragraphSpacing, 2.0, reason: '对齐原生 paragraphSpacing 配置值');
  });

  test('每行渲染高度 = textHeight * lineHeight (反推一致性)', () {
    final settings = ReadingSettings(); // lineHeight=1.2
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    final pages = engine.paginate(
      content: '　　这是一段比较长的中文文字用来触发换行一二三四五六七八九十百千万abcdef。',
      pageSize: pageSize,
      settings: settings,
    );

    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isEmptyParagraph || !line.hasCharData) continue;
        // textHeight 反推 = height / lineHeight
        final backDerived = line.height / settings.lineHeight;
        expect((line.textHeight - backDerived).abs(), lessThan(0.01),
            reason: 'textHeight 应为 height/lineHeight');
        // 渲染行高 = textHeight * lineHeight
        final expected = line.textHeight * settings.lineHeight;
        expect((line.height - expected).abs(), lessThan(0.01),
            reason: '行高应等于 textHeight * lineHeight');
        debugPrint('行 height=${line.height.toStringAsFixed(2)} '
            'textHeight=${line.textHeight.toStringAsFixed(2)} '
            '比值=${(line.height / line.textHeight).toStringAsFixed(3)} (应≈${settings.lineHeight})');
      }
    }
  });

  test('段距 = textHeight * paragraphSpacing / 10', () {
    final settings = ReadingSettings(); // paragraphSpacing=2
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    // 两段文字, 中间产生一个空段落行(段距)
    final pages = engine.paginate(
      content: '　　第一段文字内容。这是第一段的第二行。\n　　第二段文字内容。',
      pageSize: pageSize,
      settings: settings,
    );

    double? textHeight;
    double? paraSpacingH;
    for (final page in pages) {
      for (final line in page.lines) {
        if (line.isEmptyParagraph) {
          paraSpacingH = line.height;
        } else if (line.hasCharData && textHeight == null) {
          textHeight = line.textHeight;
        }
      }
    }
    debugPrint('textHeight=$textHeight 段距行height=$paraSpacingH');
    expect(textHeight, isNotNull);
    expect(paraSpacingH, isNotNull);
    final expected = textHeight! * settings.paragraphSpacing / 10.0;
    expect((paraSpacingH! - expected).abs(), lessThan(0.01),
        reason: '段距应等于 textHeight * paragraphSpacing / 10');
  });

  test('段距随 paragraphSpacing 线性变化', () {
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();
    const content = '　　第一段文字内容。\n　　第二段文字内容。';

    double spacingFor(double paraSpacing) {
      final settings = ReadingSettings()..paragraphSpacing = paraSpacing;
      final pages = engine.paginate(
          content: content, pageSize: pageSize, settings: settings);
      for (final page in pages) {
        for (final line in page.lines) {
          if (line.isEmptyParagraph) return line.height;
        }
      }
      return -1.0;
    }

    final s1 = spacingFor(1.0);
    final s2 = spacingFor(2.0);
    final s4 = spacingFor(4.0);
    debugPrint('paragraphSpacing=1→段距=$s1, =2→$s2, =4→$s4');
    // 线性: s2 ≈ 2*s1, s4 ≈ 4*s1
    expect((s2 - 2 * s1).abs(), lessThan(0.1));
    expect((s4 - 4 * s1).abs(), lessThan(0.1));
  });
}
