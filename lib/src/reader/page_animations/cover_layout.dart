// 覆盖翻页(cover)的偏移与阴影计算。
//
// 对齐原生 legado `CoverPageDelegate.onDraw` 的数学模型, 等价转换到 Flutter 的
// Stack + Transform.translate 模型。原生用 Canvas clip + translate 画 bitmap;
// Flutter 用三页 Stack, 靠 z-order(children 顺序) + Transform 偏移实现等价效果。
//
// **cover 与 slide 的唯一本质差异**: slide 让 cur 和 next/prev 都按 progress 平移;
// cover 只让「覆盖方」(NEXT 的 cur / PREV 的 prev)平移, 「被覆盖方」静止不动。
//
// 推导(原生 CoverPageDelegate.onDraw, offsetX = touchX - startX):
//
// NEXT(offsetX ∈ [-W, 0], distanceX = offsetX + W):
//   原生: next 用 withClip(W+offsetX, 0, W, H) 静止露出右边缘;
//         cur 用 withTranslation(distanceX - W = offsetX) 向左滑出。
//   Flutter: next 静止在 0(被 cur 覆盖, 逐渐露出); cur 左边缘 = offsetX = -p·W。
//   阴影: addShadow(distanceX), dx = distanceX = (1-p)·W = cur 右边缘。
//
// PREV(offsetX ∈ [0, W], distanceX = offsetX - W):
//   原生: cur 不画(实时子 View 在底静止); prev 用 withTranslation(distanceX) 从右滑入。
//   Flutter: cur 静止在 0; prev 左边缘 = distanceX = (p-1)·W。
//   阴影: addShadow(distanceX), dx = distanceX + W = p·W = prev 右边缘。

/// 覆盖翻页阴影宽度(逻辑像素)。
///
/// 对齐原生 `CoverPageDelegate.kt:84` 的 `shadowDrawableR.setBounds(0,0,30,H)` ——
/// 原生 30 是物理像素, 在 xxhdpi(≈3x)屏上 ≈ 10dp。Flutter 取 15 逻辑像素(dp),
/// 视觉上接近原生观感且在各密度屏上都清晰可见。
const double kCoverShadowWidth = 15.0;

/// 覆盖翻页阴影起始色(对齐原生 `CoverPageDelegate.kt:15` `0x66111111`)。
///
/// 约 40% 不透明深灰, 从覆盖层后缘向被覆盖页方向渐变到全透明。
const int kCoverShadowColorARGB = 0x66111111;

/// 覆盖翻页的单帧布局结果。
class CoverOffsets {
  /// 当前页 cur 的水平偏移。
  final double curX;

  /// 下一页 next 的水平偏移。
  final double nextX;

  /// 上一页 prev 的水平偏移。
  final double prevX;

  /// 阴影左边缘 x 坐标; `null` 表示该帧不画阴影(none 态, 或翻页起止点)。
  ///
  /// 阴影从 [shadowLeft] 向右画 [kCoverShadowWidth] 宽, 颜色由
  /// [kCoverShadowColorARGB] 渐变到透明。位置 = 覆盖移动页的后缘(右边缘)。
  final double? shadowLeft;

  const CoverOffsets(this.curX, this.nextX, this.prevX, this.shadowLeft);

  @override
  String toString() =>
      'CoverOffsets(cur=$curX, next=$nextX, prev=$prevX, shadow=$shadowLeft)';
}

/// 计算 cover 翻页在给定进度下的三页偏移与阴影位置。
///
/// [progress] 翻页完成度 ∈ [0, 1](0 = 起点, 1 = 整页翻过)。
/// [isNext] / [isPrev] 当前方向(两者互斥, 都为 false = none 态)。
/// [width] 视口宽度(逻辑像素)。
/// [shadowWidth] 阴影宽度, 默认 [kCoverShadowWidth]。
///
/// 返回的 [CoverOffsets] 直接用于 Stack 的 Transform.translate 偏移。
/// 层级(children 顺序)由调用方按方向决定, 不在此函数职责内。
CoverOffsets calcCoverOffsets({
  required double progress,
  required bool isNext,
  required bool isPrev,
  required double width,
  double shadowWidth = kCoverShadowWidth,
}) {
  if (width <= 0) return const CoverOffsets(0, 0, 0, null);

  // none 态: cur 原位, next/prev 屏外(与 slide 一致, none→动画过渡连续)。
  if (!isNext && !isPrev) {
    return CoverOffsets(0.0, width, -width, null);
  }

  // 阴影只在翻页中间过程有意义: progress=0 是起点(无位移), progress=1 是终点
  // (对齐原生 addShadow 的 `if (left == 0f) return` —— NEXT 终点 distanceX=0 不画)。
  final hasShadow = progress > 0 && progress < 1;

  if (isNext) {
    // NEXT: cur 向左滑出(-p·W), next 静止在 0(被 cur 覆盖, cur 滑走逐渐露出)。
    final curX = -progress * width;
    // 阴影在 cur 右边缘(= curX + W = (1-p)·W), 向右渐淡覆盖在露出的 next 上。
    final shadowLeft = hasShadow ? curX + width : null;
    return CoverOffsets(curX, 0.0, -width, shadowLeft);
  }

  // PREV: cur 静止在 0, prev 从右滑入((p-1)·W)覆盖 cur。
  final prevX = progress * width - width;
  // 阴影在 prev 右边缘(= prevX + W = p·W), 向右渐淡覆盖在露出的 cur 上。
  final shadowLeft = hasShadow ? prevX + width : null;
  return CoverOffsets(0.0, width, prevX, shadowLeft);
}
