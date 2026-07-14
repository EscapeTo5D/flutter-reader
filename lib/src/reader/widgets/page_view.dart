import 'package:flutter/material.dart';
import '../entities/text_page.dart';
import '../entities/column.dart';
import '../../core/models/reading_settings.dart';
import '../../aloud/aloud_controller.dart';
import 'tip_layout.dart'; // 渲染尺寸常量(与测量函数同源)

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

  /// 朗读控制器(可选)。非 null 时, 当前朗读段会被高亮(对应原生 aloudSpan)。
  final AloudController? aloudController;

  /// 朗读高亮版本号。每次朗读进度推进自增, 驱动 [shouldRepaint] 重绘。
  final int aloudVersion;

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
    this.aloudController,
    this.aloudVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (showHeaderOnly || showFooterOnly) {
      return _buildChromeOnly(context);
    }

    // 纯正文模式(scroll 滚动模式专用): 不画页眉/页脚/分隔线/SafeArea, 仅渲染
    // 正文行。chrome 由 reader_view 的外层浮层固定在视口, 不随滚动
    // (对齐原生: chrome 在 PageView 父布局, 正文在 ContentTextView 偏移)。
    if (!showChrome) {
      return DecoratedBox(
        decoration: _buildBackground(),
        child: ClipRect(child: _buildContent()),
      );
    }

    // 页眉/页脚的显隐只由各自配置的 hidden 决定, 与翻页模式(scroll 或其它)无关,
    // 对齐原生 legado: 翻页模式只改变翻页方式, 不影响 chrome 是否显示。
    final showHeader = settings.hideStatusBar && !settings.headerConfig.hidden;
    final showFooter = !settings.footerConfig.hidden;
    // 背景(底色/背景图)提到 SafeArea 外层, 覆盖整页(含状态栏/导航栏区域),
    // 对齐原生 legado: 根 ConstraintLayout 带 android:background, 整页统一背景色,
    // 避免状态栏区域出现 Scaffold 主题色与页眉背景色不一致的色差。
    final body = Column(
      children: [
        if (showHeader) _buildHeader(context),
        if (showHeader && settings.showHeaderDivider) _buildDivider(),
        Expanded(child: ClipRect(child: _buildContent())),
        if (showFooter && settings.showFooterDivider) _buildDivider(),
        if (showFooter) _buildFooter(context),
      ],
    );

    final content = useSafeArea
        ? SafeArea(
            top: !settings.hideStatusBar,
            bottom: !settings.hideNavigationBar,
            child: body,
          )
        : body;

    return DecoratedBox(
      decoration: _buildBackground(),
      child: content,
    );
  }

  Widget _buildChromeOnly(BuildContext context) {
    final cfg = showHeaderOnly ? settings.headerConfig : settings.footerConfig;
    // chrome-only 路径用对应(header/footer)的外层四向 padding, 与 _buildHeader/Footer 一致。
    final p = settings.padding;
    final vertPadding = showHeaderOnly
        ? EdgeInsets.only(
            left: p.headerLeft,
            right: p.headerRight,
            top: p.headerTop,
            bottom: p.headerBottom,
          )
        : EdgeInsets.only(
            left: p.footerLeft,
            right: p.footerRight,
            top: p.footerTop,
            bottom: p.footerBottom,
          );
    final chrome = Padding(
      padding: vertPadding,
      child: Row(
        children: [
          Expanded(child: _buildTip(cfg.left, context, Alignment.centerLeft)),
          Expanded(child: _buildTip(cfg.center, context, Alignment.center)),
          Expanded(child: _buildTip(cfg.right, context, Alignment.centerRight)),
        ],
      ),
    );
    // 分隔线对齐原生 view_book_page.xml: header 分隔线 vw_top_divider 在页眉
    // 【下方】, footer 分隔线 vw_bottom_divider 在页脚【上方】。chrome-only 路径
    // (scroll 模式浮层)此前漏画分隔线, 这里补齐, 让 scroll 模式与普通翻页一致。
    // 颜色与 build() 里一致(对齐原生 @color/divider = #66666666), 渲染消费
    // tipDividerColor 留待后续统一接通。
    if (showHeaderOnly && settings.showHeaderDivider) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [chrome, _buildDivider()],
      );
    }
    if (showFooterOnly && settings.showFooterDivider) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildDivider(), chrome],
      );
    }
    return chrome;
  }

  /// 分隔线: 0.5px 高, 对齐原生 @color/divider = #66666666(alpha 0x66≈40% 半透明灰)。
  /// 被 build()(普通翻页)和 _buildChromeOnly()(scroll 模式浮层)复用。
  Widget _buildDivider() => Container(height: 0.5, color: const Color(0x66666666));

  Widget _buildHeader(BuildContext context) {
    return Padding(
      // 页眉外层四向内边距(对齐原生 headerPaddingTop/Bottom/Left/Right)。
      padding: EdgeInsets.only(
        left: settings.padding.headerLeft,
        right: settings.padding.headerRight,
        top: settings.padding.headerTop,
        bottom: settings.padding.headerBottom,
      ),
      child: SizedBox(
        height: settings.padding.headerHeight,
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
      // 页脚外层四向内边距(对齐原生 footerPaddingTop/Bottom/Left/Right)。
      padding: EdgeInsets.only(
        left: settings.padding.footerLeft,
        right: settings.padding.footerRight,
        top: settings.padding.footerTop,
        bottom: settings.padding.footerBottom,
      ),
      // 内容行高由 Row 按 tip 内容自适应(对齐原生 wrap_content); 预算侧
      // (reader_view.nonContentHeight)用 measureChromeContentHeight 同函数
      // 测得相同高度, 保证不错位。详见 tip_layout.dart。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            child: _BatteryIcon(
                level: batteryLevel!,
                color: settings.tipColor,
                size: kBatteryIconSize),
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
                    fontSize: kTipTimeBatteryTextSize,
                    color: settings.tipColor,
                    fontFamily: settings.fontFamily,
                  ),
                ),
                const SizedBox(width: 4),
                _BatteryIcon(
                    level: batteryLevel!,
                    color: settings.tipColor,
                    size: kTimeBatteryIconSize),
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
          fontSize: kTipTextSize,
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

    // 正文只保留左右页边距; 上下贴分隔线(首行贴上分隔线、末行贴下分隔线)。
    // 引擎排版时 availableHeight 已 = pageSize.height(不减 padding.top/bottom),
    // 故此处不再加 top/bottom padding —— 否则正文会溢出被裁。所有翻页模式
    // 统一此行为, 切换模式无位移(详见 page_engine._splitIntoPages 注释)。
    return Padding(
      padding: EdgeInsets.only(
        left: settings.padding.left,
        right: settings.padding.right,
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

    // prevLineTop 必须取上一个【文字行】的 lineTop, 而非 lines[i-1]。
    // 因为 _applyBottomJustify 只给文字行设 lineTop, 段距行(空段落)的 lineTop=0。
    // 若用段距行的 0 做 prev, 会让紧随其后的文字行 extraSpacing 被错误放大,
    // 渲染总高溢出 availableHeight, 末行被 Clip.hardEdge 裁掉。
    double prevLineTop = 0.0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 底部对齐: 在行前插入额外间距
      if (line.lineTop > 0) {
        final extraSpacing = line.lineTop - prevLineTop;
        if (extraSpacing > 0) {
          children.add(SizedBox(height: extraSpacing));
        }
        prevLineTop = line.lineTop;
      }

      children.add(_buildLine(line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildLine(TextLine line) {
    // 空段落行: 高度即段距(排版引擎已算为 textHeight * paragraphSpacing / 10)
    if (line.isEmptyParagraph) {
      return SizedBox(height: line.height);
    }

    final isTitle = line.isTitle;
    final style = _lineStyle(isTitle);

    // 搜索高亮: 标记匹配的 Column
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      _markSearchResults(line, searchQuery!);
    }

    // 朗读高亮: 标记当前朗读段落在本行的字符区间。
    // 每次构建先清后标(isAloud 是 mutable 字段, 上次构建的标记会残留)。
    _resetAloudMarks(line);
    if (aloudController != null) {
      _markAloud(line, aloudController!);
    }

    final lineHeight = line.height;

    // 有 Column 数据: 用 CustomPainter 逐字符绘制
    // 行高必须与排版引擎预算(line.height = metric.height)一致, 否则逐行累积的
    // 差值会把最后一行挤出 availableHeight, 被 ClipRect 裁掉。
    if (line.hasCharData) {
      return SizedBox(
        height: lineHeight,
        child: CustomPaint(
          size: Size(double.infinity, lineHeight),
          painter: _TextLinePainter(
            line: line,
            style: style,
            aloudVersion: aloudVersion,
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

  /// 清除本行所有 Column 的朗读高亮标记(每次构建先清, 避免上次标记残留)。
  void _resetAloudMarks(TextLine line) {
    for (final col in line.columns) {
      if (col is TextColumn) col.isAloud = false;
    }
  }

  /// 标记当前朗读段在本行的字符区间。
  ///
  /// 朗读光标 [AloudCursor] 的 [chapterCharOffset] 是章内绝对偏移,
  /// [charOffsetInParagraph] 是段内已读偏移。本行的字符区间是
  /// [line.chapterPosition, line.chapterPosition + line.text.length)。
  ///
  /// 高亮规则: 高亮 [segStart, chapterCharOffset), 即段首到当前朗读位置
  /// (已读部分)。与原生 `upPageAloudSpan` 高亮整段的差异是已知简化 —— 段尾
  /// 无法从 cursor 直接得(需查下一段偏移), 已读部分高亮更直观地反映进度。
  void _markAloud(TextLine line, AloudController controller) {
    final cursor = controller.cursor;
    if (cursor == null) return;
    // 朗读段在章内的绝对范围 [segStart, segEnd): 段首 → 当前已读位置。
    final segStart = cursor.chapterCharOffset - cursor.charOffsetInParagraph;
    final segEnd = cursor.chapterCharOffset;
    final lineStart = line.chapterPosition;
    final lineEnd = lineStart + line.text.length;
    // 区间不相交 → 跳过。
    if (segEnd <= lineStart || segStart >= lineEnd) return;
    // 计算本行内需高亮的字符下标区间 [from, to)。
    final from = (segStart - lineStart).clamp(0, line.columns.length);
    final to = (segEnd - lineStart).clamp(0, line.columns.length);
    for (var i = from; i < to; i++) {
      if (line.columns[i] is TextColumn) {
        (line.columns[i] as TextColumn).isAloud = true;
      }
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

  /// 朗读高亮版本号。朗读进度推进时自增, 驱动 [shouldRepaint] 重绘当前段高亮。
  ///
  /// 必要性: [TextLine] 是不可变 const 对象, `old.line != line` 比对象引用。
  /// 朗读高亮变化时 line 引用不变 → shouldRepaint 返 false → 不重绘 → 高亮不动。
  /// 引入版本号打破这个僵局: 版本号变 → shouldRepaint 返 true → 重绘。
  final int aloudVersion;

  _TextLinePainter({
    required this.line,
    required this.style,
    this.aloudVersion = 0,
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
    return oldDelegate.line != line ||
        oldDelegate.style != style ||
        oldDelegate.aloudVersion != aloudVersion;
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
    this.size = kBatteryIconSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * kBatteryIconAspect),
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
