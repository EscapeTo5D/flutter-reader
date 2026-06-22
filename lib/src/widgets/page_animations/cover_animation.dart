import 'package:flutter/material.dart';
import 'page_animation.dart';

class CoverAnimation extends PageAnimation {
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
        final value = direction == PageDirection.next
            ? (dragProgress > 0 ? dragProgress : animation.value)
            : (dragProgress < 0 ? -dragProgress : animation.value);

        return Stack(
          children: [
            if (direction == PageDirection.next)
              nextPage ?? const SizedBox()
            else
              prevPage ?? const SizedBox(),
            Transform.translate(
              offset: Offset(
                direction == PageDirection.next
                    ? MediaQuery.of(context).size.width * (1 - value)
                    : -MediaQuery.of(context).size.width * (1 - value),
                0,
              ),
              child: currentPage,
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
