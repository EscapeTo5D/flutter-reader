import 'package:flutter/material.dart';

enum PageDirection { none, next, prev }

abstract class PageAnimation {
  AnimationController? _controller;
  late Animation<double> _animation;

  void init(TickerProvider vsync, {Duration duration = const Duration(milliseconds: 300)}) {
    _controller = AnimationController(vsync: vsync, duration: duration);
    _animation = CurvedAnimation(parent: _controller!, curve: Curves.easeInOut);
  }

  void dispose() {
    _controller?.dispose();
  }

  Animation<double> get animation => _animation;
  AnimationController? get controller => _controller;

  void forward() => _controller?.forward();
  void reverse() => _controller?.reverse();
  void reset() => _controller?.reset();
  void animateTo(double value) => _controller?.animateTo(value);

  Widget build({
    required BuildContext context,
    required Widget currentPage,
    required Widget? nextPage,
    required Widget? prevPage,
    required PageDirection direction,
    required double dragProgress,
  });

  bool get isAnimating => _controller?.isAnimating ?? false;
  bool get isCompleted => _controller?.isCompleted ?? false;
  double get value => _controller?.value ?? 0;
}
