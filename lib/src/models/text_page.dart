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
  final double height;

  const TextLine({
    required this.text,
    this.isTitle = false,
    this.isParagraphEnd = false,
    required this.height,
  });
}
