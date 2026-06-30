import 'package:flutter/material.dart';
import '../entities/text_page.dart';
import '../entities/column.dart';
import '../../core/models/reading_settings.dart';

class PageEngine {
  /// 末页尾部留白, 对齐原生 legado 的 `endPadding = 20.dp`(20 逻辑像素)。
  static const double _endPadding = 20.0;

  /// 字体度量补偿系数: 让 Flutter 行距/段距视觉对齐原生 legado。
  ///
  /// 根因: 两平台「纯字体度量 textHeight」的 ratio 不同。
  ///   原生 textHeight = descent - ascent + leading (Android Paint, 中文字体
  ///     如思源黑体/Noto CJK) ≈ fontSize × 1.4 (asc/desc 都大, 含 leading)。
  ///   Flutter textHeight = metric.height / lineHeight ≈ fontSize × 1.0
  ///     (默认 Roboto, ratio=1.0, 无 leading; 实测各字号 height 恒等 fontSize)。
  ///
  /// 故同样的 lineSpacingExtra 倍数, 原生行推进 = fontSize×1.4×倍数, Flutter 仅
  /// fontSize×1.0×倍数, 视觉偏紧约 0.4。用户实测印证: 无补偿时 Flutter 行距显示
  /// 0.4(lineHeight=1.4) 才 ≈ 原生显示 0.0(lineSpacingExtra=1.0)。
  ///
  /// 此系数把 Flutter 间距性质(行块高/段距)放大到原生量级, 使滑块显示值与原生
  /// 语义一致(原生0.0 ↔ Flutter0.0)。仅作用于"间距", 不影响:
  ///   - baseline 定位(用真实 textHeight-descent, 文字垂直位置由字体本身决定)
  ///   - 滑块换算/预设值(仍按原生 progress 语义, 用户看到的数值不变)
  ///   - textHeight 字段(保持纯字体度量, baseline 与段距借用都依赖它)
  static const double _nativeMetricFactor = 1.4;

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

    // 当前段落在「预处理后内容」中的起始字符偏移。
    //
    // chapterPosition 用于阅读进度持久化: 进度存 (chapterIndex, charOffset) 而非
    // pageIndex, 这样改字号/行距/换设备重排后, 用 charOffset 二分各页首行的
    // chapterPosition 即可定位回对应页, 不丢进度(对齐原生 legado dur/durPos)。
    //
    // charOffset 是「预处理后内容」(ContentProcessor 输出 join('\n')) 的绝对偏移,
    // **标题段也计入偏移流**(标题不特殊归零)——这样恢复时用同一套 ContentProcessor
    // 重新生成内容, 偏移自洽可逆(无需知道标题边界来扣减)。
    var contentOffset = 0;

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      // 预先推进: 本轮 para 起点偏移 = contentOffset, 末尾 +1 算 '\n' 分隔符。
      // 预先推进让所有 continue 分支(newpage/空段/隐藏标题)也正确累计偏移。
      final paraStart = contentOffset;
      contentOffset += para.length + 1;

      // 强制分页标记: 对齐原生 TextChapterLayout.kt:333
      // `if (text == "[newpage]") { prepareNextPageIfNeed(); return@forEach }`
      // 书源用 [newpage] 做卷封/场景切换的分隔, 原样显示会是脏字符。
      // 这里插入一个零高度的 isPageBreak 行, _splitIntoPages 遇到即强制结束当前页,
      // 该行自身不显示。
      if (para.trim() == '[newpage]') {
        lines.add(const TextLine(
          text: '',
          height: 0.0,
          isPageBreak: true,
        ));
        continue;
      }

      if (para.trim().isEmpty) {
        // 段距补偿: 同样乘 _nativeMetricFactor, 对齐原生(原生段距基于
        // ratio~1.4 的 textHeight, Flutter textHeight ratio 1.0, 需放大)。
        final spacing =
            lastTextHeight * settings.paragraphSpacing / 10.0 * _nativeMetricFactor;
        lines.add(TextLine(
          text: '',
          height: spacing,
          textHeight: lastTextHeight,
          isParagraphEnd: true,
          chapterPosition: paraStart,
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
          chapterPosition: paraStart,
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
        baseOffset: paraStart,
      );
      lines.addAll(textLines);
      // 更新纯字体度量, 供后续段距行借用
      if (textLines.isNotEmpty) {
        lastTextHeight = textLines.last.textHeight;
      }

      // 段后间距: 对齐原生 TextChapterLayout.kt:1026
      // `durY += textHeight * paragraphSpacing / 10f`, 在每个正文段落末尾追加。
      // 标题段有独立的 titleBottomSpacing, 不走这里。
      // 段距同样乘 _nativeMetricFactor 对齐原生(见空段落分支注释)。
      if (!isTitle) {
        final spacing =
            lastTextHeight * settings.paragraphSpacing / 10.0 * _nativeMetricFactor;
        lines.add(TextLine(
          text: '',
          height: spacing,
          textHeight: lastTextHeight,
          isParagraphEnd: true,
          // 段末行取该段尾偏移, 保持 chapterPosition 单调递增
          chapterPosition: paraStart + para.length,
        ));
      }

      // 标题下方间距
      if (isTitle) {
        lines.add(TextLine(
          text: '',
          height: settings.titleBottomSpacing,
          isParagraphEnd: false,
          chapterPosition: paraStart,
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
  ///
  /// [baseOffset] 是该段在「预处理后内容」中的起始字符偏移, 用于给每行写入
  /// [TextLine.chapterPosition] (进度持久化用)。详见 paginate() 注释。
  /// chapterPosition 基于 body(剥缩进后的源文本), 不含显示层缩进字符——
  /// 故每行 = baseOffset + 行在 body 内的起始 offset(= 行在 displayText 内
  /// 的 startOffset 减去 indentStr.length, 首行夹到 0)。
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
    int baseOffset = 0,
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
        chapterPosition: baseOffset,
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
      //
      // 每行用独立 painter 测量(不能用整段 painter: 跨行换行处 caret x 会跳回
      // 行首, 单行内 x 单调假设失效, 导致两端对齐拉伸量算错)。性能瓶颈主要在此,
      // 后续可考虑按 fontSize+letterSpacing 缓存字符宽度。
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

      // 行高用 metric.height(含行距缝), 但 baseline 必须按原生公式重算,
      // 否则行距视觉与原生不对等。
      //
      // 原生 upTopBottom (TextLine.kt:103-107):
      //   lineBottom = lineTop + textHeight              // textHeight 纯字体度量, 不含 extra
      //   lineBase   = lineBottom - fontMetrics.descent  // = textHeight - descent
      // 即文字顶部对齐 textHeight 顶部, lineSpacingExtra 的缝全部留在行块下方。
      //
      // Flutter 若直接用 metric.baseline, Skia 会把 leading 摊在文字上方
      // (文字在 metric.height 块里偏下), lineHeight 越大偏移越明显:
      //   h=1.0 时 baseline 一致(缝为 0, 无 leading 可摊);
      //   h=1.2 时偏 4.83px; h=1.5 时偏 12px (fs=24 实测)。
      // 故用原生公式重算, 让文字在行块内顶部对齐。
      final textHeight = metric.height / (style.height ?? 1.0);
      final nativeBaseline = textHeight - metric.descent;
      // 行块高补偿: metric.height 是 Flutter 字体(ratio 1.0)的行高, 乘以
      // _nativeMetricFactor 放大到原生中文字体(ratio ~1.4)量级, 使行距视觉对齐。
      // 文字仍按真实 textHeight 顶部对齐(nativeBaseline), 多出的缝留在行块下方。
      final blockHeight = metric.height * _nativeMetricFactor;
      // 该行在 body(剥缩进源文本) 内的起始偏移: startOffset 是相对 displayText 的,
      // body 从 displayText 的 indentStr.length 处开始, 故减去缩进长度, 首行夹到 0。
      // + baseOffset 得到该行在整章预处理内容中的字符位置(进度持久化用)。
      final bodyOffset =
          baseOffset + (startOffset - indentStr.length).clamp(0, body.length);
      result.add(TextLine(
        text: lineText,
        height: blockHeight,
        textHeight: textHeight,
        isParagraphEnd: isLastLine,
        isTitle: isTitle,
        columns: columns,
        indentWidth: indentWidth,
        indentSize: indentSize,
        lineBase: nativeBaseline,
        lineBottom: blockHeight,
        chapterPosition: bodyOffset,
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
  ///
  /// 每行用独立 TextPainter 测量, 保证单行内 caret x 单调(整段 painter 在换行
  /// 边界 x 会跳回行首, 差值非字符宽度)。TextPainter 创建+layout 是单章排版
  /// 主要耗时点(~260ms/章), 后续可按 fontSize+letterSpacing+字体 缓存字符宽度表
  /// 来优化, 但需保证缓存 key 含全部影响宽度的因素。
  ///
  /// 优化: 第 i 字符宽度 = caret(i+1).x - caret(i).x, 故只需 N+1 次 caret 查询
  /// 而非 2N 次, 约减半 caret 调用开销(caret 查询本身不便宜)。
  List<double> _measureCharWidths(String text, TextStyle style) {
    if (text.isEmpty) return [];
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    final widths = <double>[];
    var prevX = painter.getOffsetForCaret(
      const TextPosition(offset: 0),
      Rect.zero,
    ).dx;
    for (var i = 0; i < text.length; i++) {
      final x = painter.getOffsetForCaret(
        TextPosition(offset: i + 1),
        Rect.zero,
      ).dx;
      widths.add((x - prevX).abs());
      prevX = x;
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

      // 强制分页标记(对齐原生 [newpage]): 立即结束当前页, 该行不显示不占高度。
      // 即使当前页是空的也结束(对齐原生 prepareNextPageIfNeed 语义),
      // 形成一张"空白页"——常见于书源卷封/留白。
      if (line.isPageBreak) {
        if (currentPageLines.isNotEmpty) {
          _applyBottomJustify(
            currentPageLines,
            availableHeight,
            usedHeight,
            settings,
          );
        }
        pages.add(TextPage(
          lines: List.from(currentPageLines),
          pageIndex: pages.length,
        ));
        currentPageLines = [];
        usedHeight = 0;
        continue; // 跳过该行, 不加入任何页
      }

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
      // 末页追加 endPadding 留白, 对齐原生 ChapterProvider 末尾
      // (TextChapterLayout.kt:499-505): 末页内容顶部对齐、底部加 20dp。
      //
      // ⚠️ 末页【跳过底部对齐(撑满)】。原生末页虽 upLinesPosition 撑满后再
      // height += endPadding(页面逻辑高度可 > visibleHeight), 但 Flutter 渲染是
      // ClipRect 固定 availableHeight, 撑满后 endPadding 行无处安放会被裁 → 截断。
      // 末页内容本就少, 不撑满(顶对齐 + 底部留白)视觉效果与原生接近, 且避免溢出。
      // 仅当末页底部剩余 >= endPadding 时追加留白行。
      final lastSurplus = availableHeight - usedHeight;
      if (lastSurplus >= _endPadding) {
        currentPageLines.add(TextLine(
          text: '',
          height: _endPadding,
          isEndPadding: true,
        ));
      }
      // 注意: 末页不调 _applyBottomJustify, 保持顶对齐。
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
    // 对齐原生 TextPage.kt:108-109 upLinesPosition 守卫:
    //   pageHeight = lastLine.lineBottom + contentPaintTextHeight * lineSpacingExtra
    //   if (visibleHeight - pageHeight >= lastLineHeight) return  // 不撑
    // 守卫阈值 = 一行渲染高度 + 一行行距增量。原生分页保证剩余 < 一行高度,
    // 故此守卫几乎总为 false → 几乎每页撑满, 末行贴底, 到页脚分割线距离恒定。
    // 旧实现阈值仅一行高度(lines.first.height), 段距行排列使 surplus 偶尔 >= 一行
    // → 不撑 → 各页底部留白高度不一致(肉眼可见"末行到分割线距离不固定")。
    final firstTextLine = lines.firstWhere((l) => !l.isEmptyParagraph);
    final lineH = firstTextLine.height; // metric.height, 含行距
    // 行距增量 = metric.height - textHeight, 而 textHeight = metric.height / lineHeight,
    // 故行距增量 = lineH * (1 - 1/lineHeight)。
    final lineSpacingGap = lineH * (1.0 - 1.0 / settings.lineHeight);
    if (surplus <= 0 || surplus >= lineH + lineSpacingGap) return;

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
      // 原生 lineSpacingExtra 范围 -10~10(progress 0~20), 渲染倍数 = /10。
      // 原生可取 0/负(压挤), 但 Flutter TextPainter 要求 height > 0, 否则 assert。
      // 下限保护: 0/负值落到 0.1, 贴近"最紧"视觉效果且不崩。
      height: settings.lineHeight > 0 ? settings.lineHeight : 0.1,
      letterSpacing: settings.letterSpacing,
      color: settings.textColor,
      fontFamily: settings.fontFamily,
    );
  }
}
