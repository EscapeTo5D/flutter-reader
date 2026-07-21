import 'package:flutter/material.dart';

class LegadoIcons {
  static Widget arrowBack({double size = 24, Color color = const Color(0xFF000000)}) =>
      CustomPaint(size: Size(size, size), painter: _ArrowBackPainter(color));

  static Widget bookmark({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _BookmarkPainter(color));

  static Widget close({double size = 24, Color color = const Color(0xFFFFFFFF)}) =>
      CustomPaint(size: Size(size, size), painter: _ClosePainter(color));

  static Widget copy({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _CopyPainter(color));

  static Widget arrowDropUp({double size = 24, Color color = const Color(0xFF000000)}) =>
      CustomPaint(size: Size(size, size), painter: _ArrowDropUpPainter(color));

  static Widget arrowDropDown({double size = 24, Color color = const Color(0xFF000000)}) =>
      CustomPaint(size: Size(size, size), painter: _ArrowDropDownPainter(color));

  static Widget check({double size = 24, Color color = const Color(0xFF000000)}) =>
      CustomPaint(size: Size(size, size), painter: _CheckPainter(color));

  static Widget search({double size = 24, Color color = const Color(0xFF39393A)}) =>
      CustomPaint(size: Size(size, size), painter: _SearchPainter(color));

  static Widget findReplace({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _FindReplacePainter(color));

  static Widget brightness({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _BrightnessPainter(color));

  /// ic_daytime.xml — 夜晚态启用时显示的「白天」图标(切回白天模式), 对齐原生
  /// `ReadMenu.upBrightnessState`: `AppConfig.isNightTheme=true` 时 fabNightTheme
  /// 切 `R.drawable.ic_daytime`。
  static Widget daytime({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _DaytimePainter(color));

  static Widget autoPage({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _AutoPagePainter(color));

  static Widget toc({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _TocPainter(color));

  static Widget readAloud({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _ReadAloudPainter(color));

  static Widget interfaceSetting({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _InterfaceSettingPainter(color));

  static Widget settings({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _SettingsPainter(color));

  static Widget reduce({double size = 24, Color color = const Color(0xFF000000)}) =>
      CustomPaint(size: Size(size, size), painter: _ReducePainter(color));

  static Widget add({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _AddPainter(color));

  // ── 朗读弹窗用图标(对齐原生 dialog_read_aloud.xml 引用的 drawable) ──

  /// 上一段(ic_skip_previous)。
  static Widget skipPrevious({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _SkipPreviousPainter(color));

  /// 下一段(ic_skip_next)。
  static Widget skipNext({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _SkipNextPainter(color));

  /// 播放(ic_play_24dp)。
  static Widget play({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _PlayPainter(color));

  /// 暂停(ic_pause_24dp)。
  static Widget pause({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _PausePainter(color));

  /// 停止(ic_stop_black_24dp)。
  static Widget stop({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _StopPainter(color));

  /// 定时(ic_time_add_24dp, viewport 1000)。
  static Widget timer({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _TimerPainter(color));

  /// 主菜单(ic_menu)。
  static Widget mainMenu({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _MainMenuPainter(color));

  /// 后台/隐藏(ic_visibility_off)。
  static Widget visibilityOff({double size = 24, Color color = const Color(0xFF595757)}) =>
      CustomPaint(size: Size(size, size), painter: _VisibilityOffPainter(color));
}

// ic_arrow_back.xml
class _ArrowBackPainter extends CustomPainter {
  final Color color;
  _ArrowBackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(20, 11)
        ..lineTo(7.83, 11)
        ..lineTo(13.42, 5.41)
        ..lineTo(12, 4)
        ..lineTo(4, 12)
        ..lineTo(12, 20)
        ..lineTo(13.41, 18.59)
        ..lineTo(7.83, 13)
        ..lineTo(20, 13)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowBackPainter old) => old.color != color;
}

// ic_bookmark.xml
class _BookmarkPainter extends CustomPainter {
  final Color color;
  _BookmarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(5.938, 4)
        ..lineTo(5.938, 20)
        ..lineTo(7.352, 20)
        ..lineTo(12, 17.211)
        ..lineTo(16.649, 20)
        ..lineTo(18.06, 20)
        ..lineTo(18.06, 4)
        ..close()
        ..moveTo(16.606, 18.278)
        ..lineTo(12.001, 15.515)
        ..lineTo(7.397, 18.279)
        ..lineTo(7.397, 5.454)
        ..lineTo(16.612, 5.454)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BookmarkPainter old) => old.color != color;
}

// ic_baseline_close.xml
class _ClosePainter extends CustomPainter {
  final Color color;
  _ClosePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(19, 6.41)
        ..lineTo(17.59, 5)
        ..lineTo(12, 10.59)
        ..lineTo(6.41, 5)
        ..lineTo(5, 6.41)
        ..lineTo(10.59, 12)
        ..lineTo(5, 17.59)
        ..lineTo(6.41, 19)
        ..lineTo(12, 13.41)
        ..lineTo(17.59, 19)
        ..lineTo(19, 17.59)
        ..lineTo(13.41, 12)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClosePainter old) => old.color != color;
}

// ic_copy.xml
class _CopyPainter extends CustomPainter {
  final Color color;
  _CopyPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(18.303, 8.091)
        ..lineTo(14.939, 8.091)
        ..lineTo(14.939, 4.727)
        ..lineTo(15.848, 4.727)
        ..lineTo(15.848, 7.182)
        ..lineTo(18.303, 7.182)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(19.03, 18.061)
        ..lineTo(6.91, 18.061)
        ..lineTo(6.91, 4)
        ..lineTo(15.695, 4)
        ..lineTo(19.03, 7.335)
        ..close()
        ..moveTo(8.363, 16.606)
        ..lineTo(17.576, 16.606)
        ..lineTo(17.576, 7.938)
        ..lineTo(15.093, 5.454)
        ..lineTo(8.363, 5.454)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(17.09, 20)
        ..lineTo(4.969, 20)
        ..lineTo(4.969, 5.939)
        ..lineTo(7.636, 5.939)
        ..lineTo(7.636, 7.394)
        ..lineTo(6.424, 7.394)
        ..lineTo(6.424, 18.546)
        ..lineTo(15.636, 18.546)
        ..lineTo(15.636, 17.333)
        ..lineTo(17.09, 17.333)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CopyPainter old) => old.color != color;
}

// ic_arrow_drop_up.xml
class _ArrowDropUpPainter extends CustomPainter {
  final Color color;
  _ArrowDropUpPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(7, 14)
        ..lineTo(12, 9)
        ..lineTo(17, 14)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowDropUpPainter old) => old.color != color;
}

// ic_arrow_drop_down.xml
class _ArrowDropDownPainter extends CustomPainter {
  final Color color;
  _ArrowDropDownPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(7, 10)
        ..lineTo(12, 15)
        ..lineTo(17, 10)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowDropDownPainter old) => old.color != color;
}

// ic_check.xml
class _CheckPainter extends CustomPainter {
  final Color color;
  _CheckPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(9, 16.17)
        ..lineTo(4.83, 12)
        ..lineTo(3.41, 13.41)
        ..lineTo(9, 19)
        ..lineTo(21, 7)
        ..lineTo(19.59, 5.59)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.color != color;
}

// ic_search.xml (viewport 48x48)
class _SearchPainter extends CustomPainter {
  final Color color;
  _SearchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 48;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(20, 32.7)
        ..cubicTo(13.1, 32.7, 7.4, 27, 7.4, 20.1)
        ..cubicTo(7.4, 13.2, 13.1, 7.5, 20, 7.5)
        ..cubicTo(26.9, 7.5, 32.6, 13.1, 32.6, 20.1)
        ..cubicTo(32.6, 27, 27, 32.7, 20, 32.7)
        ..close()
        ..moveTo(20, 9)
        ..cubicTo(13.9, 9, 8.9, 14, 8.9, 20.1)
        ..cubicTo(8.9, 26.2, 13.9, 31.2, 20, 31.2)
        ..cubicTo(26.1, 31.2, 31.1, 26.2, 31.1, 20.1)
        ..cubicTo(31.1, 14, 26.2, 9, 20, 9)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(39.8, 40.4)
        ..cubicTo(39.6, 40.4, 39.4, 40.3, 39.3, 40.2)
        ..lineTo(28.1, 29.1)
        ..cubicTo(27.8, 28.8, 27.8, 28.4, 28.1, 28.1)
        ..cubicTo(28.4, 27.8, 28.8, 27.8, 29.1, 28.1)
        ..lineTo(40.2, 39.2)
        ..cubicTo(40.5, 39.5, 40.5, 39.9, 40.2, 40.2)
        ..cubicTo(40.1, 40.3, 39.9, 40.4, 39.8, 40.4)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SearchPainter old) => old.color != color;
}

// ic_find_replace.xml
class _FindReplacePainter extends CustomPainter {
  final Color color;
  _FindReplacePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(8.829, 10.126)
        ..lineTo(7.502, 11.451)
        ..cubicTo(7.447, 11.162, 7.415, 10.868, 7.415, 10.57)
        ..cubicTo(7.415, 7.997, 9.506, 5.907, 12.077, 5.907)
        ..cubicTo(13.573, 5.907, 14.99, 6.633, 15.864, 7.851)
        ..lineTo(16.947, 7.071)
        ..cubicTo(15.822, 5.508, 14.002, 4.574, 12.077, 4.574)
        ..cubicTo(8.772, 4.574, 6.083, 7.263, 6.083, 10.57)
        ..cubicTo(6.083, 10.684, 6.107, 10.795, 6.113, 10.909)
        ..lineTo(5.33, 10.126)
        ..lineTo(4.388, 11.068)
        ..lineTo(7.078, 13.757)
        ..lineTo(9.769, 11.069)
        ..lineTo(8.829, 10.126)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(20.388, 18.483)
        ..lineTo(16.501, 14.596)
        ..cubicTo(17.472, 13.531, 18.07, 12.12, 18.07, 10.57)
        ..cubicTo(18.07, 10.536, 18.064, 10.503, 18.064, 10.468)
        ..lineTo(18.955, 11.359)
        ..lineTo(19.897, 10.417)
        ..lineTo(17.206, 7.727)
        ..lineTo(14.515, 10.416)
        ..lineTo(15.455, 11.359)
        ..lineTo(16.708, 10.107)
        ..cubicTo(16.723, 10.26, 16.737, 10.415, 16.737, 10.57)
        ..cubicTo(16.737, 13.138, 14.647, 15.228, 12.076, 15.228)
        ..cubicTo(10.742, 15.228, 9.469, 14.656, 8.584, 13.656)
        ..lineTo(7.586, 14.539)
        ..cubicTo(8.724, 15.823, 10.36, 16.561, 12.076, 16.561)
        ..cubicTo(13.349, 16.561, 14.528, 16.159, 15.5, 15.48)
        ..lineTo(19.446, 19.425)
        ..lineTo(20.388, 18.483)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FindReplacePainter old) => old.color != color;
}

// ic_brightness.xml
class _BrightnessPainter extends CustomPainter {
  final Color color;
  _BrightnessPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(12, 20)
        ..cubicTo(7.59, 20, 4, 16.412, 4, 12)
        ..cubicTo(4, 7.588, 7.59, 4, 12, 4)
        ..lineTo(12.848, 4)
        ..lineTo(12.698, 4.835)
        ..cubicTo(12.693, 4.862, 12.221, 7.656, 13.793, 9.529)
        ..cubicTo(14.782, 10.711, 16.402, 11.306, 18.606, 11.307)
        ..cubicTo(18.816, 11.307, 19.032, 11.304, 19.255, 11.29)
        ..lineTo(20, 11.256)
        ..lineTo(20, 12)
        ..cubicTo(20, 16.412, 16.411, 20, 12, 20)
        ..close()
        ..moveTo(11.215, 5.463)
        ..cubicTo(7.955, 5.854, 5.418, 8.635, 5.418, 12)
        ..cubicTo(5.418, 15.631, 8.371, 18.583, 12, 18.583)
        ..cubicTo(15.384, 18.583, 18.18, 16.015, 18.543, 12.727)
        ..cubicTo(15.925, 12.713, 13.958, 11.943, 12.698, 10.43)
        ..cubicTo(11.305, 8.762, 11.165, 6.641, 11.215, 5.463)
        ..close(),
      paint,
    );

    canvas.restore();
  }

    @override
  bool shouldRepaint(covariant _BrightnessPainter old) => old.color != color;
}

// ic_daytime.xml —— 太阳图标(夜晚态下显示, 切回白天)。
// 9 个 path: 8 道光线 + 中心圆环。逐 pathData 翻译。
class _DaytimePainter extends CustomPainter {
  final Color color;
  _DaytimePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    // 8 道光线
    canvas.drawPath(
      Path()
        ..moveTo(16.638, 8.494)
        ..lineTo(18.223, 6.908)
        ..lineTo(17.091, 5.777)
        ..lineTo(15.506, 7.363)
        ..cubicTo(15.933, 7.687, 16.313, 8.066, 16.638, 8.494)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8.495, 7.363)
        ..lineTo(6.909, 5.777)
        ..lineTo(5.778, 6.909)
        ..lineTo(7.362, 8.494)
        ..cubicTo(7.687, 8.067, 8.067, 7.687, 8.495, 7.363)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12.001, 6.181)
        ..cubicTo(12.271, 6.181, 12.537, 6.206, 12.799, 6.243)
        ..lineTo(12.799, 4)
        ..lineTo(11.2, 4)
        ..lineTo(11.2, 6.243)
        ..cubicTo(11.462, 6.206, 11.728, 6.181, 12.001, 6.181)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6.181, 12)
        ..cubicTo(6.181, 11.729, 6.206, 11.463, 6.243, 11.2)
        ..lineTo(4, 11.2)
        ..lineTo(4, 12.8)
        ..lineTo(6.243, 12.8)
        ..cubicTo(6.206, 12.538, 6.181, 12.272, 6.181, 12)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15.506, 16.638)
        ..lineTo(17.091, 18.223)
        ..lineTo(18.222, 17.091)
        ..lineTo(16.638, 15.506)
        ..cubicTo(16.313, 15.934, 15.933, 16.313, 15.506, 16.638)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17.759, 11.2)
        ..cubicTo(17.794, 11.463, 17.82, 11.728, 17.82, 12)
        ..cubicTo(17.82, 12.272, 17.795, 12.538, 17.759, 12.8)
        ..lineTo(20, 12.8)
        ..lineTo(20, 11.2)
        ..lineTo(17.759, 11.2)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(7.363, 15.506)
        ..lineTo(5.778, 17.091)
        ..lineTo(6.909, 18.222)
        ..lineTo(8.494, 16.638)
        ..cubicTo(8.067, 16.313, 7.687, 15.934, 7.363, 15.506)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12.001, 17.819)
        ..cubicTo(11.728, 17.819, 11.462, 17.795, 11.2, 17.757)
        ..lineTo(11.2, 20)
        ..lineTo(12.8, 20)
        ..lineTo(12.8, 17.757)
        ..cubicTo(12.538, 17.795, 12.272, 17.819, 12.001, 17.819)
        ..close(),
      paint,
    );
    // 中心: 外圆 r=2.6 + 内圆 r=2 的环(原生 pathData 用 even-odd 填充规则
    // 由「外圆 + 反向内圆」挖空)。Flutter 用 PathFillType.evenOdd 显式声明,
    // 两 subpath 顺时针/逆时针均可正确挖空。
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(12, 16.6)
        ..cubicTo(9.464, 16.6, 7.4, 14.537, 7.4, 12)
        ..cubicTo(7.4, 9.463, 9.464, 7.4, 12, 7.4)
        ..cubicTo(14.536, 7.4, 16.6, 9.463, 16.6, 12)
        ..cubicTo(16.6, 14.537, 14.536, 16.6, 12, 16.6)
        ..close()
        ..moveTo(12, 9)
        ..cubicTo(10.346, 9, 9, 10.346, 9, 12)
        ..cubicTo(9, 13.654, 10.346, 15, 12, 15)
        ..cubicTo(13.654, 15, 15, 13.654, 15, 12)
        ..cubicTo(15, 10.346, 13.654, 9, 12, 9)
        ..close(),
      paint..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DaytimePainter old) => old.color != color;
}


// ic_auto_page.xml
class _AutoPagePainter extends CustomPainter {
  final Color color;
  _AutoPagePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(19.109, 6.212)
        ..lineTo(16.949, 6.212)
        ..lineTo(16.947, 5.395)
        ..cubicTo(16.947, 5.029, 16.783, 4.735, 16.507, 4.607)
        ..cubicTo(16.374, 4.545, 16.229, 4.516, 16.062, 4.516)
        ..cubicTo(15.767, 4.516, 15.467, 4.608, 15.177, 4.697)
        ..lineTo(10.056, 6.213)
        ..lineTo(4.891, 6.213)
        ..cubicTo(4.322, 6.213, 3.875, 6.62, 3.875, 7.14)
        ..lineTo(3.875, 17.047)
        ..cubicTo(3.875, 17.567, 4.321, 17.973, 4.891, 17.973)
        ..lineTo(10.174, 17.973)
        ..cubicTo(10.867, 18.163, 15.123, 19.332, 15.482, 19.436)
        ..cubicTo(15.597, 19.469, 15.711, 19.486, 15.821, 19.486)
        ..cubicTo(16.35, 19.486, 16.904, 19.064, 16.919, 18.646)
        ..lineTo(16.921, 17.973)
        ..lineTo(19.11, 17.973)
        ..cubicTo(19.679, 17.973, 20.125, 17.567, 20.125, 17.047)
        ..lineTo(20.125, 7.139)
        ..cubicTo(20.125, 6.619, 19.679, 6.212, 19.109, 6.212)
        ..close()
        ..moveTo(18.687, 7.65)
        ..lineTo(18.687, 16.533)
        ..lineTo(16.924, 16.533)
        ..lineTo(16.947, 7.65)
        ..close()
        ..moveTo(15.516, 17.95)
        ..cubicTo(14.793, 17.746, 13.234, 17.3, 12.057, 16.962)
        ..cubicTo(11.263, 16.734, 10.643, 16.557, 10.572, 16.537)
        ..lineTo(5.314, 16.533)
        ..lineTo(5.314, 7.65)
        ..lineTo(10.539, 7.65)
        ..lineTo(15.511, 6.126)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(9.544, 8.915)
        ..lineTo(6.366, 12.092)
        ..lineTo(9.544, 15.269)
        ..lineTo(10.562, 14.252)
        ..lineTo(9.12, 12.811)
        ..lineTo(14.217, 12.811)
        ..lineTo(14.217, 11.372)
        ..lineTo(9.12, 11.372)
        ..lineTo(10.562, 9.932)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AutoPagePainter old) => old.color != color;
}

// ic_toc.xml
class _TocPainter extends CustomPainter {
  final Color color;
  _TocPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(3, 9)..lineTo(17, 9)..lineTo(17, 7)..lineTo(3, 7)..close()
        ..moveTo(3, 13)..lineTo(17, 13)..lineTo(17, 11)..lineTo(3, 11)..close()
        ..moveTo(3, 17)..lineTo(17, 17)..lineTo(17, 15)..lineTo(3, 15)..close()
        ..moveTo(19, 17)..lineTo(21, 17)..lineTo(21, 15)..lineTo(19, 15)..close()
        ..moveTo(19, 7)..lineTo(19, 9)..lineTo(21, 9)..lineTo(21, 7)..close()
        ..moveTo(19, 13)..lineTo(21, 13)..lineTo(21, 11)..lineTo(19, 11)..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TocPainter old) => old.color != color;
}

// ic_read_aloud.xml
class _ReadAloudPainter extends CustomPainter {
  final Color color;
  _ReadAloudPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(12, 4)
        ..cubicTo(7.588, 4, 4, 7.559, 4, 11.933)
        ..lineTo(4, 13.202)..lineTo(4, 15.319)..lineTo(4, 18.193)
        ..cubicTo(4, 19.189, 4.816, 20, 5.818, 20)
        ..lineTo(8.242, 20)
        ..cubicTo(9.244, 20, 10.06, 19.189, 10.06, 18.192)
        ..lineTo(10.06, 13.201)
        ..cubicTo(10.06, 12.204, 9.244, 11.392, 8.242, 11.392)
        ..lineTo(5.818, 11.392)
        ..cubicTo(5.702, 11.392, 5.589, 11.406, 5.479, 11.426)
        ..cubicTo(5.742, 8.091, 8.564, 5.454, 12, 5.454)
        ..cubicTo(15.436, 5.454, 18.258, 8.091, 18.52, 11.426)
        ..cubicTo(18.411, 11.405, 18.298, 11.392, 18.182, 11.392)
        ..lineTo(15.758, 11.392)
        ..cubicTo(14.756, 11.392, 13.94, 12.204, 13.94, 13.201)
        ..lineTo(13.94, 18.192)
        ..cubicTo(13.94, 19.189, 14.756, 20, 15.758, 20)
        ..lineTo(18.182, 20)
        ..cubicTo(19.184, 20, 20, 19.189, 20, 18.192)
        ..lineTo(20, 15.318)..lineTo(20, 13.201)..lineTo(20, 11.933)
        ..cubicTo(20, 7.559, 16.412, 4, 12, 4)
        ..close()
        ..moveTo(5.818, 12.847)
        ..lineTo(8.242, 12.847)
        ..cubicTo(8.443, 12.847, 8.605, 13.006, 8.605, 13.201)
        ..lineTo(8.605, 18.192)
        ..cubicTo(8.605, 18.386, 8.443, 18.546, 8.242, 18.546)
        ..lineTo(5.818, 18.546)
        ..cubicTo(5.617, 18.546, 5.454, 18.387, 5.454, 18.192)
        ..lineTo(5.454, 15.318)..lineTo(5.454, 13.201)
        ..cubicTo(5.454, 13.006, 5.617, 12.847, 5.818, 12.847)
        ..close()
        ..moveTo(18.546, 18.192)
        ..cubicTo(18.546, 18.386, 18.383, 18.546, 18.182, 18.546)
        ..lineTo(15.758, 18.546)
        ..cubicTo(15.557, 18.546, 15.393, 18.387, 15.393, 18.192)
        ..lineTo(15.393, 13.201)
        ..cubicTo(15.393, 13.006, 15.557, 12.847, 15.758, 12.847)
        ..lineTo(18.182, 12.847)
        ..cubicTo(18.383, 12.847, 18.546, 13.006, 18.546, 13.201)
        ..lineTo(18.546, 15.318)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReadAloudPainter old) => old.color != color;
}

// ic_interface_setting.xml
class _InterfaceSettingPainter extends CustomPainter {
  final Color color;
  _InterfaceSettingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(8.348, 3.999)
        ..lineTo(4, 19.977)
        ..lineTo(5.59, 19.977)
        ..lineTo(6.834, 15.136)
        ..lineTo(11.566, 15.136)
        ..lineTo(12.887, 19.977)
        ..lineTo(14.593, 19.977)
        ..lineTo(9.96, 3.999)
        ..close()
        ..moveTo(7.266, 13.414)
        ..lineTo(8.509, 8.727)
        ..cubicTo(8.772, 7.717, 8.975, 6.701, 9.119, 5.675)
        ..cubicTo(9.293, 6.54, 9.562, 7.645, 9.922, 8.988)
        ..lineTo(11.106, 13.414)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(20.261, 19.962)
        ..lineTo(20.154, 19.731)
        ..cubicTo(20.038, 19.48, 19.959, 19.216, 19.919, 18.948)
        ..cubicTo(19.892, 18.748, 19.859, 18.227, 19.859, 16.884)
        ..lineTo(19.859, 15.303)
        ..cubicTo(19.859, 14.787, 19.84, 14.398, 19.804, 14.172)
        ..cubicTo(19.739, 13.814, 19.628, 13.525, 19.466, 13.289)
        ..cubicTo(19.299, 13.046, 19.041, 12.844, 18.701, 12.69)
        ..cubicTo(18.362, 12.537, 17.938, 12.461, 17.404, 12.461)
        ..cubicTo(16.875, 12.461, 16.403, 12.549, 16.005, 12.724)
        ..cubicTo(15.587, 12.904, 15.274, 13.159, 15.044, 13.503)
        ..cubicTo(14.832, 13.825, 14.69, 14.243, 14.622, 14.73)
        ..cubicTo(14.617, 14.745, 14.613, 14.758, 14.608, 14.775)
        ..lineTo(14.561, 14.983)
        ..lineTo(15.901, 15.164)
        ..lineTo(15.933, 15.011)
        ..cubicTo(16.029, 14.567, 16.177, 14.245, 16.363, 14.082)
        ..cubicTo(16.55, 13.919, 16.843, 13.84, 17.261, 13.84)
        ..cubicTo(17.705, 13.84, 18.027, 13.951, 18.244, 14.18)
        ..cubicTo(18.39, 14.335, 18.469, 14.642, 18.469, 15.062)
        ..lineTo(18.468, 15.237)
        ..cubicTo(18.106, 15.37, 17.57, 15.488, 16.869, 15.589)
        ..cubicTo(16.46, 15.648, 16.162, 15.708, 15.96, 15.776)
        ..cubicTo(15.676, 15.87, 15.416, 16.011, 15.187, 16.198)
        ..cubicTo(14.954, 16.386, 14.763, 16.639, 14.619, 16.951)
        ..cubicTo(14.479, 17.262, 14.409, 17.605, 14.409, 17.972)
        ..cubicTo(14.409, 18.606, 14.599, 19.135, 14.975, 19.546)
        ..cubicTo(15.355, 19.962, 15.901, 20.173, 16.598, 20.173)
        ..cubicTo(17.008, 20.173, 17.402, 20.089, 17.768, 19.924)
        ..cubicTo(18.037, 19.802, 18.317, 19.595, 18.594, 19.314)
        ..cubicTo(18.636, 19.54, 18.699, 19.737, 18.787, 19.919)
        ..lineTo(18.835, 20.019)
        ..lineTo(19.683, 19.987)
        ..lineTo(20.246, 19.966)
        ..close()
        ..moveTo(18.464, 16.601)
        ..lineTo(18.464, 16.737)
        ..cubicTo(18.464, 17.231, 18.415, 17.606, 18.319, 17.848)
        ..cubicTo(18.192, 18.163, 18.002, 18.404, 17.738, 18.581)
        ..cubicTo(17.478, 18.757, 17.175, 18.846, 16.834, 18.846)
        ..cubicTo(16.501, 18.846, 16.269, 18.765, 16.101, 18.591)
        ..cubicTo(15.938, 18.418, 15.858, 18.205, 15.858, 17.938)
        ..cubicTo(15.858, 17.762, 15.896, 17.605, 15.975, 17.465)
        ..cubicTo(16.043, 17.331, 16.143, 17.232, 16.277, 17.162)
        ..cubicTo(16.427, 17.085, 16.698, 17.012, 17.08, 16.945)
        ..cubicTo(17.645, 16.848, 18.109, 16.732, 18.464, 16.601)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InterfaceSettingPainter old) => old.color != color;
}

// ic_settings.xml
class _SettingsPainter extends CustomPainter {
  final Color color;
  _SettingsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    canvas.drawPath(
      Path()
        ..moveTo(12, 15.43)
        ..cubicTo(10.109, 15.43, 8.572, 13.891, 8.572, 12)
        ..cubicTo(8.572, 10.109, 10.109, 8.57, 12, 8.57)
        ..cubicTo(13.891, 8.57, 15.428, 10.109, 15.428, 12)
        ..cubicTo(15.428, 13.891, 13.891, 15.43, 12, 15.43)
        ..close()
        ..moveTo(12, 10.096)
        ..cubicTo(10.949, 10.096, 10.096, 10.95, 10.096, 12)
        ..cubicTo(10.096, 13.05, 10.95, 13.904, 12, 13.904)
        ..cubicTo(13.051, 13.904, 13.904, 13.05, 13.904, 12)
        ..cubicTo(13.904, 10.95, 13.051, 10.096, 12, 10.096)
        ..close(),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(13.735, 20)
        ..lineTo(10.261, 20)
        ..lineTo(10.12, 18.065)
        ..cubicTo(10.102, 17.807, 9.944, 17.585, 9.721, 17.492)
        ..cubicTo(9.472, 17.387, 9.214, 17.429, 9.024, 17.592)
        ..lineTo(7.568, 18.848)
        ..lineTo(5.113, 16.391)
        ..lineTo(6.369, 14.937)
        ..cubicTo(6.531, 14.749, 6.573, 14.49, 6.477, 14.258)
        ..cubicTo(6.376, 14.013, 6.166, 13.857, 5.913, 13.836)
        ..lineTo(4, 13.697)
        ..lineTo(4, 10.226)
        ..lineTo(5.916, 10.085)
        ..cubicTo(6.164, 10.066, 6.378, 9.913, 6.473, 9.683)
        ..cubicTo(6.574, 9.438, 6.536, 9.185, 6.371, 8.992)
        ..lineTo(5.113, 7.539)
        ..lineTo(7.573, 5.094)
        ..lineTo(9.026, 6.376)
        ..cubicTo(9.222, 6.544, 9.495, 6.605, 9.703, 6.522)
        ..lineTo(9.844, 6.461)
        ..cubicTo(10.026, 6.273, 10.107, 6.141, 10.119, 5.974)
        ..lineTo(10.262, 4)
        ..lineTo(13.734, 4)
        ..lineTo(13.877, 5.894)
        ..cubicTo(13.895, 6.139, 14.041, 6.335, 14.277, 6.43)
        ..cubicTo(14.527, 6.537, 14.786, 6.494, 14.975, 6.332)
        ..lineTo(16.427, 5.073)
        ..lineTo(18.886, 7.531)
        ..lineTo(17.629, 8.984)
        ..cubicTo(17.467, 9.172, 17.426, 9.431, 17.521, 9.664)
        ..cubicTo(17.622, 9.909, 17.833, 10.066, 18.085, 10.085)
        ..lineTo(20, 10.227)
        ..lineTo(20, 13.698)
        ..lineTo(18.085, 13.837)
        ..cubicTo(17.837, 13.858, 17.623, 14.011, 17.528, 14.242)
        ..cubicTo(17.426, 14.487, 17.465, 14.747, 17.63, 14.94)
        ..lineTo(18.886, 16.391)
        ..lineTo(16.429, 18.85)
        ..lineTo(14.975, 17.594)
        ..cubicTo(14.799, 17.444, 14.544, 17.398, 14.322, 17.479)
        ..lineTo(14.295, 17.493)
        ..cubicTo(14.051, 17.594, 13.894, 17.816, 13.876, 18.068)
        ..lineTo(13.735, 20)
        ..close()
        ..moveTo(11.561, 18.604)
        ..lineTo(12.437, 18.604)
        ..lineTo(12.482, 17.963)
        ..cubicTo(12.538, 17.216, 13.011, 16.538, 13.691, 16.232)
        ..lineTo(13.737, 16.211)
        ..cubicTo(14.526, 15.883, 15.308, 16.04, 15.886, 16.54)
        ..lineTo(16.358, 16.945)
        ..lineTo(16.98, 16.321)
        ..lineTo(16.574, 15.852)
        ..cubicTo(16.064, 15.26, 15.933, 14.446, 16.231, 13.725)
        ..cubicTo(16.535, 12.993, 17.206, 12.502, 17.982, 12.446)
        ..lineTo(18.604, 12.399)
        ..lineTo(18.604, 11.524)
        ..lineTo(17.984, 11.477)
        ..cubicTo(17.207, 11.421, 16.536, 10.938, 16.239, 10.215)
        ..cubicTo(15.935, 9.485, 16.065, 8.664, 16.574, 8.07)
        ..lineTo(16.98, 7.601)
        ..lineTo(16.358, 6.979)
        ..lineTo(15.886, 7.386)
        ..cubicTo(15.308, 7.885, 14.472, 8.022, 13.761, 7.729)
        ..cubicTo(13.029, 7.428, 12.54, 6.763, 12.482, 5.996)
        ..lineTo(12.438, 5.397)
        ..lineTo(11.558, 5.397)
        ..lineTo(11.514, 6)
        ..cubicTo(11.457, 6.773, 10.973, 7.438, 10.252, 7.733)
        ..lineTo(10.091, 7.789)
        ..cubicTo(9.416, 8.008, 8.652, 7.856, 8.112, 7.392)
        ..lineTo(7.639, 6.982)
        ..lineTo(7.02, 7.602)
        ..lineTo(7.426, 8.075)
        ..cubicTo(7.936, 8.665, 8.067, 9.479, 7.77, 10.202)
        ..cubicTo(7.467, 10.931, 6.796, 11.422, 6.02, 11.477)
        ..lineTo(5.397, 11.524)
        ..lineTo(5.397, 12.399)
        ..lineTo(6.019, 12.446)
        ..cubicTo(6.796, 12.503, 7.465, 12.987, 7.762, 13.71)
        ..cubicTo(8.066, 14.44, 7.935, 15.261, 7.426, 15.852)
        ..lineTo(7.02, 16.32)
        ..lineTo(7.64, 16.941)
        ..lineTo(8.112, 16.535)
        ..cubicTo(8.692, 16.035, 9.528, 15.898, 10.239, 16.194)
        ..cubicTo(10.958, 16.488, 11.454, 17.163, 11.514, 17.932)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SettingsPainter old) => old.color != color;
}

class _ReducePainter extends CustomPainter {
  final Color color;
  _ReducePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final s = size.width / 24;
    canvas.drawRect(Rect.fromLTRB(5 * s, 11 * s, 19 * s, 13 * s), paint);
  }

  @override
  bool shouldRepaint(covariant _ReducePainter old) => old.color != color;
}

class _AddPainter extends CustomPainter {
  final Color color;
  _AddPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final s = size.width / 24;
    canvas.drawPath(
      Path()
        ..moveTo(12.822 * s, 20 * s)
        ..lineTo(11.177 * s, 20 * s)
        ..lineTo(11.177 * s, 12.821 * s)
        ..lineTo(4 * s, 12.821 * s)
        ..lineTo(4 * s, 11.178 * s)
        ..lineTo(11.178 * s, 11.178 * s)
        ..lineTo(11.178 * s, 4 * s)
        ..lineTo(12.823 * s, 4 * s)
        ..lineTo(12.823 * s, 11.179 * s)
        ..lineTo(20 * s, 11.179 * s)
        ..lineTo(20 * s, 12.822 * s)
        ..lineTo(12.822 * s, 12.822 * s)
        ..lineTo(12.822 * s, 20 * s)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AddPainter old) => old.color != color;
}

// ── 朗读弹窗图标 painter(对齐原生 drawable 矢量路径) ──

// ic_skip_previous.xml
class _SkipPreviousPainter extends CustomPainter {
  final Color color;
  _SkipPreviousPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(6, 6)..lineTo(8, 6)..lineTo(8, 18)..lineTo(6, 18)..close()
        ..moveTo(9.5, 12)..lineTo(18, 18)..lineTo(18, 6)..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkipPreviousPainter old) => old.color != color;
}

// ic_skip_next.xml
class _SkipNextPainter extends CustomPainter {
  final Color color;
  _SkipNextPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(6, 18)..lineTo(14.5, 12)..lineTo(6, 6)..close()
        ..moveTo(16, 6)..lineTo(16, 18)..lineTo(18, 18)..lineTo(18, 6)..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkipNextPainter old) => old.color != color;
}

// ic_play_24dp.xml
class _PlayPainter extends CustomPainter {
  final Color color;
  _PlayPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()..moveTo(8, 5)..lineTo(8, 19)..lineTo(19, 12)..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlayPainter old) => old.color != color;
}

// ic_pause_24dp.xml
class _PausePainter extends CustomPainter {
  final Color color;
  _PausePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(6, 19)..lineTo(10, 19)..lineTo(10, 5)..lineTo(6, 5)..close()
        ..moveTo(14, 5)..lineTo(14, 19)..lineTo(18, 19)..lineTo(18, 5)..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PausePainter old) => old.color != color;
}

// ic_stop_black_24dp.xml
class _StopPainter extends CustomPainter {
  final Color color;
  _StopPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawRect(Rect.fromLTWH(6 * s, 6 * s, 12 * s, 12 * s), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StopPainter old) => old.color != color;
}

// ic_time_add_24dp.xml (viewport 1000)
class _TimerPainter extends CustomPainter {
  final Color color;
  _TimerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 1000;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        // 上箭头左翼
        ..moveTo(698.24, 166.67)
        ..lineTo(869.37, 309.50)
        ..lineTo(821.82, 366.52)
        ..lineTo(650.58, 223.76)
        ..close()
        // 上箭头右翼
        ..moveTo(301.73, 166.67)
        ..lineTo(349.35, 223.72)
        ..lineTo(178.18, 366.52)
        ..lineTo(130.63, 309.46)
        ..close()
        // 钟外圈
        ..moveTo(499.98, 248.02)
        ..cubicTo(315.36, 248.02, 165.66, 397.72, 165.66, 582.34)
        ..cubicTo(165.66, 766.96, 315.36, 916.67, 499.98, 916.67)
        ..cubicTo(684.60, 916.67, 834.31, 766.96, 834.31, 582.34)
        ..cubicTo(834.31, 397.72, 684.60, 248.02, 499.98, 248.02)
        ..close()
        ..moveTo(499.98, 842.37)
        ..cubicTo(356.59, 842.37, 239.95, 725.73, 239.95, 582.34)
        ..cubicTo(239.95, 438.95, 356.59, 322.31, 499.98, 322.31)
        ..cubicTo(643.37, 322.31, 760.01, 438.95, 760.01, 582.34)
        ..cubicTo(760.01, 725.73, 643.37, 842.37, 499.98, 842.37)
        ..close()
        // 钟内十字(加号)
        ..moveTo(537.13, 433.75)
        ..lineTo(462.83, 433.75)
        ..lineTo(462.83, 545.20)
        ..lineTo(351.39, 545.20)
        ..lineTo(351.39, 619.49)
        ..lineTo(462.83, 619.49)
        ..lineTo(462.83, 730.93)
        ..lineTo(537.13, 730.93)
        ..lineTo(537.13, 619.49)
        ..lineTo(648.57, 619.49)
        ..lineTo(648.57, 545.20)
        ..lineTo(537.13, 545.20)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimerPainter old) => old.color != color;
}

// ic_menu.xml
class _MainMenuPainter extends CustomPainter {
  final Color color;
  _MainMenuPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    // 三条横线(汉堡菜单), 用矩形填充。
    canvas.drawRect(Rect.fromLTWH(3 * s, 16 * s, 18 * s, 2 * s), paint);
    canvas.drawRect(Rect.fromLTWH(3 * s, 11 * s, 18 * s, 2 * s), paint);
    canvas.drawRect(Rect.fromLTWH(3 * s, 6 * s, 18 * s, 2 * s), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MainMenuPainter old) => old.color != color;
}

// ic_visibility_off.xml
class _VisibilityOffPainter extends CustomPainter {
  final Color color;
  _VisibilityOffPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(
      Path()
        ..moveTo(12, 7)
        ..cubicTo(14.76, 7, 17, 9.24, 17, 12)
        ..cubicTo(17, 12.65, 16.87, 13.26, 16.64, 13.83)
        ..lineTo(19.56, 16.75)
        ..cubicTo(21.07, 15.49, 22.26, 13.86, 22.99, 12)
        ..cubicTo(21.26, 7.61, 16.99, 4.5, 11.99, 4.5)
        ..cubicTo(10.59, 4.5, 9.25, 4.75, 8.01, 5.2)
        ..lineTo(10.17, 7.36)
        ..cubicTo(10.74, 7.13, 11.35, 7, 12, 7)
        ..close()
        ..moveTo(2, 4.27)
        ..lineTo(4.28, 6.55)
        ..lineTo(4.74, 7.01)
        ..cubicTo(3.08, 8.3, 1.78, 10.02, 1, 12)
        ..cubicTo(2.73, 16.39, 7, 19.5, 12, 19.5)
        ..cubicTo(13.55, 19.5, 15.03, 19.2, 16.38, 18.66)
        ..lineTo(16.8, 19.08)
        ..lineTo(19.73, 22)
        ..lineTo(21, 20.73)
        ..lineTo(3.27, 3)
        ..close()
        ..moveTo(7.53, 9.8)
        ..lineTo(9.08, 11.35)
        ..cubicTo(9.03, 11.56, 9, 11.78, 9, 12)
        ..cubicTo(9, 13.66, 10.34, 15, 12, 15)
        ..cubicTo(12.22, 15, 12.44, 14.97, 12.65, 14.92)
        ..lineTo(14.2, 16.47)
        ..cubicTo(13.53, 16.8, 12.79, 17, 12, 17)
        ..cubicTo(9.24, 17, 7, 14.76, 7, 12)
        ..cubicTo(7, 11.21, 7.2, 10.47, 7.53, 9.8)
        ..close()
        ..moveTo(11.84, 9.02)
        ..lineTo(14.99, 12.17)
        ..lineTo(15.01, 12.01)
        ..cubicTo(15.01, 10.35, 13.67, 9.01, 12.01, 9.01)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VisibilityOffPainter old) => old.color != color;
}
