import 'column.dart';

class TextPage {
  final List<TextLine> lines;
  final int pageIndex;
  final String? title;

  const TextPage({
    required this.lines,
    required this.pageIndex,
    this.title,
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

class TextLine {
  final String text;
  final bool isTitle;
  final bool isParagraphEnd;
  final bool isEndPadding; // 末页尾部留白行(对齐原生 endPadding=20dp), 不含文字
  final bool isPageBreak; // 强制分页标记行(对齐原生 [newpage]), 不含文字不占高度
  final double height; // 渲染行高 = textHeight * lineSpacingExtra(对齐原生 durY 累加)

  /// 纯字体度量(不含行距倍数), 对应原生 ChapterProvider 的
  /// `textHeight = descent - ascent + leading`。用于段距计算:
  /// `段距 = textHeight * paragraphSpacing / 10`(对齐原生公式)。
  /// 由 `metric.height / style.height` 反推(Flutter 把 leading 摊进 height)。
  final double textHeight;

  // --- 字符级排版信息(逐字符 Column) ---
  /// 每个字符的 Column 对象，持有精确的 start/end 像素坐标
  final List<BaseColumn> columns;

  /// 缩进宽度(像素)
  final double indentWidth;

  /// 缩进字符数
  final int indentSize;

  /// 该行在页面中的绝对 Y 坐标(由底部对齐算法计算后设置)
  final double lineTop;

  /// 行基线 Y 坐标(相对于行顶部)
  final double lineBase;

  /// 行底部 Y 坐标(相对于行顶部)
  final double lineBottom;

  /// 段落编号(用于段评等功能)
  final int paragraphNum;

  /// 该行在章节中的起始字符位置
  final int chapterPosition;

  const TextLine({
    required this.text,
    this.isTitle = false,
    this.isParagraphEnd = false,
    this.isEndPadding = false,
    this.isPageBreak = false,
    required this.height,
    this.textHeight = 0.0,
    this.columns = const [],
    this.indentWidth = 0.0,
    this.indentSize = 0,
    this.lineTop = 0.0,
    this.lineBase = 0.0,
    this.lineBottom = 0.0,
    this.paragraphNum = 0,
    this.chapterPosition = 0,
  });

  /// 是否为空段落行(段间距/末页留白/强制分页, 渲染时不绘制文字、底部对齐时跳过)
  bool get isEmptyParagraph =>
      (text.isEmpty && isParagraphEnd) || isEndPadding || isPageBreak;

  /// 是否包含字符级排版数据(Column 列表)
  bool get hasCharData => columns.isNotEmpty;
}
