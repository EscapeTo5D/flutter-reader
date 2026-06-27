import 'package:flutter/material.dart';
import '../entities/text_page.dart';
import '../entities/column.dart';
import '../../core/models/reading_settings.dart';

class PageEngine {
  List<TextPage> paginate({
    required String content,
    required Size pageSize,
    required ReadingSettings settings,
  }) {
    if (content.isEmpty) return [];

    final paragraphs = content.split('\n');
    final lines = <TextLine>[];
    var titleAdded = false;
    // 上一行文字的纯字体度量, 用于段距计算(段距行无文字, 借用邻近文字行 textHeight)。
    // 对齐原生: 段距 = textHeight * paragraphSpacing / 10。
    var lastTextHeight = settings.fontSize; // 初始用字号近似(无前文时)

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      if (para.trim().isEmpty) {
        final spacing = lastTextHeight * settings.paragraphSpacing / 10.0;
        lines.add(TextLine(
          text: '',
          height: spacing,
          textHeight: lastTextHeight,
          isParagraphEnd: true,
        ));
        continue;
      }
      final isTitle = _isTitle(para) && i == 0; // 只有首段可能是标题

      // titleMode == 2 时隐藏标题
      if (isTitle && settings.titleMode == 2) continue;

      final style = _textStyle(settings, isTitle: isTitle);
      final maxWidth =
          pageSize.width - settings.padding.left - settings.padding.right;

      // 标题上方间距
      if (isTitle && !titleAdded) {
        lines.add(TextLine(
          text: '',
          height: settings.titleTopSpacing,
          isParagraphEnd: false,
        ));
        titleAdded = true;
      }

      final textLines = _wrapText(
        text: para,
        style: style,
        maxWidth: maxWidth,
        indent: isTitle ? 0 : settings.textIndent,
        letterSpacing: settings.letterSpacing,
        fontSize: isTitle
            ? settings.fontSize + settings.titleSize
            : settings.fontSize,
        isTitle: isTitle,
        isMiddleTitle: settings.isMiddleTitle || settings.titleMode == 1,
        textFullJustify: settings.textFullJustify,
      );
      lines.addAll(textLines);
      // 更新纯字体度量, 供后续段距行借用
      if (textLines.isNotEmpty) {
        lastTextHeight = textLines.last.textHeight;
      }

      // 段后间距: 对齐原生 TextChapterLayout.kt:1026
      // `durY += textHeight * paragraphSpacing / 10f`, 在每个正文段落末尾追加。
      // 标题段有独立的 titleBottomSpacing, 不走这里。
      if (!isTitle) {
        final spacing = lastTextHeight * settings.paragraphSpacing / 10.0;
        lines.add(TextLine(
          text: '',
          height: spacing,
          textHeight: lastTextHeight,
          isParagraphEnd: true,
        ));
      }

      // 标题下方间距
      if (isTitle) {
        lines.add(TextLine(
          text: '',
          height: settings.titleBottomSpacing,
          isParagraphEnd: false,
        ));
      }
    }

    return _splitIntoPages(
      lines: lines,
      pageSize: pageSize,
      settings: settings,
    );
  }

  /// 核心换行逻辑: 逐字符测量 + 生成 Column 对象
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
    // 对齐原生 legado: 缩进是"替换"而非"叠加"。源文本段落通常自带全角/半角空格
    // 缩进, 先剥离首部空白字符, 再用标准缩进(indent 个全角空格)统一填充, 避免双重缩进。
    // 原生 addCharsToLineFirst 用 words.subList(bodyIndent.length, ...) 跳过源文本前 N 字符。
    final body = indent > 0 ? text.replaceFirst(RegExp(r'^[\s\u3000]+'), '') : text;
    final indentStr = indent > 0 ? '\u3000' * indent : '';
    final displayText = '$indentStr$body';

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

      // 标题居中: 对齐原生 addCharsToLineNatural 的
      // startX = (visibleWidth - desiredWidth) / 2。仅 isMiddleTitle 开启时居中
      // (原生还含 emptyContent/isVolumeTitle/imgStyleSingle, Flutter 暂不建模这些)。
      // 标题行不缩进、不两端对齐, naturalWidth 即 desiredWidth。
      final double centerOffset;
      if (isTitle && isMiddleTitle) {
        final naturalWidth = charWidths.fold(0.0, (a, b) => a + b);
        centerOffset = ((maxWidth - naturalWidth) / 2).clamp(0.0, double.infinity);
      } else {
        centerOffset = 0.0;
      }

      // 生成 Column 列表(含两端对齐的坐标计算)
      final columns = _buildColumns(
        lineText: lineText,
        charWidths: charWidths,
        indentSize: indentSize,
        indentWidth: indentWidth,
        maxWidth: maxWidth,
        shouldJustify: shouldJustify,
        startOffset: centerOffset,
      );

      result.add(TextLine(
        text: lineText,
        height: metric.height,
        textHeight: metric.height / (style.height ?? 1.0),
        isParagraphEnd: isLastLine,
        isTitle: isTitle,
        columns: columns,
        indentWidth: indentWidth,
        indentSize: indentSize,
        lineBase: metric.baseline,
        lineBottom: metric.height,
      ));
      offset = endOffset;
    }

    return result;
  }

  /// 生成 Column 列表，计算每个字符的绝对 start/end 坐标
  ///
  /// 对应原生 Android 的 addCharsToLineFirst / addCharsToLineMiddle / addCharsToLineNatural
  List<TextColumn> _buildColumns({
    required String lineText,
    required List<double> charWidths,
    required int indentSize,
    required double indentWidth,
    required double maxWidth,
    required bool shouldJustify,
    double startOffset = 0.0,
  }) {
    final columns = <TextColumn>[];
    if (lineText.isEmpty) return columns;

    // 计算自然排列时的总宽度
    final naturalWidth = charWidths.fold(0.0, (a, b) => a + b);

    // 两端对齐: 计算需要分配的额外间距
    double perCharExtra = 0.0; // 每个字符间隙的额外间距
    double perWordExtra = 0.0; // 每个空格的额外间距
    if (shouldJustify && charWidths.isNotEmpty) {
      final residualWidth = maxWidth - naturalWidth;
      if (residualWidth > 0) {
        final spaceCount = ' '.allMatches(lineText).length;
        final gapCount = lineText.length - 1 - indentSize;

        if (spaceCount > 1) {
          // 英文: 额外间距分配到空格上
          perWordExtra = residualWidth / spaceCount;
        } else if (gapCount > 0) {
          // 中文: 额外间距分配到字符间隙上
          perCharExtra = residualWidth / gapCount;
        }
      }
    }

    // 遍历字符，计算每个 Column 的 start/end 坐标
    // 居中标题(startOffset>0): 对齐原生 addCharsToLineNatural
    // startX = (visibleWidth - desiredWidth) / 2, 整行右移 startOffset。
    double x = startOffset;
    for (var i = 0; i < lineText.length; i++) {
      final charStart = x;
      final charWidth = charWidths[i];
      final charEnd = charStart + charWidth;

      columns.add(TextColumn(
        charData: lineText[i],
        start: charStart,
        end: charEnd,
      ));

      // 推进 x 坐标: 字符宽度 + 基础字间距 + 两端对齐额外间距
      x = charEnd;
      if (i < lineText.length - 1) {
        // 两端对齐间距只施加到「正文字符之间」的间隙, 跳过缩进字符
        // (i < indentSize 的间隙), 对齐原生 legado addCharsToLineFirst:
        // 缩进字符用固定 indentCharWidth 排列, 不参与两端对齐; 仅对
        // 缩进之后的字符子列调 addCharsToLineMiddle 分配 residualWidth。
        // 否则 perCharExtra 会被多施加 indentSize 个间隙, 末列 end 超出
        // maxWidth, 缩进行的末字被裁。
        if (i >= indentSize) {
          x += perCharExtra;
          // 如果当前字符是空格，添加词间距
          if (lineText[i] == ' ') {
            x += perWordExtra;
          }
        }
      }
    }

    return columns;
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
      final totalLineHeight = line.height;

      if (usedHeight + totalLineHeight > availableHeight &&
          currentPageLines.isNotEmpty) {
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
  void _applyBottomJustify(
    List<TextLine> lines,
    double availableHeight,
    double usedHeight,
    ReadingSettings settings,
  ) {
    if (!settings.textBottomJustify) return;
    if (lines.length <= 1) return;

    final textLineCount = lines.where((l) => !l.isEmptyParagraph).length;
    if (textLineCount <= 1) return;

    final surplus = availableHeight - usedHeight;
    if (surplus <= 0 || surplus >= lines.first.height) return;

    final tj = surplus / (textLineCount - 1);
    var yOffset = 0.0;
    var textLineIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmptyParagraph) continue;

      if (textLineIndex > 0) {
        yOffset = tj * textLineIndex;
      }
      textLineIndex++;

      lines[i] = TextLine(
        text: line.text,
        isTitle: line.isTitle,
        isParagraphEnd: line.isParagraphEnd,
        height: line.height,
        textHeight: line.textHeight,
        columns: line.columns,
        indentWidth: line.indentWidth,
        indentSize: line.indentSize,
        lineTop: yOffset,
        lineBase: line.lineBase,
        lineBottom: line.lineBottom,
        paragraphNum: line.paragraphNum,
        chapterPosition: line.chapterPosition,
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
