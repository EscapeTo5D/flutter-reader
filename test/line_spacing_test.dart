import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/engine/page_engine.dart';
import 'package:flutter_reader/src/core/models/reading_settings.dart';

/// 【行距/段距语义对齐原生 legado - 回归测试】
///
/// 验证 Flutter 行高模型与原生公式一致:
///   textHeight        = 纯字体度量(由 metric.height/lineHeight 反推)
///   lineHeight(系数)  = 默认 1.0  (默认预设=微信读书, lineSpacingExtra=10/10)
///   paragraphSpacing  = 默认 6     (微信读书 paragraphSpacing 配置值)
///   渲染行高 = textHeight * lineHeight
///   段距     = textHeight * paragraphSpacing / 10
void main() {
  test('默认配置(微信读书预设): lineHeight=1.0, paragraphSpacing=6', () {
    final settings = ReadingSettings();
    expect(settings.lineHeight, 1.0, reason: '对齐原生 lineSpacingExtra=10/10');
    expect(settings.paragraphSpacing, 6.0, reason: '微信读书 paragraphSpacing 配置值');
  });

  test('每行渲染高度 = textHeight * lineHeight * nativeMetricFactor(1.4)', () {
    // 补偿后恒等式多 1.4 系数(对齐原生中文字体 ratio):
    //   height = textHeight * lineHeight * 1.4 = metric.height * 1.4
    final settings = ReadingSettings()..lineHeight = 1.2; // 用非1.0验证反推
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
        // textHeight 仍为纯字体度量(height 不含补偿, = metric.height/lineHeight)
        final backDerived = line.height / settings.lineHeight / 1.4;
        expect((line.textHeight - backDerived).abs(), lessThan(0.01),
            reason: 'textHeight 应为 height/lineHeight/1.4');
        // 渲染行高 = textHeight * lineHeight * 1.4(含字体度量补偿)
        final expected = line.textHeight * settings.lineHeight * 1.4;
        expect((line.height - expected).abs(), lessThan(0.01),
            reason: '行高应等于 textHeight * lineHeight * 1.4');
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
        // 跳过末页留白行(isEndPadding), 它不是段距
        if (line.isEndPadding) continue;
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
    // 段距 = textHeight * paragraphSpacing / 10 * 1.4(含字体度量补偿)
    final expected = textHeight! * settings.paragraphSpacing / 10.0 * 1.4;
    expect((paraSpacingH! - expected).abs(), lessThan(0.01),
        reason: '段距应等于 textHeight * paragraphSpacing / 10 * 1.4');
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
          if (line.isEndPadding) continue; // 跳过末页留白
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

  /// 【baseline 对齐原生 legado - 回归测试】
  ///
  /// 原生 upTopBottom (TextLine.kt:103-107): 文字顶部对齐 textHeight 顶部,
  /// lineSpacingExtra 的缝全部留在行块下方。
  ///   lineBase = textHeight - fontMetrics.descent
  ///
  /// 旧实现误用 Flutter 的 metric.baseline, Skia 会把 leading 摊在文字上方,
  /// lineHeight 越大文字在行块里越偏下, 与原生视觉不对等:
  ///   h=1.0 时一致(缝为0); h=1.2 时偏 ~4.8px; h=1.5 时偏 ~12px (fs=24 实测)。
  /// 此测试锁定 baseline 按"原生公式重算 + 文字顶部对齐"的语义。
  test('lineBase 按原生公式重算(textHeight - descent), 文字顶部对齐行块', () {
    const pageSize = Size(360.0, 600.0);
    final engine = PageEngine();

    for (final lh in [1.0, 1.2, 1.5]) {
      final settings = ReadingSettings()..lineHeight = lh;
      final pages = engine.paginate(
        content: '　　这是一段比较长的中文文字用来触发换行一二三四五六七八九十百千万。',
        pageSize: pageSize,
        settings: settings,
      );

      for (final page in pages) {
        for (final line in page.lines) {
          if (line.isEmptyParagraph || !line.hasCharData) continue;
          // 重算原生 baseline 所需的 descent: 用 TextPainter 取该字号字体的 descent。
          final p = TextPainter(
            text: TextSpan(
                text: '我',
                style: TextStyle(fontSize: settings.fontSize, height: lh)),
            textDirection: TextDirection.ltr,
          )..layout();
          final descent = p.computeLineMetrics().first.descent;

          final expected = line.textHeight - descent;
          expect((line.lineBase - expected).abs(), lessThan(0.5),
              reason: 'lineBase 应= textHeight($line) - descent($descent) '
                  '= $expected (lh=$lh), 实际 ${line.lineBase}');
          debugPrint('lh=$lh lineBase=${line.lineBase.toStringAsFixed(2)} '
              '原生=${expected.toStringAsFixed(2)} '
              '缝下方=${(line.height - line.textHeight).toStringAsFixed(2)}');
        }
      }
    }
  });
}
