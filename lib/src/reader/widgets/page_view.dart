import 'package:flutter/material.dart';
import '../entities/text_page.dart';
import '../entities/column.dart';
import '../../core/models/reading_settings.dart';

class PageView extends StatelessWidget {
  final TextPage? page;
  final ReadingSettings settings;
  final int pageIndex;
  final int totalPages;
  final int chapterIndex;
  final int chapterSize;
  final String? chapterTitle;
  final String? searchQuery;
  final String? bookName;
  final int? batteryLevel;
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
    this.chapterIndex = 0,
    this.chapterSize = 0,
    this.chapterTitle,
    this.searchQuery,
    this.bookName,
    this.batteryLevel,
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

    // 页眉/页脚的显隐只由各自配置的 hidden 决定, 与翻页模式(scroll 或其它)无关,
    // 对齐原生 legado: 翻页模式只改变翻页方式, 不影响 chrome 是否显示。
    final showHeader = settings.hideStatusBar && !settings.headerConfig.hidden;
    final showFooter = !settings.footerConfig.hidden;
    final content = Container(
      decoration: _buildBackground(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          if (showHeader) _buildHeader(context),
          if (showHeader && settings.showHeaderDivider)
            Container(height: 0.5, color: settings.backgroundColor),
          Expanded(child: ClipRect(child: _buildContent())),
          if (showFooter && settings.showFooterDivider)
            Container(height: 0.5, color: Colors.grey.shade300),
          if (showFooter)
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
        if (batteryLevel != null) {
          return Align(
            alignment: alignment,
            child: _BatteryIcon(level: batteryLevel!, color: settings.tipColor),
          );
        }
        text = '';
      case TipPosition.batteryPercent:
        text = batteryLevel != null ? '$batteryLevel%' : '';
      case TipPosition.pageNumber:
        text = '${pageIndex + 1}/$totalPages';
      case TipPosition.progress:
        text = _calcProgress();
      case TipPosition.bookName:
        text = bookName ?? '';
      case TipPosition.timeAndBattery:
        final time =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        if (batteryLevel != null) {
          return Align(
            alignment: alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    color: settings.tipColor,
                    fontFamily: settings.fontFamily,
                  ),
                ),
                const SizedBox(width: 4),
                _BatteryIcon(level: batteryLevel!, color: settings.tipColor, size: 16),
              ],
            ),
          );
        }
        text = time;
      case TipPosition.pageAndTotal:
        text = '${pageIndex + 1}/$totalPages  ${_calcProgress()}';
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

  /// 计算全书阅读进度，与原生 Legado TextPage.readProgress 一致
  String _calcProgress() {
    if (chapterSize == 0 || (totalPages == 0 && chapterIndex == 0)) {
      return '0.0%';
    } else if (totalPages == 0) {
      return '${((chapterIndex + 1) / chapterSize * 100).toStringAsFixed(1)}%';
    }
    final percent = chapterIndex / chapterSize +
        (pageIndex + 1) / totalPages / chapterSize;
    var result = (percent * 100).toStringAsFixed(1);
    if (result == '100.0%' &&
        (chapterIndex + 1 != chapterSize || pageIndex + 1 != totalPages)) {
      result = '99.9';
    }
    return '$result%';
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
    final style = _lineStyle(isTitle);

    // 搜索高亮: 标记匹配的 Column
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      _markSearchResults(line, searchQuery!);
    }

    final lineHeight = line.height;

    // 有 Column 数据: 用 CustomPainter 逐字符绘制
    if (line.hasCharData) {
      return SizedBox(
        height: lineHeight+15,
        child: CustomPaint(
          size: Size(double.infinity, lineHeight),
          painter: _TextLinePainter(
            line: line,
            style: style,
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

  TextStyle _lineStyle(bool isTitle) {
    return TextStyle(
      fontSize: isTitle ? settings.fontSize + 2 : settings.fontSize,
      fontWeight: isTitle ? FontWeight.bold : settings.fontWeight,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing,
      color: settings.textColor,
      fontFamily: settings.fontFamily,
    );
  }

  /// 标记搜索结果: 遍历 Column 列表，将匹配的字符标记为 isSearchResult
  void _markSearchResults(TextLine line, String query) {
    final text = line.text;
    int start = 0;
    while (true) {
      final index = text.indexOf(query, start);
      if (index < 0) break;
      for (var i = index; i < index + query.length && i < line.columns.length; i++) {
        if (line.columns[i] is TextColumn) {
          (line.columns[i] as TextColumn).isSearchResult = true;
        }
      }
      start = index + query.length;
    }
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
/// 遍历 line.columns，对每个 Column 调用 draw()，
/// 每个字符有独立的像素坐标，实现精确的逐字绘制。
class _TextLinePainter extends CustomPainter {
  final TextLine line;
  final TextStyle style;

  _TextLinePainter({
    required this.line,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (line.text.isEmpty) return;
    if (line.columns.isEmpty) return;

    for (final column in line.columns) {
      column.draw(canvas, style, line.lineBase);
    }
  }

  @override
  bool shouldRepaint(_TextLinePainter oldDelegate) {
    return oldDelegate.line != line || oldDelegate.style != style;
  }
}

/// 电池图标 Widget，用 Canvas 绘制原生风格的电池图标
class _BatteryIcon extends StatelessWidget {
  final int level;
  final Color color;
  final double size;

  const _BatteryIcon({
    required this.level,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.6),
      painter: _BatteryPainter(level: level.clamp(0, 100), color: color),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final int level;
  final Color color;

  _BatteryPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color;

    final bodyWidth = size.width * 0.85;
    final bodyHeight = size.height;
    final bodyLeft = 0.0;
    final bodyTop = 0.0;
    final cornerRadius = size.height * 0.15;

    final bodyRect = RRect.fromLTRBR(
      bodyLeft, bodyTop, bodyLeft + bodyWidth, bodyTop + bodyHeight,
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(bodyRect, paint);

    final tipWidth = size.width * 0.1;
    final tipHeight = size.height * 0.4;
    final tipLeft = bodyLeft + bodyWidth;
    final tipTop = (bodyHeight - tipHeight) / 2;
    final tipRect = RRect.fromLTRBR(
      tipLeft, tipTop, tipLeft + tipWidth, tipTop + tipHeight,
      Radius.circular(cornerRadius * 0.5),
    );
    canvas.drawRRect(tipRect, paint);

    final fillPadding = 2.0;
    final fillWidth = (bodyWidth - fillPadding * 2) * level / 100;
    final fillRect = RRect.fromLTRBR(
      bodyLeft + fillPadding,
      bodyTop + fillPadding,
      bodyLeft + fillPadding + fillWidth,
      bodyTop + bodyHeight - fillPadding,
      Radius.circular(cornerRadius * 0.5),
    );
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = level <= 20 ? color.withValues(alpha: 0.5) : color;
    canvas.drawRRect(fillRect, fillPaint);
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}
