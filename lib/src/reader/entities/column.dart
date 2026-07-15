import 'package:flutter/material.dart';

/// 字符列基类 - 对应原生 Android BaseColumn
///
/// 每个 Column 代表一行中的一个可绘制单元(字符、图片等),
/// 持有精确的像素坐标 [start]/[end]，支持逐字绘制和触摸检测。
abstract class BaseColumn {
  /// 列起始 X 坐标(相对于行左边缘)
  double start;

  /// 列结束 X 坐标(相对于行左边缘)
  double end;

  BaseColumn({required this.start, required this.end});

  /// 绘制该列。[accentColor] 非空时用于朗读/搜索命中列的前景色覆盖。
  void draw(Canvas canvas, TextStyle style, double lineBase, {Color? accentColor});

  /// 触摸检测：点击坐标 x 是否落在该列范围内
  bool isTouch(double x) => x >= start && x <= end;

  /// 列宽度
  double get width => end - start;
}

/// 文字列 - 对应原生 Android TextColumn
///
/// 表示一个普通文字字符，支持选中和搜索结果高亮。
class TextColumn extends BaseColumn {
  /// 单个字符数据
  final String charData;

  /// 是否被选中
  bool selected;

  /// 是否为搜索结果
  bool isSearchResult;

  /// 是否为朗读高亮(对应原生 `TextPage.upPageAloudSpan` 标记)。
  ///
  /// mutable 字段, 在 `PageView._buildLine` 每次构建时重算(先清后标),
  /// 与 [selected]/[isSearchResult] 同套机制。详见 `_markAloud`。
  bool isAloud;

  TextColumn({
    required this.charData,
    required super.start,
    required super.end,
    this.selected = false,
    this.isSearchResult = false,
    this.isAloud = false,
  });

  @override
  void draw(Canvas canvas, TextStyle style, double lineBase, {Color? accentColor}) {
    // 绘制选中背景
    if (selected) {
      final bgPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(start, 0, end, lineBase + style.fontSize! * 0.3),
        bgPaint,
      );
    }

    // 绘制搜索结果高亮背景
    if (isSearchResult) {
      final bgPaint = Paint()
        ..color = Colors.yellow.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(start, 0, end, lineBase + style.fontSize! * 0.3),
        bgPaint,
      );
    }

    // 朗读高亮: 对齐原生 legado `TextColumn.draw` —— 当前朗读段落用强调色作
    // **前景文字色**(textAccentColor, 默认红 #E53935), 不画背景。与"手动选词"
    // (selectedPaint 背景高亮)区分开。(搜索结果 isSearchResult 是既有独立功能,
    // 仍用黄色背景, 不走这里。)
    final fgColor = isAloud ? accentColor ?? style.color : style.color;

    // 绘制文字(朗读段用强调色, 否则普通文字色)
    final painter = TextPainter(
      text: TextSpan(text: charData, style: style.copyWith(color: fgColor)),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset(start, 0));
  }

  @override
  String toString() => 'TextColumn("$charData", ${start.toStringAsFixed(1)}..${end.toStringAsFixed(1)})';
}

/// 图片列 - 对应原生 Android ImageColumn (预留)
///
/// 用于行内图片混排，当前仅预留接口。
class ImageColumn extends BaseColumn {
  /// 图片地址
  final String src;

  /// 图片显示高度
  final double imageHeight;

  ImageColumn({
    required this.src,
    required super.start,
    required super.end,
    required this.imageHeight,
  });

  @override
  void draw(Canvas canvas, TextStyle style, double lineBase, {Color? accentColor}) {
    // TODO: 实现图片绘制
  }
}
