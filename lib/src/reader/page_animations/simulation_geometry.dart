import 'dart:math' as math;

/// 仿真翻页的纯数学几何核心(无 Canvas 依赖, 可单测)。
///
/// 逐行翻译原生 legado `SimulationPageDelegate.kt` 的贝塞尔卷曲算法
/// (`calcCornerXY` / `calcPoints` / `getCross`)。核心思想: **touch 到 corner
/// 的垂直平分线作为折痕, 折痕与 corner 两条邻边的交点即两段二次贝塞尔的控制点**。
/// 这是经典"折纸翻页"模型, 视觉修饰(投影/高光/背面反射)都在 [SimulationPainter]
/// 里基于这里算出的点绘制。
///
/// 本文件不依赖 Flutter 的 `Canvas`/`Path`, 仅用 `dart:math`, 方便单元测试。
/// 坐标系与原生一致: 原点左上, x 向右, y 向下。

/// 一个二维点(对齐原生 `android.graphics.PointF`)。
///
/// 不复用 `Offset` 是为了让本文件保持无 Flutter 依赖、可纯 Dart 测试。
class SimPoint {
  final double x;
  final double y;
  const SimPoint(this.x, this.y);

  @override
  String toString() => 'SimPoint(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is SimPoint && (x - other.x).abs() < 1e-9 && (y - other.y).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 拖拽对应的页角(翻页卷曲朝向由它决定)。
///
/// 对齐原生 `calcCornerXY`: `cornerX` ∈ {0, viewWidth}, `cornerY` ∈ {0, viewHeight}。
/// [isRtOrLb] 标记"右上或左下"对角方向(左下角或右上角), 原生用它决定投影/阴影
/// 渐变方向(LR 还是 RL)。
class SimCorner {
  final double cornerX;
  final double cornerY;
  final bool isRtOrLb;

  const SimCorner({
    required this.cornerX,
    required this.cornerY,
    required this.isRtOrLb,
  });
}

/// `calcPoints` 的输出: 翻页卷曲边的全部贝塞尔点 + 派生量。
///
/// 命名与原生 `SimulationPageDelegate` 字段一一对应:
/// - `start1/control1/vertex1/end1` —— 第一段二次贝塞尔(沿 cornerY 水平边)
/// - `start2/control2/vertex2/end2` —— 第二段二次贝塞尔(沿 cornerX 垂直边)
/// - 两段共用 touch 点为折痕顶点
class SimPoints {
  /// 第一段贝塞尔起点(在 y=cornerY 水平边上)。
  final SimPoint start1;

  /// 第一段贝塞尔控制点。
  final SimPoint control1;

  /// 第一段贝塞尔 t=0.5 处顶点(用于绘制背面多边形与投影顶点)。
  final SimPoint vertex1;

  /// 第一段贝塞尔终点(touch 与 control1 连线 ∩ start1-start2 直线)。
  final SimPoint end1;

  /// 第二段贝塞尔起点(在 x=cornerX 垂直边上)。
  final SimPoint start2;

  /// 第二段贝塞尔控制点。
  final SimPoint control2;

  /// 第二段贝塞尔 t=0.5 处顶点。
  final SimPoint vertex2;

  /// 第二段贝塞尔终点。
  final SimPoint end2;

  /// touch 与 corner 的中点(中间量)。
  final double middleX;
  final double middleY;

  /// touch 到 corner 的距离(用于投影宽度 = 触距 / 4)。
  final double touchToCornerDis;

  /// 投影旋转角(度), 由 control1-corner 与 control2-corner 方向决定。
  final double degrees;

  /// 边界钳制可能修正后的 touch 点(原生 `calcPoints` 543-574 行可能改写 touch)。
  final SimPoint touch;

  const SimPoints({
    required this.start1,
    required this.control1,
    required this.vertex1,
    required this.end1,
    required this.start2,
    required this.control2,
    required this.vertex2,
    required this.end2,
    required this.middleX,
    required this.middleY,
    required this.touchToCornerDis,
    required this.degrees,
    required this.touch,
  });
}

/// 仿真翻页几何计算。
///
/// 所有方法为静态, 无状态, 输入 → 输出, 易于测试。
class SimGeometry {
  SimGeometry._();

  /// 计算拖拽点 [x],[y] 对应的页角。
  ///
  /// 对齐原生 `calcCornerXY`(`SimulationPageDelegate.kt:513-518`):
  /// - `x <= viewW/2` → 左角(cornerX=0), 否则右角(cornerX=viewW)
  /// - `y <= viewH/2` → 上角(cornerY=0), 否则下角(cornerY=viewH)
  /// - `isRtOrLb` = (左下角) 或 (右上角)
  ///
  /// [viewW]/[viewH] 为页面可视宽高。
  static SimCorner calcCornerXY(double x, double y, double viewW, double viewH) {
    final cornerX = x <= viewW / 2 ? 0.0 : viewW;
    final cornerY = y <= viewH / 2 ? 0.0 : viewH;
    final isRtOrLb = (cornerX == 0 && cornerY == viewH) ||
        (cornerY == 0 && cornerX == viewW);
    return SimCorner(cornerX: cornerX, cornerY: cornerY, isRtOrLb: isRtOrLb);
  }

  /// 求直线 P1P2 与直线 P3P4 的交点。
  ///
  /// 原生 `getCross`(`SimulationPageDelegate.kt:602-612`) 用 y=ax+b 通式, **但当某条
  /// 直线为竖直线(x 恒定, 斜率无穷)时会除零产生 NaN/Inf**。仿真翻页里 touch→control1
  /// 可能恰好竖直(touchX == control1.x), 故这里改用**参数化行列式法**(对竖直线鲁棒):
  /// ```
  /// 解 P1 + t·(P2−P1) = P3 + u·(P4−P3):
  ///   d  = (P2.x−P1.x)·(P4.y−P3.y) − (P2.y−P1.y)·(P4.x−P3.x)   // 行列式
  ///   t  = ((P3.x−P1.x)·(P4.y−P3.y) − (P3.y−P1.y)·(P4.x−P3.x)) / d
  ///   cross = P1 + t·(P2−P1)
  /// ```
  /// 两直线平行(含重合)时 d=0 → 返回 P1(退化, 不会发生在仿真翻页的正常几何里,
  /// 因为 start1-start2 与 touch-control 永远相交)。
  ///
  /// 非竖直/非平行场景下, 本实现与原生 y=ax+b 公式数学等价。
  static SimPoint getCross(SimPoint p1, SimPoint p2, SimPoint p3, SimPoint p4) {
    final dx12 = p2.x - p1.x;
    final dy12 = p2.y - p1.y;
    final dx34 = p4.x - p3.x;
    final dy34 = p4.y - p3.y;
    final d = dx12 * dy34 - dy12 * dx34; // 行列式; 0 表示平行。
    if (d == 0) {
      // 平行/重合退化: 返回 P1 占位(避免 NaN; 正常几何不会进此分支)。
      return p1;
    }
    final t = ((p3.x - p1.x) * dy34 - (p3.y - p1.y) * dx34) / d;
    return SimPoint(p1.x + t * dx12, p1.y + t * dy12);
  }

  /// 由当前 [touch] 与 [corner] 计算全部贝塞尔点。
  ///
  /// 对齐原生 `calcPoints`(`SimulationPageDelegate.kt:520-597`)。步骤:
  /// 1. touch-corner 中点 → 折痕(垂直平分线)
  /// 2. 折痕与 corner 两条邻边(水平 y=cornerY、垂直 x=cornerX)的交点 = 两个控制点
  /// 3. 控制点关于折痕反射到 corner 边上 = 两个 start 点
  /// 4. **边界钳制**: 若 start1.x 越出 [0, viewW], 按 touch 反射把 touch 拉回,
  ///    重算控制点(原生 543-574 行) —— 防止卷曲到边缘时变形
  /// 5. end 点 = (touch-control 连线) ∩ (start1-start2 直线)
  /// 6. vertex 点 = 二次贝塞尔 t=0.5 处 = (start + 2·control + end) / 4
  /// 7. degrees = atan2(control1.x - cornerX, control2.y - cornerY) 转角度(投影方向)
  ///
  /// 除零保护(对齐原生):
  /// - `f4 = cornerY - middleY == 0` 时用 0.1 作分母(原生 532-538 行)
  /// - `viewW`/`viewH` 必须 > 0
  static SimPoints calcPoints(
    SimPoint touch,
    SimCorner corner,
    double viewW,
    double viewH,
  ) {
    // ⚠️ 不让 touch 为 0, 否则点计算会有问题(原生注释 + 0.1 初始化)。
    var touchX = touch.x == 0 ? 0.1 : touch.x;
    var touchY = touch.y == 0 ? 0.1 : touch.y;
    final cornerX = corner.cornerX;
    final cornerY = corner.cornerY;

    var middleX = (touchX + cornerX) / 2;
    var middleY = (touchY + cornerY) / 2;

    var control1X = _control1X(middleX, middleY, cornerX, cornerY);
    // control1 沿水平边 y=cornerY。
    // control2 沿垂直边 x=cornerX。
    final control2X = cornerX;
    var control2Y = _control2Y(middleX, middleY, cornerX, cornerY);

    var start1X = control1X - (cornerX - control1X) / 2;

    // 固定左边上下两个点: 当 start1 越界时镜像修正 touch(原生 543-574 行)。
    // 防止翻页卷曲到屏幕边缘时贝塞尔形状扭曲。
    if (touchX > 0 && touchX < viewW) {
      if (start1X < 0 || start1X > viewW) {
        if (start1X < 0) {
          start1X = viewW - start1X;
        }
        final f1 = (cornerX - touchX).abs();
        final f2 = viewW * f1 / start1X;
        touchX = (cornerX - f2).abs();

        final f3 = (cornerX - touchX).abs() * (cornerY - touchY).abs() / f1;
        touchY = (cornerY - f3).abs();

        middleX = (touchX + cornerX) / 2;
        middleY = (touchY + cornerY) / 2;

        control1X = _control1X(middleX, middleY, cornerX, cornerY);
        control2Y = _control2Y(middleX, middleY, cornerX, cornerY);

        start1X = control1X - (cornerX - control1X) / 2;
      }
    }
    final start1Y = cornerY;
    final control1Y = cornerY;

    final start2X = cornerX;
    final start2Y = control2Y - (cornerY - control2Y) / 2;

    final touchToCornerDis =
        math.sqrt((touchX - cornerX) * (touchX - cornerX) +
            (touchY - cornerY) * (touchY - cornerY));

    final start1 = SimPoint(start1X, start1Y);
    final start2 = SimPoint(start2X, start2Y);
    final control1 = SimPoint(control1X, control1Y);
    final control2 = SimPoint(control2X, control2Y);
    final touchPoint = SimPoint(touchX, touchY);

    final end1 = getCross(touchPoint, control1, start1, start2);
    final end2 = getCross(touchPoint, control2, start1, start2);

    // 二次贝塞尔 B(0.5) = (P0 + 2·P1 + P2) / 4。
    final vertex1 = SimPoint(
      (start1.x + 2 * control1.x + end1.x) / 4,
      (2 * control1.y + start1.y + end1.y) / 4,
    );
    final vertex2 = SimPoint(
      (start2.x + 2 * control2.x + end2.x) / 4,
      (2 * control2.y + start2.y + end2.y) / 4,
    );

    // 投影旋转角: atan2(control1.x - cornerX, control2.y - cornerY) → 度。
    // 注意原生参数顺序: (x 分量, y 分量) 对应 atan2 的 (y, x) 反着写,
    // 这里照搬原生 `atan2(control1.x - cornerX, control2.y - cornerY)`。
    final radians = math.atan2(control1.x - cornerX, control2.y - cornerY);
    final degrees = radians * 180 / math.pi;

    return SimPoints(
      start1: start1,
      control1: control1,
      vertex1: vertex1,
      end1: end1,
      start2: start2,
      control2: control2,
      vertex2: vertex2,
      end2: end2,
      middleX: middleX,
      middleY: middleY,
      touchToCornerDis: touchToCornerDis,
      degrees: degrees,
      touch: touchPoint,
    );
  }

  /// 计算 control2.y(原生 `calcPoints` 531-538 行, 在主流程和边界钳制分支各出现一次)。
  ///
  /// `control2.y = middleY - (cornerX - middleX)² / (cornerY - middleY)`，
  /// 当 `cornerY == middleY`(分母 0)时用 0.1 作分母(除零保护, 对齐原生 533 行)。
  static double _control2Y(
    double middleX,
    double middleY,
    double cornerX,
    double cornerY,
  ) {
    final dx = cornerX - middleX;
    final denom = cornerY - middleY;
    if (denom == 0) {
      return middleY - dx * dx / 0.1;
    }
    return middleY - dx * dx / denom;
  }

  /// 计算 control1.x(原生 `calcPoints` 526-528 行)。
  ///
  /// `control1.x = middleX - (cornerY - middleY)² / (cornerX - middleX)`。
  /// **原生此处无除零保护**, 但当 `touchX == cornerX`(如点击翻页把初始 touch 精确
  /// 设在 corner 上、或手指落在角柱正上方)时 `middleX == cornerX` → 分母 0 → Infinity/NaN,
  /// 会传染到 start1/end1/vertex1/degrees, 最终 Canvas 抛
  /// `Offset argument contained a NaN value`。
  ///
  /// Flutter `Path` 对 NaN 比 Android 严格(Android 静默吸收), 故这里补保护:
  /// 分母 0 时用 0.1(对齐 `_control2Y` 的保护策略)。代价: touch 恰在 corner 正上/下时
  /// 卷曲形状有微小偏差, 但该位置本就是退化情形(卷曲量为 0), 无视觉影响。
  static double _control1X(
    double middleX,
    double middleY,
    double cornerX,
    double cornerY,
  ) {
    final dy = cornerY - middleY;
    final denom = cornerX - middleX;
    if (denom == 0) {
      return middleX - dy * dy / 0.1;
    }
    return middleX - dy * dy / denom;
  }
}
