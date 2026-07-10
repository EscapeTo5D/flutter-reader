import 'package:flutter/material.dart';

import 'legado_icons.dart';

/// 精细滑块, 复刻原生 legado `DetailSeekBar`
/// (`app/src/main/res/layout/view_detail_seek_bar.xml` + `DetailSeekBar.kt`)。
///
/// 结构(左→右): `[标题 60dp][− 24dp][Slider 4weight][+ 24dp][值 60dp]`。
/// 标题/±/值文字色随 [textColor](对齐原生 isBottomBackground 时用 primaryText)。
///
/// **回调语义(对齐原生 DetailSeekBar.kt)**:
/// 原生 `onProgressChanged`(拖动每 tick) 只调 `upValue()` 刷新数字显示,
/// `onStopTrackingTouch`(松手) 才调 `onChanged` 业务回调(重排/写配置)。
/// 这里拆成两个回调对齐该行为:
/// - [onChanged]: 拖动每 tick 实时回调, **只用于刷新右侧显示文本**(原生 upValue)。
///   不应在此触发重排/落库等重操作。
/// - [onChangeEnd]: 松手(或点 ±按钮)才回调, 触发重排/写配置等确定操作。
///
/// [display] 文本随 [progress] 由父 widget 算好传入; 拖动期间父 widget 在
/// [onChanged] 里 setState 更新 [progress] → 本控件重绘新数字。
class DetailSeekBar extends StatelessWidget {
  final String title;
  final int progress;
  final int max;
  /// 当前值的显示文本(原生 valueFormat: (Int)->String)。
  final String display;
  /// 拖动中实时回调(对齐原生 onProgressChanged → upValue: 刷新数字显示)。
  /// 松手前的中间值经此回调; **不应在此触发重排**。
  final ValueChanged<int> onChanged;
  /// 松手(拖动结束)或点 ±按钮才回调(对齐原生 onStopTrackingTouch → onChanged:
  /// 触发重排/写配置等确定操作)。
  final ValueChanged<int> onChangeEnd;
  final Color? textColor;
  final Color? activeColor;

  const DetailSeekBar({
    super.key,
    required this.title,
    required this.progress,
    required this.max,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
    this.textColor,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Colors.black87;
    final accent = activeColor ?? Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(title, style: TextStyle(fontSize: 13, color: fg)),
        ),
        _buildButton(LegadoIcons.reduce(size: 24, color: fg), () {
          final v = (progress - 1).clamp(0, max);
          if (v != progress) onChangeEnd(v);
        }),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              thumbColor: accent,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: progress.toDouble().clamp(0, max.toDouble()),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              onChanged: (v) => onChanged(v.round()),
              onChangeEnd: (v) => onChangeEnd(v.round()),
            ),
          ),
        ),
        _buildButton(LegadoIcons.add(size: 24, color: fg), () {
          final v = (progress + 1).clamp(0, max);
          if (v != progress) onChangeEnd(v);
        }),
        SizedBox(
          width: 60,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: fg),
          ),
        ),
      ],
    );
  }

  Widget _buildButton(Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 24, height: 24, child: icon),
    );
  }
}
