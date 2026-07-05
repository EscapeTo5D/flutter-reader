import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'simulation_geometry.dart';

/// 仿真翻页绘制器。
///
/// 逐层翻译原生 legado `SimulationPageDelegate.onDraw` 的 4 个绘制函数, 已全部实现:
/// 卷曲形状 + 当前页裁剪露出下层 + 下一页 + 背面投影 + 正面高光阴影 + 背面镜像文字
/// + 折痕暗影。达到与原生一致的观感。
///
/// 绘制顺序(从底到顶, 对齐原生 `onDraw` NEXT 分支 247-268):
/// 1. [drawCurrentPageArea]   当前页裁掉翻起区(clipOutPath) → 露出下层页
/// 2. [drawNextPageAreaAndShadow] 下层目标页 + 卷曲投影
/// 3. [drawCurrentPageShadow]   翻起页正面高光阴影(两段 frontShadow)
/// 4. [drawCurrentBackArea]   翻起页背面(铺背景色 + Householder 镜像文字 + 折痕阴影)
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
  // 正面高光阴影(front): 起点半透明深色 → 终点透明。
  // 对齐原生 mFrontShadowColors = {-0x7feeeeef(=0x80111111), 0x111111(=0x00111111)}。
  static const Color _frontShadowStart = Color(0x80111111);
  static const Color _frontShadowEnd = Color(0x00111111);

  /// 对角线长(用于阴影矩形高度, 对齐原生 `mMaxLength = hypot(W, H)`)。
  double get _maxLength =>
      math.sqrt(viewSize.width * viewSize.width + viewSize.height * viewSize.height);

  /// 阴影渐变宽度(dp)。
  ///
  /// 原生 Android 的 `Canvas`/`viewWidth` 都是 **物理像素(px)**, 故硬编码的 `25` 是
  /// 25px。Flutter `Canvas`/`viewSize` 是**逻辑像素(dp)**, 直接用 25 会让阴影在
  /// DPR=2.5~3 的设备上放大 2.5~3 倍 —— 用户反馈的"阴影扩散范围比原生大"根因。
  /// 故按 DPR 反算: `25 dp → 25/dpr px` 等效于原生的 25px。
  ///
  /// 对齐原生 `mFrontShadowColors`/`drawCurrentPageShadow` 的 25、`mBackShadowDrawable`
  /// 不受影响(它用 `touchToCornerDis/4`, 是 dp 域的比例量)。
  double get _shadowWidth => 25.0 / devicePixelRatio;

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
    _drawCurrentPageShadow(canvas, pts);
    _drawCurrentBackArea(canvas, pts, turningImage);
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
      // 渐变方向 from=折痕端 start1(深) → to=远端(透明)。对齐原生 RL 语义
      // (colors[0]=深在 right=start1, colors[1]=透明在 left=start1-projW)。
      gradient = ui.Gradient.linear(
        Offset(rightX, start1Y),
        Offset(leftX, start1Y),
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

  /// ③ 绘制翻起页正面高光阴影(两段 frontShadow)。
  ///
  /// 对齐原生 `drawCurrentPageShadow`(`SimulationPageDelegate.kt:340-435`)。
  /// 在翻起页**正面**靠近折痕处画两道渐变高光, 让纸面有立体反光质感。
  /// 两段阴影的几何基座共用一个顶点(touch 偏移 shadowWidth·√2, 由
  /// [SimGeometry.calcFrontShadowTip] 算出), 分别沿 control1 / control2 边绘制。
  ///
  /// **第一段**(原生 355-390): 沿 control1 边的竖直渐变(VLR/VRL)。
  /// - path1 = (tip) → touch → control1 → start1 → close
  /// - 裁剪: clipOutPath(path0) ∩ path1 —— 仅在「未卷起区 + 阴影三角形」交集内画
  /// - shadowWidth dp 宽竖直渐变, 绕 control1 旋转到折痕法线方向
  ///
  /// **第二段**(原生 392-434): 沿 control2 边的水平渐变(HTB/HBT)。
  /// - path1 = (tip) → touch → control2 → start2 → close
  /// - 裁剪同第一段: clipOutPath(path0) ∩ path1
  /// - shadowWidth dp 高水平渐变, 绕 control2 旋转; 含 control2.y<0 时的边界 hmg 修正
  ///
  /// ⚠️ tip 用 [SimPoints.touch](边界钳制后的 touch), 与原生用 `mTouchX/mTouchY`
  /// 一致(原生 `calcPoints` 钳制分支会改写 `mTouchX/Y`, 阴影顶点用钳制后的值)。
  /// 若用原始 touch 会在拖到屏幕边缘(即"翻页角"附近)时阴影顶点偏移, 阴影方向错乱。
  ///
  /// ⚠️ 阴影宽度 shadowWidth = `25 / devicePixelRatio`(见 [_shadowWidth]),
  /// 不是直接用原生的 25 —— 原生在 px 域, Flutter 在 dp 域。
  ///
  /// ⚠️ Flutter `Canvas.clipPath` 无 `ClipOp.difference`, clipOutPath 用
  /// `Path.combine(PathOperation.difference, 全屏, path0)` 预算后 intersect-clip。
  void _drawCurrentPageShadow(ui.Canvas canvas, SimPoints pts) {
    final touch = pts.touch;
    final sw = _shadowWidth;
    final tip = SimGeometry.calcFrontShadowTip(touch, pts, corner, shadowWidth: sw);
    final path0 = _buildPath0(pts);
    // clipOutPath(path0) 的 Flutter 等价: 全屏 - path0(差集)。
    final fullRect = ui.Path()..addRect(Offset.zero & viewSize);
    final outsidePath0 =
        ui.Path.combine(ui.PathOperation.difference, fullRect, path0);
    final maxLen = _maxLength;

    // ---- 第一段: 沿 control1 边的竖直渐变 ----
    final path1A = ui.Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(pts.touch.x, pts.touch.y)
      ..lineTo(pts.control1.x, pts.control1.y)
      ..lineTo(pts.start1.x, pts.start1.y)
      ..close();
    canvas.save();
    canvas.clipPath(outsidePath0);
    canvas.clipPath(path1A);
    final c1x = pts.control1.x;
    final c1y = pts.control1.y;
    final gradA = corner.isRtOrLb
        ? ui.Gradient.linear(
            // LR: 深在左(control), 透明在右(c1x+sw)。
            Offset(c1x, c1y),
            Offset(c1x + sw, c1y),
            [_frontShadowStart, _frontShadowEnd],
          )
        : ui.Gradient.linear(
            // RL: 深在右(control), 透明在左(c1x-sw)。对齐原生 VRL 语义
            // (colors[0]=深在 right=c1x+1, colors[1]=透明在 left=c1x-sw)。
            Offset(c1x + 1, c1y),
            Offset(c1x - sw, c1y),
            [_frontShadowStart, _frontShadowEnd],
          );
    final leftA = corner.isRtOrLb ? c1x : c1x - sw;
    final rightA = corner.isRtOrLb ? c1x + sw : c1x + 1;
    // 旋转到折痕法线方向: rotateDegrees = atan2(touchX-control1.x, control1.y-touchY)。
    final rotA = math.atan2(
            pts.touch.x - c1x, c1y - pts.touch.y) *
        180 /
        math.pi;
    canvas.translate(c1x, c1y);
    canvas.rotate(rotA * math.pi / 180);
    canvas.translate(-c1x, -c1y);
    canvas.drawRect(
      Rect.fromLTRB(leftA, c1y - maxLen, rightA, c1y),
      Paint()..shader = gradA,
    );
    canvas.restore();

    // ---- 第二段: 沿 control2 边的水平渐变 ----
    final path1B = ui.Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(pts.touch.x, pts.touch.y)
      ..lineTo(pts.control2.x, pts.control2.y)
      ..lineTo(pts.start2.x, pts.start2.y)
      ..close();
    canvas.save();
    canvas.clipPath(outsidePath0);
    canvas.clipPath(path1B);
    final c2x = pts.control2.x;
    final c2y = pts.control2.y;
    final gradB = corner.isRtOrLb
        ? ui.Gradient.linear(
            // HTB: 深在上(control2.y), 透明在下(c2y+sw)。
            Offset(c2x, c2y),
            Offset(c2x, c2y + sw),
            [_frontShadowStart, _frontShadowEnd],
          )
        : ui.Gradient.linear(
            // HBT: 深在下(control2.y), 透明在上(c2y-sw)。对齐原生 HBT 语义
            // (colors[0]=深在 bottom=c2y+1, colors[1]=透明在 top=c2y-sw)。
            Offset(c2x, c2y + 1),
            Offset(c2x, c2y - sw),
            [_frontShadowStart, _frontShadowEnd],
          );
    final leftB = corner.isRtOrLb ? c2y : c2y - sw;
    final rightB = corner.isRtOrLb ? c2y + sw : c2y + 1;
    final rotB = math.atan2(
            c2y - pts.touch.y, c2x - pts.touch.x) *
        180 /
        math.pi;
    canvas.translate(c2x, c2y);
    canvas.rotate(rotB * math.pi / 180);
    canvas.translate(-c2x, -c2y);
    // 边界修正(对齐原生 419-432): control2.y<0 时按 hmg 平移阴影矩形。
    final temp = c2y < 0 ? c2y - viewSize.height : c2y;
    final hmg = math.sqrt(c2x * c2x + temp * temp);
    double rectLeft;
    double rectRight;
    if (hmg > maxLen) {
      rectLeft = c2x - sw - hmg;
      rectRight = c2x + maxLen - hmg;
    } else {
      rectLeft = c2x - maxLen;
      rectRight = c2x;
    }
    // 注意: 原生第二段 setBounds(leftX=control2.y, ..., rightX=control2.y+25) 把
    // y 当 left/right 用 —— 因 rotate 后矩形的"宽"实际是竖直方向高度。Flutter 这里的
    // leftB/rightB 是渐变方向(竖直), 配合上面 rotate 后 drawRect 的 x 维度。
    canvas.drawRect(
      Rect.fromLTRB(rectLeft, leftB, rectRight, rightB),
      Paint()..shader = gradB,
    );
    canvas.restore();
  }

  /// ④ 绘制翻起页背面(Householder 反射镜像版)。
  ///
  /// 对齐原生 `drawCurrentBackArea`(`SimulationPageDelegate.kt:273-335`):
  /// - clip path0 ∩ path1(卷曲三角形区域)
  /// - 铺背景色(对齐原生 `canvas.drawColor(bgMeanColor)` —— 纸背底色)
  /// - **沿折痕反射镜像绘制当前页位图**(原生 311-326 行 Householder 矩阵) →
  ///   背面显示反向文字, "像纸"的灵魂
  /// - 按折痕方向画一道 folderShadow 暗影(折痕处更深, 让背面有立体感)
  ///
  /// 反射矩阵构造(对齐原生 `mMatrix.setValues` + pre/postTranslate):
  /// ```
  /// M = T(anchor) · R · T(-anchor)
  ///   anchor = control1, R = | 1-2f9²    2f8f9  |
  ///                           | 2f8f9     1-2f8² |
  /// ```
  /// 由 [SimGeometry.calcReflection] 算出 (f8, f9, anchor), 这里展开成 4×4 列主序矩阵
  /// 喂给 `canvas.transform`。Flutter `Canvas.transform` 接受 `Float64List`(16 元素,
  /// 列主序), 与 `Matrix4.storage` 同布局, 故直接构造 `Matrix4`。
  void _drawCurrentBackArea(ui.Canvas canvas, SimPoints pts, ui.Image? image) {
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

    // 铺背景色(纸背底色, 对齐原生 canvas.drawColor(bgMeanColor))。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewSize.width, viewSize.height),
      Paint()..color = bgColor,
    );

    // 沿折痕反射镜像绘制翻起页位图(背面显示反向文字)。
    // 对齐原生 311-326: Householder 反射矩阵 + preTranslate(-control1) + postTranslate(control1)。
    if (image != null) {
      final r = SimGeometry.calcReflection(corner, pts);
      // 构造 4×4 列主序变换矩阵 M = T(anchor) · R · T(-anchor)。
      // R = | 1-2f9²    2f8f9  |
      //     | 2f8f9     1-2f8² |
      final m00 = 1 - 2 * r.f9 * r.f9;
      final m01 = 2 * r.f8 * r.f9;
      final m10 = 2 * r.f8 * r.f9;
      final m11 = 1 - 2 * r.f8 * r.f8;
      // 平移列: M·p = R·(p - anchor) + anchor = R·p + (anchor - R·anchor)。
      final tx = r.anchor.x - (m00 * r.anchor.x + m01 * r.anchor.y);
      final ty = r.anchor.y - (m10 * r.anchor.x + m11 * r.anchor.y);
      // Flutter Canvas.transform 接受列主序 Float64List(16)。
      // 列主序: [m00,m10,m20,m30, m01,m11,m21,m31, m02,m12,m22,m32, m03,m13,m23,m33]
      // 2D 仿射: m00,m01,m10,m11 非零, m22=m33=1, 其余 0。
      final matrix = Float64List.fromList(<double>[
        m00, m10, 0, 0, //
        m01, m11, 0, 0, //
        0,   0,   1, 0, //
        tx,  ty,  0, 1,
      ]);
      canvas.save();
      canvas.transform(matrix);
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
      canvas.drawImageRect(image, src, dst, Paint());
      canvas.restore();
    }

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
