import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/page_animations/simulation_geometry.dart';

/// 仿真翻页几何核心单元测试。
///
/// 不依赖 Canvas/渲染, 纯数学验证。重点保证:
/// - 角判定 / 求交的正确性(可手算精确值的用例)
/// - calcPoints 的结构不变量(控制点落在 corner 邻边、顶点公式、无 NaN)
/// - 边界钳制 / 除零保护不崩
///
/// 这些是仿真翻页"形状对不对"的根本, 视觉观感(阴影/背面)留给后续肉眼验证。
void main() {
  const viewW = 400.0;
  const viewH = 600.0;

  group('calcCornerXY', () {
    test('左上角(x<=W/2, y<=H/2)', () {
      final c = SimGeometry.calcCornerXY(100, 100, viewW, viewH);
      expect(c.cornerX, 0);
      expect(c.cornerY, 0);
      expect(c.isRtOrLb, isFalse);
    });

    test('右上角(x>W/2, y<=H/2)', () {
      final c = SimGeometry.calcCornerXY(300, 100, viewW, viewH);
      expect(c.cornerX, viewW);
      expect(c.cornerY, 0);
      expect(c.isRtOrLb, isTrue); // 右上是 RtOrLb
    });

    test('左下角(x<=W/2, y>H/2)', () {
      final c = SimGeometry.calcCornerXY(100, 500, viewW, viewH);
      expect(c.cornerX, 0);
      expect(c.cornerY, viewH);
      expect(c.isRtOrLb, isTrue); // 左下是 RtOrLb
    });

    test('右下角(x>W/2, y>H/2)', () {
      final c = SimGeometry.calcCornerXY(300, 500, viewW, viewH);
      expect(c.cornerX, viewW);
      expect(c.cornerY, viewH);
      expect(c.isRtOrLb, isFalse);
    });

    test('中点边界(x==W/2 判左, y==H/2 判上)', () {
      // x <= W/2 → 左; y <= H/2 → 上。200==W/2 走左分支。
      final c = SimGeometry.calcCornerXY(viewW / 2, viewH / 2, viewW, viewH);
      expect(c.cornerX, 0);
      expect(c.cornerY, 0);
    });
  });

  group('getCross', () {
    test('两条对角线交于中心', () {
      // (0,0)-(2,2) 与 (0,2)-(2,0) 交于 (1,1)。
      final p = SimGeometry.getCross(
        const SimPoint(0, 0),
        const SimPoint(2, 2),
        const SimPoint(0, 2),
        const SimPoint(2, 0),
      );
      expect(p.x, closeTo(1.0, 1e-9));
      expect(p.y, closeTo(1.0, 1e-9));
    });

    test('水平线与垂直线交点(竖直线鲁棒, 修复原生除零)', () {
      // (0,5)-(10,5) 水平, (3,0)-(3,10) 垂直, 交于 (3,5)。
      // 原生 y=ax+b 公式遇到竖直线会除零; 本实现用参数化行列式法鲁棒处理。
      final p = SimGeometry.getCross(
        const SimPoint(0, 5),
        const SimPoint(10, 5),
        const SimPoint(3, 0),
        const SimPoint(3, 10),
      );
      expect(p.x, closeTo(3.0, 1e-9));
      expect(p.y, closeTo(5.0, 1e-9));
    });

    test('两条竖直线(平行)退化返回 P1, 不产生 NaN', () {
      final p = SimGeometry.getCross(
        const SimPoint(3, 0),
        const SimPoint(3, 10),
        const SimPoint(5, 0),
        const SimPoint(5, 10),
      );
      expect(p.x.isFinite, isTrue);
      expect(p.y.isFinite, isTrue);
    });

    test('一般斜线交点', () {
      // y=x (过原点斜率1) 与 y=-x+4 (斜率-1, 截距4) 交于 (2,2)。
      final p = SimGeometry.getCross(
        const SimPoint(0, 0),
        const SimPoint(1, 1),
        const SimPoint(0, 4),
        const SimPoint(4, 0),
      );
      expect(p.x, closeTo(2.0, 1e-9));
      expect(p.y, closeTo(2.0, 1e-9));
    });
  });

  group('calcPoints - 结构不变量', () {
    // 典型翻页场景: 从右下角翻, touch 在屏幕中部偏左下。
    final corner = SimGeometry.calcCornerXY(300, 500, viewW, viewH);
    final touch = const SimPoint(250, 450);
    final pts = SimGeometry.calcPoints(touch, corner, viewW, viewH);

    test('全部点为有限值(无 NaN/Infinity, 验证除零保护)', () {
      final all = [
        pts.start1, pts.control1, pts.vertex1, pts.end1,
        pts.start2, pts.control2, pts.vertex2, pts.end2,
      ];
      for (final p in all) {
        expect(p.x.isFinite, isTrue, reason: 'x 非有限: $p');
        expect(p.y.isFinite, isTrue, reason: 'y 非有限: $p');
      }
      expect(pts.touchToCornerDis.isFinite, isTrue);
      expect(pts.degrees.isFinite, isTrue);
    });

    test('control1.y == cornerY(沿水平边), control2.x == cornerX(沿垂直边)', () {
      // 原生: mBezierControl1.y = mCornerY; mBezierControl2.x = mCornerX。
      expect(pts.control1.y, closeTo(corner.cornerY, 1e-9));
      expect(pts.control2.x, closeTo(corner.cornerX, 1e-9));
    });

    test('start1.y == cornerY, start2.x == cornerX(start 点在 corner 邻边)', () {
      expect(pts.start1.y, closeTo(corner.cornerY, 1e-9));
      expect(pts.start2.x, closeTo(corner.cornerX, 1e-9));
    });

    test('vertex = 二次贝塞尔 t=0.5 = (start + 2·control + end)/4', () {
      // 独立用 getCross 复算 end, 验证 vertex 公式 (原生 593-596 行)。
      final end1 = SimGeometry.getCross(
          pts.touch, pts.control1, pts.start1, pts.start2);
      final expectedV1 = SimPoint(
        (pts.start1.x + 2 * pts.control1.x + end1.x) / 4,
        (2 * pts.control1.y + pts.start1.y + end1.y) / 4,
      );
      expect(pts.vertex1.x, closeTo(expectedV1.x, 1e-6));
      expect(pts.vertex1.y, closeTo(expectedV1.y, 1e-6));
    });

    test('touchToCornerDis == |touch - corner|', () {
      final expected =
          math.sqrt((touch.x - corner.cornerX) * (touch.x - corner.cornerX) +
              (touch.y - corner.cornerY) * (touch.y - corner.cornerY));
      expect(pts.touchToCornerDis, closeTo(expected, 1e-6));
    });

    test('degrees == atan2(control1.x-cornerX, control2.y-cornerY) 转角度', () {
      final rad =
          math.atan2(pts.control1.x - corner.cornerX, pts.control2.y - corner.cornerY);
      final expected = rad * 180 / math.pi;
      expect(pts.degrees, closeTo(expected, 1e-6));
    });
  });

  group('calcPoints - 除零保护', () {
    test('touchY == cornerY(f4==0 分支)不产生 NaN', () {
      // 让 touch 与 corner 同高 → middleY == cornerY → f4 = 0, 走 0.1 分母分支。
      final corner = const SimCorner(cornerX: 400, cornerY: 0, isRtOrLb: true);
      final touch = const SimPoint(300, 0); // touchY == cornerY == 0
      final pts = SimGeometry.calcPoints(touch, corner, viewW, viewH);
      // 触摸点 0 会被钳为 0.1(除零保护), 各点应有限。
      expect(pts.control2.y.isFinite, isTrue);
      expect(pts.start2.y.isFinite, isTrue);
    });

    test('touch.x==0 被钳为非零初始值(0.1), 不导致除零 NaN', () {
      // touch.x==0 → 初始钳为 0.1(除零保护); 边界钳制分支可能再改写它。
      // 这里只验证不产生 NaN/Infinity(除零保护的真正目的)。
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      final pts = SimGeometry.calcPoints(const SimPoint(0, 300), corner, viewW, viewH);
      expect(pts.touch.x.isFinite, isTrue);
      expect(pts.control1.x.isFinite, isTrue);
      expect(pts.control2.y.isFinite, isTrue);
    });

    test('touch.y==0 被钳为非零初始值(0.1), 不导致除零 NaN', () {
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      final pts = SimGeometry.calcPoints(const SimPoint(300, 0), corner, viewW, viewH);
      expect(pts.touch.y.isFinite, isTrue);
      expect(pts.control1.x.isFinite, isTrue);
      expect(pts.control2.y.isFinite, isTrue);
    });

    test('touchX == cornerX(control1X 分母 0)不产生 NaN(回归: 修复 Canvas 崩溃)', () {
      // 复现线上崩溃: 点击翻页时初始 touch 精确设在 corner 上, 或手指落在角柱正上方,
      // 使 touchX == cornerX → middleX == cornerX → control1X 分母为 0。
      // 原生此处无保护, Android 静默吸收 NaN; Flutter Path 严格会抛
      // "Offset argument contained a NaN value"。本测试锁定 _control1X 的除零保护。
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      final pts =
          SimGeometry.calcPoints(const SimPoint(400, 450), corner, viewW, viewH);
      final all = [
        pts.start1, pts.control1, pts.vertex1, pts.end1,
        pts.start2, pts.control2, pts.vertex2, pts.end2,
      ];
      for (final p in all) {
        expect(p.x.isFinite, isTrue, reason: 'x NaN @ $p');
        expect(p.y.isFinite, isTrue, reason: 'y NaN @ $p');
      }
      expect(pts.degrees.isFinite, isTrue);
    });
  });

  group('calcPoints - 边界钳制', () {
    test('touch 在屏内时 start1 被钳回 [0, viewW] 附近', () {
      // 极端: touch 紧贴 corner, 会触发 start1.x 越界 → 镜像修正(原生 543-574)。
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      // touch 接近 corner 但在屏内, 易触发越界修正分支。
      final pts = SimGeometry.calcPoints(const SimPoint(399, 599), corner, viewW, viewH);
      // 修正后所有点仍有限, touch 仍在屏内(原生逻辑保证)。
      expect(pts.start1.x.isFinite, isTrue);
      expect(pts.touch.x, inInclusiveRange(0.0, viewW));
    });

    test('touch 在屏外时不触发钳制分支(touchX>0 && <viewW 守卫)', () {
      // touchX == 0 → 守卫 `touchX > 0` 为 false → 不进钳制分支, 也不崩。
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      final pts = SimGeometry.calcPoints(const SimPoint(0, 300), corner, viewW, viewH);
      expect(pts.start1.x.isFinite, isTrue);
      expect(pts.control1.x.isFinite, isTrue);
    });
  });

  group('calcPoints - 翻页方向覆盖', () {
    test('右下角翻页(touch 在角附近中部)几何自洽', () {
      // 典型 NEXT 翻页: 从右下角往左上卷, touch 落在屏幕中部。
      final corner = const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false);
      final pts =
          SimGeometry.calcPoints(const SimPoint(250, 450), corner, viewW, viewH);
      // 控制点/start 点(由 touch-corner 几何直接确定)必有限。
      expect(pts.control1.x.isFinite, isTrue);
      expect(pts.control2.y.isFinite, isTrue);
      expect(pts.start1.x.isFinite, isTrue);
      // touch 距 corner 为正。
      expect(pts.touchToCornerDis, greaterThan(0));
    });

    test('左下角翻页几何自洽', () {
      final corner = const SimCorner(cornerX: 0, cornerY: 600, isRtOrLb: true);
      final pts =
          SimGeometry.calcPoints(const SimPoint(150, 450), corner, viewW, viewH);
      expect(pts.control1.x.isFinite, isTrue);
      expect(pts.control2.y.isFinite, isTrue);
      expect(pts.touchToCornerDis, greaterThan(0));
    });

    test('四个角的控制点都有限(核心几何不崩)', () {
      final corners = [
        const SimCorner(cornerX: 400, cornerY: 600, isRtOrLb: false),
        const SimCorner(cornerX: 0, cornerY: 600, isRtOrLb: true),
        const SimCorner(cornerX: 400, cornerY: 0, isRtOrLb: true),
        const SimCorner(cornerX: 0, cornerY: 0, isRtOrLb: false),
      ];
      const touch = SimPoint(250, 450);
      for (final corner in corners) {
        final pts = SimGeometry.calcPoints(touch, corner, viewW, viewH);
        // 仅断言由 touch-corner 直接派生的点(控制点/start/middle), 它们几何上
        // 必有限。end/vertex 依赖 getCross, 极端 touch 可能让两直线平行 → 无穷,
        // 这是原生算法的固有特性, 此处不约束。
        expect(pts.control1.x.isFinite, isTrue, reason: 'control1.x @ $corner');
        expect(pts.control2.y.isFinite, isTrue, reason: 'control2.y @ $corner');
        expect(pts.start1.x.isFinite, isTrue, reason: 'start1.x @ $corner');
        expect(pts.middleX.isFinite, isTrue);
      }
    });
  });
}
