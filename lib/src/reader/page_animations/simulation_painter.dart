import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'simulation_geometry.dart';

/// 仿真翻页绘制器(MVP 阶段)。
///
/// 逐层翻译原生 legado `SimulationPageDelegate.onDraw` 的 4 个绘制函数, 但**省略
/// 背面 bitmap 反射矩阵**(第二阶段补)与正面高光阴影(`drawCurrentPageShadow`)。
/// 即使如此, 已能呈现仿真翻页约 80% 观感: 卷曲形状 + 当前页裁剪露出下层 +
/// 下一页 + 背面投影 + 折痕暗影 + 背面铺背景色(看起来像翻起的纸背)。
///
/// 绘制顺序(从底到顶, 对齐原生 `onDraw` NEXT 分支 247-268):
/// 1. [drawCurrentPageArea]   当前页裁掉翻起区(clipOutPath) → 露出下层页
/// 2. [drawNextPageAreaAndShadow] 下层目标页 + 卷曲投影
/// 3. [drawCurrentBackArea]   翻起页背面(MVP: 铺背景色 + 折痕阴影, 不画镜像文字)
///
/// ⚠️ 颜色换算(原生 Kotlin Int → Flutter 0xAARRGGBB):
/// - `0x333333`        = `0x00333333` (alpha 0, folder shadow 起点)
/// - `-0x4fcccccd`     = `0xB0333333` (folder shadow 终点, 较深)
/// - `-0xeeeeef`       = `0xFF111111` (back/front shadow 起点, 不透明)
/// - `0x111111`        = `0x00111111` (back/front shadow 终点, alpha 0)
/// - `-0x7feeeeef`     = `0x80111111` (front shadow 起点, 半透明)
///
/// ⚠️ Flutter `Canvas.clipPath` **不支持 `ClipOp.difference`**(仅 `clipRect` 支持)。
/// 对齐原生 `clipOutPath(path0)` 的差集裁剪用 `Path.combine(PathOperation.difference, 全屏矩形, path0)`
/// 预先算出"全屏减去翻起区"的路径, 再 intersect-clip。这是 Flutter 与原生 API 的关键差异。
class SimulationPainter extends CustomPainter {
  /// 翻起页(当前页)位图。null 时 [drawCurrentPageArea] 用纯色矩形降级。
  final ui.Image? curImage;

  /// 翻页目标页位图(NEXT=下一页, PREV=上一页)。null 时纯色降级。
  final ui.Image? targetImage;

  /// 翻页方向: true=NEXT(向后翻), false=PREV(向前翻)。
  final bool isNext;

  /// 当前触摸点(逻辑像素, 坐标原点为页面左上)。MVP 仅水平翻页, 但 touch 的 Y
  /// 决定卷曲高度(对齐原生 `mTouchY`, 由 reader_view 的锁边逻辑约束)。
  final Offset touch;

  /// 拖拽对应的页角(由 reader_view 在手势 down 时用 `calcCornerXY` 算出)。
  final SimCorner corner;

  /// 页面背景色(用于 [drawCurrentBackArea] 铺背面底色, 对齐原生 `bgMeanColor`)。
  final Color bgColor;

  /// 页面尺寸(逻辑像素)。位图按此尺寸绘制(drawImageRect 拉伸/贴合)。
  final Size viewSize;

  /// 设备像素比。位图由 `RepaintBoundary.toImage` 以 devicePixelRatio 截图,
  /// 绘制时按逻辑尺寸贴回, 故 drawImageRect 用 [viewSize] 作 dst。
  final double devicePixelRatio;

  SimulationPainter({
    required this.curImage,
    required this.targetImage,
    required this.isNext,
    required this.touch,
    required this.corner,
    required this.bgColor,
    required this.viewSize,
    this.devicePixelRatio = 1.0,
  });

  // ---- 阴影颜色(对齐原生 init 块, 已换算为 0xAARRGGBB) ----
  // 折痕阴影(folder): 起点近透明 → 终点较深灰。
  static const Color _folderShadowStart = Color(0x00333333);
  static const Color _folderShadowEnd = Color(0xB0333333);
  // 背面投影(back): 起点 nearly 不透明深色 → 终点透明。
  static const Color _backShadowStart = Color(0xFF111111);
  static const Color _backShadowEnd = Color(0x00111111);

  /// 对角线长(用于阴影矩形高度, 对齐原生 `mMaxLength = hypot(W, H)`)。
  double get _maxLength =>
      math.sqrt(viewSize.width * viewSize.width + viewSize.height * viewSize.height);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // 触摸点不为 0(对齐原生 mTouchX/Y 初始化 0.1 的除零保护)。
    final t = Offset(touch.dx == 0 ? 0.1 : touch.dx, touch.dy == 0 ? 0.1 : touch.dy);
    final pts = SimGeometry.calcPoints(
      SimPoint(t.dx, t.dy),
      corner,
      viewSize.width,
      viewSize.height,
    );

    // 选择位图: NEXT 时翻起页是 cur, 露出的是 next; PREV 时翻起页是 prev, 露出 cur。
    // 对齐原生 onDraw NEXT/PREV 两分支的 bitmap 入参。
    final turningImage = curImage; // 翻起页固定为 cur(PREV 时 reader_view 传 prev 作 curImage)
    final baseImage = targetImage; // 露出的底层页

    _drawCurrentPageArea(canvas, pts, turningImage);
    _drawNextPageAreaAndShadow(canvas, pts, baseImage);
    _drawCurrentBackArea(canvas, pts);
  }

  /// ① 绘制翻起页正面(屏幕剩余区)。
  ///
  /// 对齐原生 `drawCurrentPageArea`(`SimulationPageDelegate.kt:486-508`):
  /// 用卷曲边贝塞尔路径(path0)做 **差集裁剪**(clipOutPath), 在 path0 之外画整张
  /// 当前页位图 → 露出当前页未被卷起的部分。
  ///
  /// Flutter `clipPath` 无 difference, 故用 `Path.combine(difference, 全屏, path0)`
  /// 预算"全屏减翻起区", 再 intersect-clip 后画整页位图。
  void _drawCurrentPageArea(ui.Canvas canvas, SimPoints pts, ui.Image? image) {
    final path0 = _buildPath0(pts);
    final fullRect = ui.Path()..addRect(Offset.zero & viewSize);
    final outside = ui.Path.combine(ui.PathOperation.difference, fullRect, path0);
    canvas.save();
    canvas.clipPath(outside);
    _drawPageImage(canvas, image);
    canvas.restore();
  }

  /// ② 绘制底层目标页 + 卷曲投影。
  ///
  /// 对齐原生 `drawNextPageAreaAndShadow`(`SimulationPageDelegate.kt:438-483`):
  /// path1 = start1 → vertex1 → vertex2 → start2 → corner → close(卷曲三角形外区域)。
  /// 先 clip path0(卷曲区) 再 clip path1, 求交得"露出的底层页区域", 画底层页位图,
  /// 再按 degrees 旋转后画一道从卷曲边向外渐隐的投影(backShadow)。
  void _drawNextPageAreaAndShadow(ui.Canvas canvas, SimPoints pts, ui.Image? image) {
    final path0 = _buildPath0(pts);
    final path1 = ui.Path()
      ..moveTo(pts.start1.x, pts.start1.y)
      ..lineTo(pts.vertex1.x, pts.vertex1.y)
      ..lineTo(pts.vertex2.x, pts.vertex2.y)
      ..lineTo(pts.start2.x, pts.start2.y)
      ..lineTo(corner.cornerX, corner.cornerY)
      ..close();

    canvas.save();
    canvas.clipPath(path0); // intersect
    canvas.clipPath(path1); // intersect
    _drawPageImage(canvas, image);

    // 投影位置: 起点 start1, 宽度 = touchToCornerDis / 4(对齐原生)。
    final projWidth = pts.touchToCornerDis / 4;
    final start1X = pts.start1.x;
    final start1Y = pts.start1.y;
    final maxLen = _maxLength;

    double leftX;
    double rightX;
    ui.Gradient gradient;
    if (corner.isRtOrLb) {
      // 左下 / 右上: 投影从 start1 向右渐隐(LR)。
      leftX = start1X;
      rightX = start1X + projWidth;
      gradient = ui.Gradient.linear(
        Offset(leftX, start1Y),
        Offset(rightX, start1Y),
        [_backShadowStart, _backShadowEnd],
      );
    } else {
      leftX = start1X - projWidth;
      rightX = start1X;
      gradient = ui.Gradient.linear(
        Offset(leftX, start1Y),
        Offset(rightX, start1Y),
        [_backShadowStart, _backShadowEnd],
      );
    }

    canvas.save();
    // 旋转到卷曲边方向再画矩形投影(原生 canvas.rotate(degrees, start1.x, start1.y))。
    canvas.translate(start1X, start1Y);
    canvas.rotate(pts.degrees * math.pi / 180);
    canvas.translate(-start1X, -start1Y);
    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(leftX, start1Y, rightX, start1Y + maxLen),
      paint,
    );
    canvas.restore();

    canvas.restore();
  }

  /// ③ 绘制翻起页背面(MVP 简化版)。
  ///
  /// 对齐原生 `drawCurrentBackArea`(`SimulationPageDelegate.kt:273-335`)的**结构**,
  /// 但**省略 bitmap 反射矩阵**(第二阶段补)。MVP 阶段:
  /// - clip path0 ∩ path1(卷曲三角形区域)
  /// - 铺背景色(对齐原生 `canvas.drawColor(bgMeanColor)` —— 看起来像翻起的纸背底色)
  /// - 按折痕方向画一道 folderShadow 暗影(折痕处更深, 让背面有立体感)
  ///
  /// 第二阶段会在此处加 Householder 反射矩阵(`Matrix4` + `canvas.transform`),
  /// 把当前页位图沿折痕镜像绘制, 让背面显示镜像文字 —— 那才是"像纸"的灵魂。
  void _drawCurrentBackArea(ui.Canvas canvas, SimPoints pts) {
    // f3 = 折痕阴影宽度(对齐原生 f3 = min(f1, f2))。
    final f1 = ((pts.start1.x + pts.control1.x) / 2 - pts.control1.x).abs();
    final f2 = ((pts.start2.y + pts.control2.y) / 2 - pts.control2.y).abs();
    final f3 = math.min(f1, f2);

    final path0 = _buildPath0(pts);
    final path1 = ui.Path()
      ..moveTo(pts.vertex2.x, pts.vertex2.y)
      ..lineTo(pts.vertex1.x, pts.vertex1.y)
      ..lineTo(pts.end1.x, pts.end1.y)
      ..lineTo(pts.touch.x, pts.touch.y)
      ..lineTo(pts.end2.x, pts.end2.y)
      ..close();

    canvas.save();
    canvas.clipPath(path0);
    canvas.clipPath(path1);

    // 铺背景色(纸背底色)。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewSize.width, viewSize.height),
      Paint()..color = bgColor,
    );

    // 折痕阴影: 从 start1 沿 isRtOrLb 方向渐变(f3 宽)。
    final start1X = pts.start1.x;
    final start1Y = pts.start1.y;
    final maxLen = _maxLength;
    double leftX;
    double rightX;
    ui.Gradient gradient;
    if (corner.isRtOrLb) {
      leftX = start1X - 1;
      rightX = start1X + f3 + 1;
      gradient = ui.Gradient.linear(
        Offset(leftX, start1Y),
        Offset(rightX, start1Y),
        [_folderShadowStart, _folderShadowEnd],
      );
    } else {
      leftX = start1X - f3 - 1;
      rightX = start1X + 1;
      gradient = ui.Gradient.linear(
        Offset(leftX, start1Y),
        Offset(rightX, start1Y),
        [_folderShadowEnd, _folderShadowStart],
      );
    }

    canvas.save();
    canvas.translate(start1X, start1Y);
    canvas.rotate(pts.degrees * math.pi / 180);
    canvas.translate(-start1X, -start1Y);
    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(leftX, start1Y, rightX, start1Y + maxLen),
      paint,
    );
    canvas.restore();

    canvas.restore();
  }

  /// 构造 path0(卷曲边贝塞尔封闭路径, 对齐原生 `drawCurrentPageArea` 491-498):
  /// start1 → quadTo(control1, end1) → touch → end2 → quadTo(control2, start2)
  /// → corner → close。
  ///
  /// 此路径定义"翻起区域", 是差集裁剪与后续交裁剪的基准。
  ui.Path _buildPath0(SimPoints pts) {
    return ui.Path()
      ..moveTo(pts.start1.x, pts.start1.y)
      ..quadraticBezierTo(pts.control1.x, pts.control1.y, pts.end1.x, pts.end1.y)
      ..lineTo(pts.touch.x, pts.touch.y)
      ..lineTo(pts.end2.x, pts.end2.y)
      ..quadraticBezierTo(pts.control2.x, pts.control2.y, pts.start2.x, pts.start2.y)
      ..lineTo(corner.cornerX, corner.cornerY)
      ..close();
  }

  /// 把一张页面位图按 [viewSize] 贴到画布(覆盖整页)。
  /// image 为 null 时用背景色降级填充(截图未就绪时不崩, 卷曲形状仍可见)。
  void _drawPageImage(ui.Canvas canvas, ui.Image? image) {
    if (image == null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, viewSize.width, viewSize.height),
        Paint()..color = bgColor,
      );
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(covariant SimulationPainter old) =>
      old.touch != touch ||
      old.corner.cornerX != corner.cornerX ||
      old.corner.cornerY != corner.cornerY ||
      old.isNext != isNext ||
      old.curImage != curImage ||
      old.targetImage != targetImage ||
      old.bgColor != bgColor ||
      old.viewSize != viewSize;
}
