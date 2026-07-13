import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/src/reader/page_animations/cover_layout.dart';

/// 覆盖翻页(cover)偏移公式单元测试。
///
/// 不依赖 Canvas/渲染, 纯数学验证 `calcCoverOffsets`。重点保证:
/// - NEXT/PREV 各进度点的偏移值精确(可手算)
/// - none 态三页归位(与 slide 一致, none→动画过渡连续)
/// - 阴影位置正确(覆盖层后缘), 起止点不画
/// - 边界(width=0)不崩
///
/// cover 与 slide 的本质差异(见 cover_layout.dart 推导):
/// - slide: cur 和 next/prev 都按 progress 平移
/// - cover NEXT: cur 向左滑出(-p·W), next 静止(0, 被 cur 覆盖, 逐渐露出)
/// - cover PREV: cur 静止(0), prev 从右滑入((p-1)·W)覆盖 cur
void main() {
  const width = 400.0;

  group('none 态(静止)', () {
    test('三页归位: cur=0, next=+W(屏外), prev=-W(屏外)', () {
      final o = calcCoverOffsets(
        progress: 0,
        isNext: false,
        isPrev: false,
        width: width,
      );
      expect(o.curX, 0.0, reason: 'cur 在原位');
      expect(o.nextX, width, reason: 'next 屏外右侧');
      expect(o.prevX, -width, reason: 'prev 屏外左侧');
      expect(o.shadowLeft, isNull, reason: '静止态不画阴影');
    });

    test('none 态与 slide 一致(none→动画过渡连续的前提)', () {
      // cover 与 slide 在 none 态的偏移必须相同, 否则切模式/起翻时会有跳变。
      final o = calcCoverOffsets(
        progress: 0,
        isNext: false,
        isPrev: false,
        width: width,
      );
      // slide 公式: cur=0, next=+W, prev=-W
      expect(o.curX, 0.0);
      expect(o.nextX, width);
      expect(o.prevX, -width);
    });
  });

  group('NEXT 方向(cur 向左滑出, next 静止露出)', () {
    test('p=0: cur 在原位, next 贴右边(被 cur 完全覆盖)', () {
      final o = calcCoverOffsets(
        progress: 0,
        isNext: true,
        isPrev: false,
        width: width,
      );
      // cover NEXT p=0: curX=-0=0(还没动), nextX=0(静止)。
      // 与 none 态 curX=0 连续。
      expect(o.curX, 0.0, reason: '起点 cur 在原位');
      expect(o.nextX, 0.0, reason: 'next 静止(被 cur 覆盖)');
      expect(o.shadowLeft, isNull, reason: '起点不画阴影(对齐原生 left==0 return)');
    });

    test('p=0.5: cur 左移半屏, next 露出右半', () {
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: true,
        isPrev: false,
        width: width,
      );
      expect(o.curX, closeTo(-200.0, 1e-9), reason: 'cur 左边缘在 -0.5W');
      expect(o.nextX, 0.0, reason: 'next 始终静止在 0(cover 核心: 被覆盖方不动)');
      expect(o.prevX, -width, reason: 'prev 屏外不受影响');
      // 阴影在 cur 右边缘 = curX + W = -200 + 400 = 200
      expect(o.shadowLeft, closeTo(200.0, 1e-9), reason: '阴影在 cur 右边缘');
    });

    test('p=1.0: cur 完全滑出左屏, next 完全露出', () {
      final o = calcCoverOffsets(
        progress: 1.0,
        isNext: true,
        isPrev: false,
        width: width,
      );
      expect(o.curX, closeTo(-400.0, 1e-9), reason: 'cur 完全滑出左侧');
      expect(o.nextX, 0.0, reason: 'next 静止在原位');
      expect(o.shadowLeft, isNull, reason: '终点不画阴影(对齐原生 distanceX=0)');
    });

    test('cover 与 slide 的核心差异: next 不跟随平移', () {
      // slide NEXT p=0.5: nextX = (1-0.5)·W = 200(从右滑入)
      // cover NEXT p=0.5: nextX = 0(静止)
      // 这是两种翻页模式的本质区别。
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: true,
        isPrev: false,
        width: width,
      );
      expect(o.nextX, 0.0, reason: 'cover: next 静止不动(slide 会是 200)');
    });
  });

  group('PREV 方向(cur 静止, prev 从右滑入覆盖)', () {
    test('p=0: prev 在屏右外, cur 在原位', () {
      final o = calcCoverOffsets(
        progress: 0,
        isNext: false,
        isPrev: true,
        width: width,
      );
      expect(o.curX, 0.0, reason: 'cur 静止在原位');
      expect(o.prevX, closeTo(-400.0, 1e-9), reason: 'prev 左边缘在 -W(屏右外)');
      expect(o.shadowLeft, isNull, reason: '起点不画阴影');
    });

    test('p=0.5: prev 滑入半屏覆盖 cur', () {
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: false,
        isPrev: true,
        width: width,
      );
      expect(o.curX, 0.0, reason: 'cur 始终静止(cover 核心: 被覆盖方不动)');
      expect(o.prevX, closeTo(-200.0, 1e-9), reason: 'prev 左边缘在 -0.5W(从右滑入)');
      // 阴影在 prev 右边缘 = prevX + W = -200 + 400 = 200
      expect(o.shadowLeft, closeTo(200.0, 1e-9), reason: '阴影在 prev 右边缘');
    });

    test('p=1.0: prev 完全覆盖 cur', () {
      final o = calcCoverOffsets(
        progress: 1.0,
        isNext: false,
        isPrev: true,
        width: width,
      );
      expect(o.curX, 0.0, reason: 'cur 静止');
      expect(o.prevX, closeTo(0.0, 1e-9), reason: 'prev 完全滑入对齐原位');
      expect(o.shadowLeft, isNull, reason: '终点不画阴影');
    });

    test('cover 与 slide 的核心差异: cur 不跟随平移', () {
      // slide PREV p=0.5: curX = +0.5·W = 200(向右滑出)
      // cover PREV p=0.5: curX = 0(静止)
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: false,
        isPrev: true,
        width: width,
      );
      expect(o.curX, 0.0, reason: 'cover: cur 静止不动(slide 会是 +200)');
    });
  });

  group('阴影', () {
    test('NEXT 中间过程阴影在 cur 右边缘, 随进度左移', () {
      for (final p in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        final o = calcCoverOffsets(
            progress: p, isNext: true, isPrev: false, width: width);
        // 阴影 left = curX + W = -p·W + W = (1-p)·W
        expect(o.shadowLeft, closeTo((1 - p) * width, 1e-9),
            reason: 'p=$p 阴影应在 (1-p)·W');
      }
    });

    test('PREV 中间过程阴影在 prev 右边缘, 随进度右移', () {
      for (final p in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        final o = calcCoverOffsets(
            progress: p, isNext: false, isPrev: true, width: width);
        // 阴影 left = prevX + W = (p-1)·W + W = p·W
        expect(o.shadowLeft, closeTo(p * width, 1e-9),
            reason: 'p=$p 阴影应在 p·W');
      }
    });

    test('起止点(progress=0 和 1)不画阴影', () {
      // 对齐原生 addShadow 的 `if (left == 0f) return`。
      for (final isNext in [true, false]) {
        final o0 = calcCoverOffsets(
            progress: 0, isNext: isNext, isPrev: !isNext, width: width);
        final o1 = calcCoverOffsets(
            progress: 1, isNext: isNext, isPrev: !isNext, width: width);
        expect(o0.shadowLeft, isNull, reason: 'isNext=$isNext p=0 无阴影');
        expect(o1.shadowLeft, isNull, reason: 'isNext=$isNext p=1 无阴影');
      }
    });
  });

  group('边界', () {
    test('width=0 不崩(返回全零)', () {
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: true,
        isPrev: false,
        width: 0,
      );
      expect(o.curX, 0.0);
      expect(o.nextX, 0.0);
      expect(o.prevX, 0.0);
      expect(o.shadowLeft, isNull);
    });

    test('width 为负不崩', () {
      final o = calcCoverOffsets(
        progress: 0.5,
        isNext: true,
        isPrev: false,
        width: -100,
      );
      expect(o.curX, 0.0);
      expect(o.nextX, 0.0);
      expect(o.prevX, 0.0);
      expect(o.shadowLeft, isNull);
    });

    test('progress 超出 [0,1] 被 clamp 处理(阴影只在中段画)', () {
      // progress 略超 1: 阴影 hasShadow 判定为 false(>=1), 不画。
      final o = calcCoverOffsets(
        progress: 1.0001,
        isNext: true,
        isPrev: false,
        width: width,
      );
      expect(o.shadowLeft, isNull, reason: 'progress≥1 不画阴影');
    });
  });

  group('过渡连续性', () {
    test('none→NEXT 在 p=0 偏移连续(cur 都在 0)', () {
      final oNone = calcCoverOffsets(
          progress: 0, isNext: false, isPrev: false, width: width);
      final oNext0 = calcCoverOffsets(
          progress: 0, isNext: true, isPrev: false, width: width);
      // none 态 curX=0, NEXT p=0 curX=0 → 连续
      expect(oNext0.curX, oNone.curX,
          reason: 'none→NEXT cur 偏移连续');
    });

    test('none→PREV 在 p=0 偏移连续(cur 都在 0)', () {
      final oNone = calcCoverOffsets(
          progress: 0, isNext: false, isPrev: false, width: width);
      final oPrev0 = calcCoverOffsets(
          progress: 0, isNext: false, isPrev: true, width: width);
      expect(oPrev0.curX, oNone.curX,
          reason: 'none→PREV cur 偏移连续');
    });
  });
}
