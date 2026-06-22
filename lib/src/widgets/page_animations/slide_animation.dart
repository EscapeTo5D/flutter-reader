import 'package:flutter/material.dart';
import 'page_animation.dart';

class SlideAnimation extends PageAnimation {
  @override
  Widget build({
    required BuildContext context,
    required Widget currentPage,
    required Widget? nextPage,
    required Widget? prevPage,
    required PageDirection direction,
    required double dragProgress,
  }) {
    return AnimatedBuilder(
      listenable: animation,
      builder: (context, child) {
        final width = MediaQuery.of(context).size.width;
        final value = animation.value;

        return Stack(
          children: [
            Transform.translate(
              offset: Offset(
                direction == PageDirection.next
                    ? width * (1 - value)
                    : -width * (1 - value),
                0,
              ),
              child: direction == PageDirection.next ? currentPage : prevPage,
            ),
            Transform.translate(
              offset: Offset(
                direction == PageDirection.next
                    ? -width * value
                    : width * value,
                0,
              ),
              child: direction == PageDirection.next ? nextPage : currentPage,
            ),
          ],
        );
      },
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
