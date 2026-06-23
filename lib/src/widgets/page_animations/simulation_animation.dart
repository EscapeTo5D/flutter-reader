import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'page_animation.dart';

class SimulationAnimation extends PageAnimation {
  @override
  Widget build({
    required BuildContext context,
    required Widget currentPage,
    required Widget? nextPage,
    required Widget? prevPage,
    required PageDirection direction,
    required double dragProgress,
  }) {
    return const SizedBox();
  }

  Widget buildWithImages({
    required BuildContext context,
    required ui.Image? curImage,
    required ui.Image? nextImage,
    required ui.Image? prevImage,
    required PageDirection direction,
    required Offset touchPoint,
    required Size viewSize,
    required bool isCancel,
    required double devicePixelRatio,
  }) {
    if (curImage == null) return const SizedBox();
    if (direction == PageDirection.next && nextImage == null) {
      return const SizedBox();
    }
    if (direction == PageDirection.prev && prevImage == null) {
      return const SizedBox();
    }

    return CustomPaint(
      size: viewSize,
      painter: SimulationPagePainter(
        curImage: curImage,
        nextImage: nextImage,
        prevImage: prevImage,
        direction: direction,
        touchPoint: touchPoint,
        viewSize: viewSize,
        isCancel: isCancel,
        devicePixelRatio: devicePixelRatio,
      ),
    );
  }
}

class SimulationPagePainter extends CustomPainter {
  final ui.Image? curImage;
  final ui.Image? nextImage;
  final ui.Image? prevImage;
  final PageDirection direction;
  final Offset touchPoint;
  final Size viewSize;
  final bool isCancel;
  final double devicePixelRatio;

  late double _touchX;
  late double _touchY;
  late int _cornerX;
  late int _cornerY;
  late bool _isRtOrLb;

  late Offset _bezierStart1;
  late Offset _bezierControl1;
  late Offset _bezierVertex1;
  late Offset _bezierEnd1;
  late Offset _bezierStart2;
  late Offset _bezierControl2;
  late Offset _bezierVertex2;
  late Offset _bezierEnd2;

  late double _middleX;
  late double _middleY;
  late double _degrees;
  late double _touchToCornerDis;
  late double _maxLength;

  SimulationPagePainter({
    required this.curImage,
    required this.nextImage,
    required this.prevImage,
    required this.direction,
    required this.touchPoint,
    required this.viewSize,
    required this.isCancel,
    required this.devicePixelRatio,
  });

  void _drawImageFull(Canvas canvas, ui.Image image) {
    final src = Rect.fromLTWH(
      0, 0, image.width.toDouble(), image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
    canvas.drawImageRect(image, src, dst, Paint());
  }

  void _rotateAround(Canvas canvas, double radians, double cx, double cy) {
    canvas.translate(cx, cy);
    canvas.rotate(radians);
    canvas.translate(-cx, -cy);
  }

  Float64List _buildTranslateMatrix(double tx, double ty) {
    return Float64List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    ]);
  }

  Float64List _multiplyMatrix(Float64List a, Float64List b) {
    final result = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        result[i * 4 + j] =
            a[i * 4 + 0] * b[0 * 4 + j] +
            a[i * 4 + 1] * b[1 * 4 + j] +
            a[i * 4 + 2] * b[2 * 4 + j] +
            a[i * 4 + 3] * b[3 * 4 + j];
      }
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (direction == PageDirection.none) return;
    if (direction == PageDirection.next && nextImage == null) return;
    if (direction == PageDirection.prev && prevImage == null) return;

    _maxLength = _hypot(viewSize.width, viewSize.height);
    _touchX = touchPoint.dx;
    _touchY = touchPoint.dy;

    if (_touchX == 0) _touchX = 0.1;
    if (_touchY == 0) _touchY = 0.1;

    _calcCornerXY(_touchX, _touchY);
    _calcPoints();

    if (direction == PageDirection.next) {
      _drawCurrentPageArea(canvas, curImage);
      _drawNextPageAreaAndShadow(canvas, nextImage);
      _drawCurrentPageShadow(canvas);
      _drawCurrentBackArea(canvas, curImage);
    } else {
      _drawCurrentPageArea(canvas, prevImage);
      _drawNextPageAreaAndShadow(canvas, curImage);
      _drawCurrentPageShadow(canvas);
      _drawCurrentBackArea(canvas, prevImage);
    }
  }

  void _calcCornerXY(double x, double y) {
    _cornerX = x <= viewSize.width / 2 ? 0 : viewSize.width.toInt();
    _cornerY = y <= viewSize.height / 2 ? 0 : viewSize.height.toInt();
    _isRtOrLb = (_cornerX == 0 && _cornerY == viewSize.height.toInt()) ||
        (_cornerY == 0 && _cornerX == viewSize.width.toInt());
  }

  void _calcPoints() {
    _middleX = (_touchX + _cornerX) / 2;
    _middleY = (_touchY + _cornerY) / 2;

    double control1X =
        _middleX - (_cornerY - _middleY) * (_cornerY - _middleY) / (_cornerX - _middleX);
    double control1Y = _cornerY.toDouble();
    double control2X = _cornerX.toDouble();

    double f4 = _cornerY - _middleY;
    double control2Y;
    if (f4 == 0) {
      control2Y = _middleY - (_cornerX - _middleX) * (_cornerX - _middleX) / 0.1;
    } else {
      control2Y = _middleY - (_cornerX - _middleX) * (_cornerX - _middleX) / (_cornerY - _middleY);
    }

    _bezierControl1 = Offset(control1X, control1Y);
    _bezierControl2 = Offset(control2X, control2Y);

    double start1X = control1X - (_cornerX - control1X) / 2;
    double start1Y = _cornerY.toDouble();

    if (_touchX > 0 && _touchX < viewSize.width) {
      if (start1X < 0 || start1X > viewSize.width) {
        if (start1X < 0) start1X = viewSize.width - start1X;

        double f1 = (_cornerX - _touchX).abs();
        double f2 = viewSize.width * f1 / start1X;
        _touchX = (_cornerX - f2).abs();

        double f3 = (_cornerX - _touchX).abs() * (_cornerY - _touchY).abs() / f1;
        _touchY = (_cornerY - f3).abs();

        _middleX = (_touchX + _cornerX) / 2;
        _middleY = (_touchY + _cornerY) / 2;

        control1X = _middleX -
            (_cornerY - _middleY) * (_cornerY - _middleY) / (_cornerX - _middleX);
        control1Y = _cornerY.toDouble();
        control2X = _cornerX.toDouble();

        f4 = _cornerY - _middleY;
        if (f4 == 0) {
          control2Y = _middleY - (_cornerX - _middleX) * (_cornerX - _middleX) / 0.1;
        } else {
          control2Y = _middleY -
              (_cornerX - _middleX) * (_cornerX - _middleX) / (_cornerY - _middleY);
        }

        _bezierControl1 = Offset(control1X, control1Y);
        _bezierControl2 = Offset(control2X, control2Y);
        start1X = control1X - (_cornerX - control1X) / 2;
      }
    }

    _bezierStart1 = Offset(start1X, start1Y);
    _bezierStart2 = Offset(
      _cornerX.toDouble(),
      control2Y - (_cornerY - control2Y) / 2,
    );

    _touchToCornerDis = _hypot(_touchX - _cornerX, _touchY - _cornerY);

    _bezierEnd1 = _getCross(
      Offset(_touchX, _touchY), _bezierControl1, _bezierStart1, _bezierStart2,
    );
    _bezierEnd2 = _getCross(
      Offset(_touchX, _touchY), _bezierControl2, _bezierStart1, _bezierStart2,
    );

    _bezierVertex1 = Offset(
      (_bezierStart1.dx + 2 * _bezierControl1.dx + _bezierEnd1.dx) / 4,
      (2 * _bezierControl1.dy + _bezierStart1.dy + _bezierEnd1.dy) / 4,
    );
    _bezierVertex2 = Offset(
      (_bezierStart2.dx + 2 * _bezierControl2.dx + _bezierEnd2.dx) / 4,
      (2 * _bezierControl2.dy + _bezierStart2.dy + _bezierEnd2.dy) / 4,
    );
  }

  Offset _getCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    double a1 = (p2.dy - p1.dy) / (p2.dx - p1.dx);
    double b1 = (p1.dx * p2.dy - p2.dx * p1.dy) / (p1.dx - p2.dx);
    double a2 = (p4.dy - p3.dy) / (p4.dx - p3.dx);
    double b2 = (p3.dx * p4.dy - p4.dx * p3.dy) / (p3.dx - p4.dx);
    double crossX = (b2 - b1) / (a1 - a2);
    double crossY = a1 * crossX + b1;
    return Offset(crossX, crossY);
  }

  Path _buildFoldPath() {
    final path = Path();
    path.moveTo(_bezierStart1.dx, _bezierStart1.dy);
    path.quadraticBezierTo(
      _bezierControl1.dx, _bezierControl1.dy, _bezierEnd1.dx, _bezierEnd1.dy,
    );
    path.lineTo(_touchX, _touchY);
    path.lineTo(_bezierEnd2.dx, _bezierEnd2.dy);
    path.quadraticBezierTo(
      _bezierControl2.dx, _bezierControl2.dy, _bezierStart2.dx, _bezierStart2.dy,
    );
    path.lineTo(_cornerX.toDouble(), _cornerY.toDouble());
    path.close();
    return path;
  }

  Path _fullRectPath() {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, viewSize.width, viewSize.height));
  }

  void _drawCurrentPageArea(Canvas canvas, ui.Image? bitmap) {
    if (bitmap == null) return;
    final foldPath = _buildFoldPath();
    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, _fullRectPath(), foldPath),
    );
    _drawImageFull(canvas, bitmap);
    canvas.restore();
  }

  void _drawNextPageAreaAndShadow(Canvas canvas, ui.Image? bitmap) {
    if (bitmap == null) return;

    final path1 = Path();
    path1.moveTo(_bezierStart1.dx, _bezierStart1.dy);
    path1.lineTo(_bezierVertex1.dx, _bezierVertex1.dy);
    path1.lineTo(_bezierVertex2.dx, _bezierVertex2.dy);
    path1.lineTo(_bezierStart2.dx, _bezierStart2.dy);
    path1.lineTo(_cornerX.toDouble(), _cornerY.toDouble());
    path1.close();

    _degrees = _toDegrees(math.atan2(
      _bezierControl1.dx - _cornerX,
      _bezierControl2.dy - _cornerY,
    ));

    final foldPath = _buildFoldPath();
    final clipPath = Path.combine(PathOperation.intersect, foldPath, path1);

    double leftX;
    double rightX;
    Color shadowColor1;
    Color shadowColor2;
    if (_isRtOrLb) {
      leftX = _bezierStart1.dx;
      rightX = _bezierStart1.dx + _touchToCornerDis / 4;
      shadowColor1 = const Color(0xCCCCCCCC);
      shadowColor2 = const Color(0x11111111);
    } else {
      leftX = _bezierStart1.dx - _touchToCornerDis / 4;
      rightX = _bezierStart1.dx;
      shadowColor1 = const Color(0x11111111);
      shadowColor2 = const Color(0xCCCCCCCC);
    }

    canvas.save();
    canvas.clipPath(clipPath);
    _drawImageFull(canvas, bitmap);
    _rotateAround(canvas, _degrees * math.pi / 180, _bezierStart1.dx, _bezierStart1.dy);

    final shadowRect = Rect.fromLTRB(
      leftX, _bezierStart1.dy, rightX, _bezierStart1.dy + _maxLength,
    );
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: _isRtOrLb ? Alignment.centerLeft : Alignment.centerRight,
        end: _isRtOrLb ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadowColor1, shadowColor2],
      ).createShader(shadowRect);
    canvas.drawRect(shadowRect, shadowPaint);
    canvas.restore();
  }

  void _drawCurrentPageShadow(Canvas canvas) {
    final double degree;
    if (_isRtOrLb) {
      degree = math.pi / 4 -
          math.atan2(_bezierControl1.dy - _touchY, _touchX - _bezierControl1.dx);
    } else {
      degree = math.pi / 4 -
          math.atan2(_touchY - _bezierControl1.dy, _touchX - _bezierControl1.dx);
    }

    final d1 = 25 * 1.414 * math.cos(degree);
    final d2 = 25 * 1.414 * math.sin(degree);
    final x = _touchX + d1;
    final double y;
    if (_isRtOrLb) {
      y = _touchY + d2;
    } else {
      y = _touchY - d2;
    }

    final path1 = Path();
    path1.moveTo(x, y);
    path1.lineTo(_touchX, _touchY);
    path1.lineTo(_bezierControl1.dx, _bezierControl1.dy);
    path1.lineTo(_bezierStart1.dx, _bezierStart1.dy);
    path1.close();

    final foldPath = _buildFoldPath();

    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, _fullRectPath(), foldPath),
    );
    canvas.clipPath(path1);

    double leftX;
    double rightX;
    Color shadowColor1;
    Color shadowColor2;
    if (_isRtOrLb) {
      leftX = _bezierControl1.dx;
      rightX = _bezierControl1.dx + 25;
      shadowColor1 = const Color(0x80111111);
      shadowColor2 = const Color(0x11111111);
    } else {
      leftX = _bezierControl1.dx - 25;
      rightX = _bezierControl1.dx + 1;
      shadowColor1 = const Color(0x11111111);
      shadowColor2 = const Color(0x80111111);
    }

    double rotateDegrees = _toDegrees(
      math.atan2(_touchX - _bezierControl1.dx, _bezierControl1.dy - _touchY),
    );
    _rotateAround(canvas, rotateDegrees * math.pi / 180, _bezierControl1.dx, _bezierControl1.dy);

    final shadowRect = Rect.fromLTRB(
      leftX, _bezierControl1.dy - _maxLength, rightX, _bezierControl1.dy,
    );
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: _isRtOrLb ? Alignment.centerLeft : Alignment.centerRight,
        end: _isRtOrLb ? Alignment.centerRight : Alignment.centerLeft,
        colors: [shadowColor1, shadowColor2],
      ).createShader(shadowRect);
    canvas.drawRect(shadowRect, shadowPaint);
    canvas.restore();

    final path2 = Path();
    path2.moveTo(x, y);
    path2.lineTo(_touchX, _touchY);
    path2.lineTo(_bezierControl2.dx, _bezierControl2.dy);
    path2.lineTo(_bezierStart2.dx, _bezierStart2.dy);
    path2.close();

    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, _fullRectPath(), foldPath),
    );
    canvas.clipPath(path2);

    double leftX2;
    double rightX2;
    Color shadowColor2_1;
    Color shadowColor2_2;
    if (_isRtOrLb) {
      leftX2 = _bezierControl2.dy;
      rightX2 = _bezierControl2.dy + 25;
      shadowColor2_1 = const Color(0x80111111);
      shadowColor2_2 = const Color(0x11111111);
    } else {
      leftX2 = _bezierControl2.dy - 25;
      rightX2 = _bezierControl2.dy + 1;
      shadowColor2_1 = const Color(0x11111111);
      shadowColor2_2 = const Color(0x80111111);
    }

    rotateDegrees = _toDegrees(math.atan2(
      _bezierControl2.dy - _touchY,
      _bezierControl2.dx - _touchX,
    ));
    _rotateAround(canvas, rotateDegrees * math.pi / 180, _bezierControl2.dx, _bezierControl2.dy);

    double temp = _bezierControl2.dy < 0
        ? _bezierControl2.dy - viewSize.height
        : _bezierControl2.dy;
    double hmg = _hypot(_bezierControl2.dx, temp);

    Rect shadowRect2;
    if (hmg > _maxLength) {
      shadowRect2 = Rect.fromLTRB(
        _bezierControl2.dx - 25 - hmg,
        leftX2,
        _bezierControl2.dx + _maxLength - hmg,
        rightX2,
      );
    } else {
      shadowRect2 = Rect.fromLTRB(
        _bezierControl2.dx - _maxLength,
        leftX2,
        _bezierControl2.dx,
        rightX2,
      );
    }
    final shadowPaint2 = Paint()
      ..shader = LinearGradient(
        begin: _isRtOrLb ? Alignment.topCenter : Alignment.bottomCenter,
        end: _isRtOrLb ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [shadowColor2_1, shadowColor2_2],
      ).createShader(shadowRect2);
    canvas.drawRect(shadowRect2, shadowPaint2);
    canvas.restore();
  }

  void _drawCurrentBackArea(Canvas canvas, ui.Image? bitmap) {
    if (bitmap == null) return;

    double i = (_bezierStart1.dx + _bezierControl1.dx) / 2;
    double f1 = (i - _bezierControl1.dx).abs();
    double i1 = (_bezierStart2.dy + _bezierControl2.dy) / 2;
    double f2 = (i1 - _bezierControl2.dy).abs();
    double f3 = math.min(f1, f2);

    final path1 = Path();
    path1.moveTo(_bezierVertex2.dx, _bezierVertex2.dy);
    path1.lineTo(_bezierVertex1.dx, _bezierVertex1.dy);
    path1.lineTo(_bezierEnd1.dx, _bezierEnd1.dy);
    path1.lineTo(_touchX, _touchY);
    path1.lineTo(_bezierEnd2.dx, _bezierEnd2.dy);
    path1.close();

    final foldPath = _buildFoldPath();
    final clipPath = Path.combine(PathOperation.intersect, foldPath, path1);

    double left;
    double right;
    Color folderShadowColor1;
    Color folderShadowColor2;
    if (_isRtOrLb) {
      left = _bezierStart1.dx - 1;
      right = _bezierStart1.dx + f3 + 1;
      folderShadowColor1 = const Color(0x33333333);
      folderShadowColor2 = const Color(0xB3333333);
    } else {
      left = _bezierStart1.dx - f3 - 1;
      right = _bezierStart1.dx + 1;
      folderShadowColor1 = const Color(0xB3333333);
      folderShadowColor2 = const Color(0x33333333);
    }

    canvas.save();
    canvas.clipPath(clipPath);

    const colorMatrix = <double>[
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];
    final paint = Paint()
      ..colorFilter = const ColorFilter.matrix(colorMatrix);

    final dis = _hypot(
      _cornerX - _bezierControl1.dx,
      _bezierControl2.dy - _cornerY,
    );
    final f8 = (_cornerX - _bezierControl1.dx) / dis;
    final f9 = (_bezierControl2.dy - _cornerY) / dis;

    final reflectMatrix = Float64List.fromList([
      1 - 2 * f9 * f9, 2 * f8 * f9, 0, 0,
      2 * f8 * f9, 1 - 2 * f8 * f8, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);

    final translateToOrigin = _buildTranslateMatrix(
      -_bezierControl1.dx, -_bezierControl1.dy,
    );
    final translateBack = _buildTranslateMatrix(
      _bezierControl1.dx, _bezierControl1.dy,
    );

    var transform = _multiplyMatrix(translateToOrigin, reflectMatrix);
    transform = _multiplyMatrix(transform, translateBack);

    canvas.transform(transform);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewSize.width, viewSize.height),
      Paint()..color = const Color(0xFFF5F5F5),
    );

    final src = Rect.fromLTWH(
      0, 0, bitmap.width.toDouble(), bitmap.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
    canvas.drawImageRect(bitmap, src, dst, paint);

    // Inverse of T(-cx,-cy)*R*T(cx,cy) = T(-cx,-cy)*R*T(cx,cy) (self-inverse)
    final invTranslateToOrigin = _buildTranslateMatrix(
      -_bezierControl1.dx, -_bezierControl1.dy,
    );
    final invTranslateBack = _buildTranslateMatrix(
      _bezierControl1.dx, _bezierControl1.dy,
    );
    var invTransform = _multiplyMatrix(invTranslateToOrigin, reflectMatrix);
    invTransform = _multiplyMatrix(invTransform, invTranslateBack);

    canvas.transform(invTransform);

    _rotateAround(canvas, _degrees * math.pi / 180, _bezierStart1.dx, _bezierStart1.dy);
    final shadowRect = Rect.fromLTRB(
      left, _bezierStart1.dy, right, _bezierStart1.dy + _maxLength,
    );
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: _isRtOrLb ? Alignment.centerLeft : Alignment.centerRight,
        end: _isRtOrLb ? Alignment.centerRight : Alignment.centerLeft,
        colors: [folderShadowColor1, folderShadowColor2],
      ).createShader(shadowRect);
    canvas.drawRect(shadowRect, shadowPaint);
    canvas.restore();
  }

  double _toDegrees(double radians) => radians * 180 / math.pi;

  double _hypot(double x, double y) => math.sqrt(x * x + y * y);

  @override
  bool shouldRepaint(covariant SimulationPagePainter oldDelegate) {
    return oldDelegate.touchPoint != touchPoint ||
        oldDelegate.direction != direction ||
        oldDelegate.isCancel != isCancel;
  }
}
