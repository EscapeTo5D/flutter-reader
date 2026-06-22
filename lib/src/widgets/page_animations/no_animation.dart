import 'package:flutter/material.dart';
import 'page_animation.dart';

class NoAnimation extends PageAnimation {
  @override
  Widget build({
    required BuildContext context,
    required Widget currentPage,
    required Widget? nextPage,
    required Widget? prevPage,
    required PageDirection direction,
    required double dragProgress,
  }) {
    return currentPage;
  }
}
