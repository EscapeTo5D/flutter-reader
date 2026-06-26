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
  final double height; // TextPainter 原始行高(含 lineHeight 倍数), 用于渲染 SizedBox

  /// 纯字高(ascent + descent, 不含行距留白)。
  /// 对齐原生 legado 的 textHeight 语义: 分页放行判断用纯字高, 让末行的行距
  /// 留白允许溢出页底(被 ClipRect 裁掉留白, 不裁字)。为 0 时退回用 [height]。
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

  /// 是否为空段落行(用于渲染段间距)
  bool get isEmptyParagraph => text.isEmpty && isParagraphEnd;

  /// 是否包含字符级排版数据(Column 列表)
  bool get hasCharData => columns.isNotEmpty;
}
