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
  final double height; // TextPainter 原始行高(不含 lineHeight 倍数)

  // --- 字符级排版信息 ---
  /// 每个字符的原始宽度(由 TextPainter 测量)
  final List<double> charWidths;

  /// 缩进宽度(像素)
  final double indentWidth;

  /// 缩进字符数(用于绘制时跳过缩进字符)
  final int indentSize;

  /// 两端对齐时的额外字间距(比率, 需乘以 fontSize 使用)
  final double extraLetterSpacing;

  /// 两端对齐时的词间距(像素, 用于有空格的英文文本)
  final double wordSpacing;

  /// 是否需要两端对齐(多行段落的中间行)
  final bool isJustified;

  /// 该行在页面中的绝对 Y 坐标(由底部对齐算法计算后设置)
  final double lineTop;

  const TextLine({
    required this.text,
    this.isTitle = false,
    this.isParagraphEnd = false,
    required this.height,
    this.charWidths = const [],
    this.indentWidth = 0.0,
    this.indentSize = 0,
    this.extraLetterSpacing = 0.0,
    this.wordSpacing = 0.0,
    this.isJustified = false,
    this.lineTop = 0.0,
  });

  /// 是否为空段落行(用于渲染段间距)
  bool get isEmptyParagraph => text.isEmpty && isParagraphEnd;

  /// 是否包含字符级排版数据
  bool get hasCharData => charWidths.isNotEmpty;
}
