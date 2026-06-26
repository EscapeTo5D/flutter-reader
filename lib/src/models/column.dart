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

  /// 绘制该列
  void draw(Canvas canvas, TextStyle style, double lineBase);

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

  TextColumn({
    required this.charData,
    required super.start,
    required super.end,
    this.selected = false,
    this.isSearchResult = false,
  });

  @override
  void draw(Canvas canvas, TextStyle style, double lineBase) {
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

    // 绘制文字
    final painter = TextPainter(
      text: TextSpan(text: charData, style: style),
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
  void draw(Canvas canvas, TextStyle style, double lineBase) {
    // TODO: 实现图片绘制
  }
}
