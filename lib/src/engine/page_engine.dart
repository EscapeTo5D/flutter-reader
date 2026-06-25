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
        lines.add(TextLine(
          text: '',
          height: settings.paragraphSpacing,
          isParagraphEnd: true,
        ));
        continue;
      }
      final isTitle = _isTitle(para);
      final style = _textStyle(settings, isTitle: isTitle);
      final maxWidth =
          pageSize.width - settings.padding.left - settings.padding.right;
      final textLines = _wrapText(
        text: para,
        style: style,
        maxWidth: maxWidth,
        indent: isTitle ? 0 : settings.textIndent,
        letterSpacing: settings.letterSpacing,
        fontSize: isTitle ? settings.fontSize + 2 : settings.fontSize,
        isTitle: isTitle,
        isMiddleTitle: false, // TODO: 从配置读取
        textFullJustify: settings.textFullJustify,
      );
      lines.addAll(textLines);
    }

    return _splitIntoPages(
      lines: lines,
      pageSize: pageSize,
      settings: settings,
    );
  }

  /// 核心换行逻辑: 逐字符测量 + 两端对齐计算
  List<TextLine> _wrapText({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int indent,
    required double letterSpacing,
    required double fontSize,
    required bool isTitle,
    required bool isMiddleTitle,
    required bool textFullJustify,
  }) {
    final result = <TextLine>[];
    final indentStr = indent > 0 ? '\u3000' * indent : '';
    final displayText = '$indentStr$text';

    // 用 TextPainter 排版整段
    final painter = TextPainter(
      text: TextSpan(text: displayText, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    painter.layout(maxWidth: maxWidth);

    final lineMetrics = painter.computeLineMetrics();
    if (lineMetrics.isEmpty) {
      result.add(TextLine(
        text: displayText,
        height: style.fontSize! * (style.height ?? 1.5),
      ));
      return result;
    }

    // 逐行切分
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
      final isLastLine = i == lineMetrics.length - 1;
      final isMultiLine = lineMetrics.length > 1;
      final isFirstLine = i == 0;

      // 判断行类型
      final bool shouldJustify;
      if (isTitle) {
        shouldJustify = false; // 标题不两端对齐
      } else if (!isMultiLine) {
        shouldJustify = false; // 单行段落不两端对齐
      } else if (isLastLine) {
        shouldJustify = false; // 末行不两端对齐
      } else {
        shouldJustify = textFullJustify; // 中间行: 按配置决定
      }

      // 测量每个字符的宽度
      final charWidths = _measureCharWidths(lineText, style);

      // 计算缩进宽度
      final double indentWidth;
      final int indentSize;
      if (isFirstLine && indent > 0) {
        indentWidth = charWidths.take(indent).fold(0.0, (a, b) => a + b);
        indentSize = indent;
      } else {
        indentWidth = 0.0;
        indentSize = 0;
      }

      // 计算两端对齐参数
      double extraLetterSpacing = 0.0;
      double wordSpacing = 0.0;
      if (shouldJustify && charWidths.isNotEmpty) {
        final naturalWidth = charWidths.fold(0.0, (a, b) => a + b);
        final residualWidth = maxWidth - naturalWidth;

        if (residualWidth > 0) {
          // 统计空格数量
          final spaceCount = ' '.allMatches(lineText).length;
          // 排除缩进后的字符间隙数
          final gapCount = lineText.length - 1 - indentSize;

          if (spaceCount > 1) {
            // 策略A: 有多个空格 → 分配到空格上
            wordSpacing = residualWidth / spaceCount;
          } else if (gapCount > 0) {
            // 策略B: 无空格(中文) → 分配到字符间隙上
            extraLetterSpacing = residualWidth / gapCount;
          }
        }
      }

      result.add(TextLine(
        text: lineText,
        height: metric.height,
        isParagraphEnd: isLastLine,
        isTitle: isTitle,
        charWidths: charWidths,
        indentWidth: indentWidth,
        indentSize: indentSize,
        extraLetterSpacing: extraLetterSpacing,
        wordSpacing: wordSpacing,
        isJustified: shouldJustify,
      ));
      offset = endOffset;
    }

    return result;
  }

  /// 测量每个字符的宽度
  List<double> _measureCharWidths(String text, TextStyle style) {
    if (text.isEmpty) return [];
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    final widths = <double>[];
    for (var i = 0; i < text.length; i++) {
      final startOffset = painter.getOffsetForCaret(
        TextPosition(offset: i),
        Rect.zero,
      );
      final endOffset = painter.getOffsetForCaret(
        TextPosition(offset: i + 1),
        Rect.zero,
      );
      widths.add((endOffset.dx - startOffset.dx).abs());
    }
    return widths;
  }

  /// 分页 + 底部对齐
  List<TextPage> _splitIntoPages({
    required List<TextLine> lines,
    required Size pageSize,
    required ReadingSettings settings,
  }) {
    final pages = <TextPage>[];
    final availableHeight =
        pageSize.height - settings.padding.top - settings.padding.bottom;

    var currentPageLines = <TextLine>[];
    var usedHeight = 0.0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineSpacing = line.height * (settings.lineHeight - 1.0);
      final totalLineHeight = line.height + lineSpacing;

      if (usedHeight + totalLineHeight > availableHeight &&
          currentPageLines.isNotEmpty) {
        // 当前页已满, 应用底部对齐后保存
        _applyBottomJustify(
          currentPageLines,
          availableHeight,
          usedHeight,
          settings,
        );
        pages.add(TextPage(
          lines: List.from(currentPageLines),
          pageIndex: pages.length,
        ));
        currentPageLines = [];
        usedHeight = 0;
      }

      currentPageLines.add(line);
      usedHeight += totalLineHeight;
    }

    if (currentPageLines.isNotEmpty) {
      _applyBottomJustify(
        currentPageLines,
        availableHeight,
        usedHeight,
        settings,
      );
      pages.add(TextPage(
        lines: currentPageLines,
        pageIndex: pages.length,
      ));
    }

    return pages;
  }

  /// 底部对齐: 将剩余空间均匀分配到各行之间
  ///
  /// 对应 Android 版 TextPage.upLinesPosition()
  void _applyBottomJustify(
    List<TextLine> lines,
    double availableHeight,
    double usedHeight,
    ReadingSettings settings,
  ) {
    if (!settings.textBottomJustify) return;
    if (lines.length <= 1) return;

    // 跳过空段落行(只统计实际文本行)
    final textLineCount = lines.where((l) => !l.isEmptyParagraph).length;
    if (textLineCount <= 1) return;

    final surplus = availableHeight - usedHeight;
    // 如果剩余空间超过一行高度, 说明是页面内容太少, 不做底部对齐
    if (surplus <= 0 || surplus >= lines.first.height) return;

    // 均匀分配剩余空间
    final tj = surplus / (textLineCount - 1);
    var yOffset = 0.0;
    var textLineIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmptyParagraph) {
        // 空段落行不参与偏移计算
        continue;
      }

      if (textLineIndex > 0) {
        yOffset = tj * textLineIndex;
      }
      textLineIndex++;

      // 创建新的 TextLine 带上 lineTop
      lines[i] = TextLine(
        text: line.text,
        isTitle: line.isTitle,
        isParagraphEnd: line.isParagraphEnd,
        height: line.height,
        charWidths: line.charWidths,
        indentWidth: line.indentWidth,
        indentSize: line.indentSize,
        extraLetterSpacing: line.extraLetterSpacing,
        wordSpacing: line.wordSpacing,
        isJustified: line.isJustified,
        lineTop: yOffset,
      );
    }
  }

  bool _isTitle(String text) {
    final trimmed = text.trim();
    return RegExp(r'^第[一二三四五六七八九十百千万\d]+[章节回]')
            .hasMatch(trimmed) ||
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
