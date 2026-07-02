import 'package:flutter/material.dart';

/// 阅读器统一路由转场: 左右向 + 450ms, 对所有平台一致。
///
/// 阅读类 App 的直觉是「进入新页向左、返回上一页向右」。Material 各平台默认转场
/// 不一致(Android 左右向、桌面 zoom/fade、iOS Cupertino 风格), 且默认时长(~300ms)
/// 偏快。本路由对所有 [TargetPlatform] 一律:
///   - push 时新页从屏幕右侧滑入(`Offset(1,0) → Offset.zero`)
///   - pop 时新页向右滑出(animation 反播, 即「退出向右」)
///   - 底层页(被覆盖页)push 时向左轻推 1/3, 营造景深
///   - 时长 450ms, 比默认柔和
///
/// 宿主与包内 push 均应使用本路由, 保证进入/退出小说、进入/退出目录等转场统一。
class ReaderPageRoute<T> extends PageRoute<T> {
  ReaderPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  /// 转场时长(ms)。对齐阅读类 App 的柔和节奏。
  static const int _durationMs = 450;

  @override
  Duration get transitionDuration => const Duration(milliseconds: _durationMs);

  @override
  Duration get reverseTransitionDuration =>
      const Duration(milliseconds: _durationMs);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 新页位移: push 正向从右侧外(1,0)滑入到原点(0,0);
    // pop 反向由 animation 反播, 自动从原点滑回右侧外 → 即「退出向右」。
    final pageOffset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    // 底层页(被覆盖页)位移: push 时向左轻推 1/3, 营造景深; pop 时滑回。
    final behindOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.0 / 3, 0),
    ).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic));
    return SlideTransition(
      position: behindOffset,
      child: SlideTransition(position: pageOffset, child: child),
    );
  }
}
