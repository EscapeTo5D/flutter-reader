import 'package:flutter/material.dart';
import '../models/text_page.dart';
import '../models/reading_settings.dart';

class PageEngine {
  List<TextPage> paginate({
    required String content,
    required Size pageSize,
    required ReadingSettings settings,
  }) {
    if (content.isEmpty) return [];

    final paragraphs = content.split('\n');
    final lines = <TextLine>[];

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      if (para.trim().isEmpty) {
        lines.add(TextLine(text: '', height: settings.paragraphSpacing, isParagraphEnd: true));
        continue;
      }
      final isTitle = _isTitle(para);
      final style = _textStyle(settings, isTitle: isTitle);
      final textLines = _wrapText(
        text: para,
        style: style,
        maxWidth: pageSize.width - settings.padding.left - settings.padding.right,
        indent: isTitle ? 0 : settings.textIndent,
        letterSpacing: settings.letterSpacing,
      );
      lines.addAll(textLines);
    }

    return _splitIntoPages(
      lines: lines,
      pageSize: pageSize,
      settings: settings,
    );
  }

  List<TextLine> _wrapText({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int indent,
    required double letterSpacing,
  }) {
    final result = <TextLine>[];
    final indentStr = indent > 0 ? '\u3000' * indent : '';
    final displayText = '$indentStr$text';

    final painter = TextPainter(
      text: TextSpan(text: displayText, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    painter.layout(maxWidth: maxWidth);

    final lineMetrics = painter.computeLineMetrics();
    if (lineMetrics.isEmpty) {
      result.add(TextLine(text: displayText, height: style.fontSize! * (style.height ?? 1.5)));
      return result;
    }

    int offset = 0;
    for (var i = 0; i < lineMetrics.length; i++) {
      final metric = lineMetrics[i];
      final startOffset = offset;
      int endOffset;

      if (i == lineMetrics.length - 1) {
        endOffset = displayText.length;
      } else {
        final nextMetric = lineMetrics[i + 1];
        final charOffset = painter.getPositionForOffset(
          Offset(nextMetric.left, nextMetric.baseline),
        );
        endOffset = charOffset.offset;
      }

      final lineText = displayText.substring(startOffset, endOffset);
      result.add(TextLine(
        text: lineText,
        height: metric.height,
        isParagraphEnd: i == lineMetrics.length - 1,
      ));
      offset = endOffset;
    }

    return result;
  }

  List<TextPage> _splitIntoPages({
    required List<TextLine> lines,
    required Size pageSize,
    required ReadingSettings settings,
  }) {
    final pages = <TextPage>[];
    final availableHeight = pageSize.height -
        settings.padding.top -
        settings.padding.bottom -
        settings.padding.headerHeight -
        settings.padding.footerHeight;

    var currentPageLines = <TextLine>[];
    var usedHeight = 0.0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineSpacing = line.height * (settings.lineHeight - 1.0);
      final totalLineHeight = line.height + lineSpacing;

      if (usedHeight + totalLineHeight > availableHeight && currentPageLines.isNotEmpty) {
        pages.add(TextPage(lines: List.from(currentPageLines), pageIndex: pages.length));
        currentPageLines = [];
        usedHeight = 0;
      }

      currentPageLines.add(line);
      usedHeight += totalLineHeight;
    }

    if (currentPageLines.isNotEmpty) {
      pages.add(TextPage(lines: currentPageLines, pageIndex: pages.length));
    }

    return pages;
  }

  bool _isTitle(String text) {
    final trimmed = text.trim();
    return RegExp(r'^第[一二三四五六七八九十百千万\d]+[章节回]').hasMatch(trimmed) ||
        RegExp(r'^Chapter\s+\d+', caseSensitive: false).hasMatch(trimmed);
  }

  TextStyle _textStyle(ReadingSettings settings, {bool isTitle = false}) {
    return TextStyle(
      fontSize: isTitle ? settings.fontSize + 2 : settings.fontSize,
      fontWeight: isTitle ? FontWeight.bold : settings.fontWeight,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing,
      color: settings.textColor,
      fontFamily: settings.fontFamily,
    );
  }
}
