import 'package:flutter/material.dart';
import '../models/text_page.dart';
import '../models/reading_settings.dart';

class PageView extends StatelessWidget {
  final TextPage? page;
  final ReadingSettings settings;
  final int pageIndex;
  final int totalPages;
  final String? chapterTitle;
  final String? searchQuery;
  final String? bookName;
  final bool useSafeArea;
  final bool showChrome;
  final bool showFooterOnly;
  final bool showHeaderOnly;

  const PageView({
    super.key,
    this.page,
    required this.settings,
    required this.pageIndex,
    required this.totalPages,
    this.chapterTitle,
    this.searchQuery,
    this.bookName,
    this.useSafeArea = true,
    this.showChrome = true,
    this.showFooterOnly = false,
    this.showHeaderOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showHeaderOnly || showFooterOnly) {
      return _buildChromeOnly(context);
    }

    final showHeader = settings.hideStatusBar && showChrome;
    final content = Container(
      decoration: _buildBackground(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          if (showHeader) _buildHeader(context),
          if (showHeader && settings.showHeaderDivider)
            Container(height: 0.5, color: settings.backgroundColor),
          Expanded(child: ClipRect(child: _buildContent())),
          if (showChrome && settings.showFooterDivider)
            Container(height: 0.5, color: Colors.grey.shade300),
          if (showChrome)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: _buildFooter(context),
            ),
        ],
      ),
    );

    if (!useSafeArea) return content;
    return SafeArea(
      top: !settings.hideStatusBar,
      bottom: !settings.hideNavigationBar,
      child: content,
    );
  }

  Widget _buildChromeOnly(BuildContext context) {
    final cfg = showHeaderOnly ? settings.headerConfig : settings.footerConfig;
    final vertPadding = showHeaderOnly
        ? EdgeInsets.only(
            left: settings.padding.left, right: settings.padding.right)
        : EdgeInsets.only(
            left: settings.padding.left,
            right: settings.padding.right,
            top: 2,
            bottom: 6);
    return Padding(
      padding: vertPadding,
      child: Row(
        children: [
          Expanded(child: _buildTip(cfg.left, context, Alignment.centerLeft)),
          Expanded(child: _buildTip(cfg.center, context, Alignment.center)),
          Expanded(child: _buildTip(cfg.right, context, Alignment.centerRight)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: settings.padding.headerHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: settings.padding.left,
          right: settings.padding.right,
        ),
        child: Row(
          children: [
            Expanded(
                child: _buildTip(
                    settings.headerConfig.left, context, Alignment.centerLeft)),
            Expanded(
                child: _buildTip(settings.headerConfig.center, context,
                    Alignment.center)),
            Expanded(
                child: _buildTip(settings.headerConfig.right, context,
                    Alignment.centerRight)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: settings.padding.left,
        right: settings.padding.right,
        top: 2,
        bottom: 6,
      ),
      child: Row(
        children: [
          Expanded(
              child: _buildTip(
                  settings.footerConfig.left, context, Alignment.centerLeft)),
          Expanded(
              child: _buildTip(
                  settings.footerConfig.center, context, Alignment.center)),
          Expanded(
              child: _buildTip(
                  settings.footerConfig.right, context, Alignment.centerRight)),
        ],
      ),
    );
  }

  Widget _buildTip(
      TipPosition position, BuildContext context, Alignment alignment) {
    final now = DateTime.now();
    String text;
    switch (position) {
      case TipPosition.none:
        return const SizedBox();
      case TipPosition.chapterTitle:
        text = chapterTitle ?? '';
      case TipPosition.time:
        text =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      case TipPosition.battery:
        text = '';
      case TipPosition.batteryPercent:
        text = '';
      case TipPosition.pageNumber:
        text = '${pageIndex + 1}/$totalPages';
      case TipPosition.progress:
        final percent =
            totalPages > 0 ? ((pageIndex + 1) / totalPages * 100).toInt() : 0;
        text = '$percent%';
      case TipPosition.bookName:
        text = bookName ?? '';
      case TipPosition.timeAndBattery:
        text =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      case TipPosition.pageAndTotal:
        final percent =
            totalPages > 0 ? ((pageIndex + 1) / totalPages * 100).toInt() : 0;
        text = '${pageIndex + 1}/$totalPages $percent%';
    }
    return Align(
      alignment: alignment,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: settings.tipColor,
          fontFamily: settings.fontFamily,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildContent() {
    if (page == null || page!.isEmpty) {
      return const Center(child: Text(''));
    }

    return Padding(
      padding: EdgeInsets.only(
        left: settings.padding.left,
        right: settings.padding.right,
        top: settings.padding.top,
        bottom: settings.padding.bottom,
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        child: _buildLines(),
      ),
    );
  }

  /// 构建所有行, 处理底部对齐的额外间距
  Widget _buildLines() {
    final lines = page!.lines;
    final children = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 底部对齐: 在行前插入额外间距
      if (i > 0 && line.lineTop > 0) {
        final prevLineTop = lines[i - 1].lineTop;
        final extraSpacing = line.lineTop - prevLineTop;
        if (extraSpacing > 0) {
          children.add(SizedBox(height: extraSpacing));
        }
      }

      children.add(_buildLine(line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildLine(TextLine line) {
    // 空段落行: 只显示段间距
    if (line.isEmptyParagraph) {
      return SizedBox(height: settings.paragraphSpacing);
    }

    final isTitle = line.isTitle;
    final style = TextStyle(
      fontSize: isTitle ? settings.fontSize + 2 : settings.fontSize,
      fontWeight: isTitle ? FontWeight.bold : settings.fontWeight,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing,
      color: settings.textColor,
      fontFamily: settings.fontFamily,
    );

    // 搜索高亮行: 用 RichText 实现(保持兼容)
    if (searchQuery != null &&
        searchQuery!.isNotEmpty &&
        line.text.contains(searchQuery!)) {
      return _buildHighlightedLine(line.text, style);
    }

    final lineHeight = line.height * settings.lineHeight;

    // 有字符级排版数据: 用 CustomPainter 逐字符绘制
    if (line.hasCharData) {
      return SizedBox(
        height: lineHeight,
        child: CustomPaint(
          size: Size(double.infinity, lineHeight),
          painter: _TextLinePainter(
            line: line,
            style: style,
            fontSize: isTitle ? settings.fontSize + 2 : settings.fontSize,
          ),
        ),
      );
    }

    // 降级: 用 Text Widget
    return SizedBox(
      height: lineHeight,
      child: Text(line.text, style: style),
    );
  }

  Widget _buildHighlightedLine(String text, TextStyle style) {
    final spans = <TextSpan>[];
    int start = 0;
    final query = searchQuery!;
    while (true) {
      final index = text.indexOf(query, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: query,
        style: const TextStyle(backgroundColor: Colors.yellow),
      ));
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }

  BoxDecoration _buildBackground() {
    if (settings.backgroundImage != null &&
        settings.backgroundImage!.isNotEmpty) {
      return BoxDecoration(
        image: DecorationImage(
          image: AssetImage(settings.backgroundImage!,
              package: 'flutter_reader'),
          fit: BoxFit.cover,
        ),
      );
    }
    return BoxDecoration(color: settings.backgroundColor);
  }
}

/// 逐字符绘制 TextLine 的 CustomPainter
///
/// 支持:
/// - 两端对齐(中文字符间隙均匀分布 / 英文空格间距分布)
/// - 首行缩进
/// - 自然排列(末行、标题)
class _TextLinePainter extends CustomPainter {
  final TextLine line;
  final TextStyle style;
  final double fontSize;

  _TextLinePainter({
    required this.line,
    required this.style,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (line.text.isEmpty) return;

    final hasIndent = line.indentSize > 0;

    if (hasIndent) {
      // 分两段绘制: 缩进部分 + 剩余部分
      _drawIndentPart(canvas);
      _drawRemainingPart(canvas, line.indentWidth);
    } else {
      // 整行绘制
      _drawRemainingPart(canvas, 0);
    }
  }

  /// 绘制缩进部分(全角空格, 自然间距)
  void _drawIndentPart(Canvas canvas) {
    final indentText = line.text.substring(0, line.indentSize);
    final painter = TextPainter(
      text: TextSpan(text: indentText, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset.zero);
  }

  /// 绘制剩余部分(可能带两端对齐)
  void _drawRemainingPart(Canvas canvas, double startX) {
    final remainingText = line.text.substring(line.indentSize);
    if (remainingText.isEmpty) return;

    TextStyle drawStyle;
    if (line.isJustified) {
      // 两端对齐: 添加额外字间距
      drawStyle = style.copyWith(
        letterSpacing: (style.letterSpacing ?? 0) + line.extraLetterSpacing,
        wordSpacing: line.wordSpacing > 0 ? line.wordSpacing : null,
      );
    } else {
      drawStyle = style;
    }

    final painter = TextPainter(
      text: TextSpan(text: remainingText, style: drawStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset(startX, 0));
  }

  @override
  bool shouldRepaint(_TextLinePainter oldDelegate) {
    return oldDelegate.line != line || oldDelegate.style != style;
  }
}
