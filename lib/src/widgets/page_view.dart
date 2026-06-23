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
          if (showChrome) _buildFooter(context),
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
        ? EdgeInsets.only(left: settings.padding.left, right: settings.padding.right)
        : EdgeInsets.only(left: settings.padding.left, right: settings.padding.right, top: 6, bottom: 6);
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
            Expanded(child: _buildTip(settings.headerConfig.left, context, Alignment.centerLeft)),
            Expanded(child: _buildTip(settings.headerConfig.center, context, Alignment.center)),
            Expanded(child: _buildTip(settings.headerConfig.right, context, Alignment.centerRight)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return SizedBox(
      height: settings.padding.footerHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: settings.padding.left,
          right: settings.padding.right,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            Expanded(child: _buildTip(settings.footerConfig.left, context, Alignment.centerLeft)),
            Expanded(child: _buildTip(settings.footerConfig.center, context, Alignment.center)),
            Expanded(child: _buildTip(settings.footerConfig.right, context, Alignment.centerRight)),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(TipPosition position, BuildContext context, Alignment alignment) {
    final now = DateTime.now();
    String text;
    switch (position) {
      case TipPosition.none:
        return const SizedBox();
      case TipPosition.chapterTitle:
        text = chapterTitle ?? '';
      case TipPosition.time:
        text = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      case TipPosition.battery:
        text = '';
      case TipPosition.batteryPercent:
        text = '';
      case TipPosition.pageNumber:
        text = '${pageIndex + 1}/$totalPages';
      case TipPosition.progress:
        final percent = totalPages > 0 ? ((pageIndex + 1) / totalPages * 100).toInt() : 0;
        text = '$percent%';
      case TipPosition.bookName:
        text = bookName ?? '';
      case TipPosition.timeAndBattery:
        text = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      case TipPosition.pageAndTotal:
        final percent = totalPages > 0 ? ((pageIndex + 1) / totalPages * 100).toInt() : 0;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: page!.lines.map((line) => _buildLine(line)).toList(),
      ),
    );
  }

  Widget _buildLine(TextLine line) {
    if (line.text.isEmpty && line.isParagraphEnd) {
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

    if (searchQuery != null && searchQuery!.isNotEmpty && line.text.contains(searchQuery!)) {
      return _buildHighlightedLine(line.text, style);
    }

    return SizedBox(
      height: line.height * settings.lineHeight,
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
    if (settings.backgroundImage != null && settings.backgroundImage!.isNotEmpty) {
      return BoxDecoration(
        image: DecorationImage(
          image: AssetImage(settings.backgroundImage!, package: 'flutter_reader'),
          fit: BoxFit.cover,
        ),
      );
    }
    return BoxDecoration(color: settings.backgroundColor);
  }
}
