import 'package:flutter/material.dart';

import 'legado_icons.dart';

/// 精细滑块, 复刻原生 legado `DetailSeekBar`
/// (`app/src/main/res/layout/view_detail_seek_bar.xml` + `DetailSeekBar.kt`)。
///
/// 结构(左→右): `[标题 60dp][− 24dp][Slider 4weight][+ 24dp][值 60dp]`。
/// 标题/±/值文字色随 [textColor](对齐原生 isBottomBackground 时用 primaryText)。
/// 拖动中实时触发 onChanged(与现有 _StyleDialog 滑块行为一致; 排版有防抖兜底)。
class DetailSeekBar extends StatelessWidget {
  final String title;
  final int progress;
  final int max;
  /// 当前值的显示文本(原生 valueFormat: (Int)->String)。
  final String display;
  /// 值变化回调(松手或 ± 触发)。
  final ValueChanged<int> onChanged;
  final Color? textColor;
  final Color? activeColor;

  const DetailSeekBar({
    super.key,
    required this.title,
    required this.progress,
    required this.max,
    required this.display,
    required this.onChanged,
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
          if (progress > 0) onChanged(progress - 1);
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
            ),
          ),
        ),
        _buildButton(LegadoIcons.add(size: 24, color: fg), () {
          if (progress < max) onChanged(progress + 1);
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
