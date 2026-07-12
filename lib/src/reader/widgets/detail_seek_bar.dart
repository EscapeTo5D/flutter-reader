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
              // divisions 用于吸附, 但不画刻度小点(对齐原生 SeekBar 视觉,
              // 字距 max=100 / 字号 max=45 否则会有密密麻麻的 tick marks)。
              tickMarkShape: SliderTickMarkShape.noTickMark,
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
    // 视觉占位仍是 24×24(不撑高 Row), 触摸热区用 OverflowBox 溢出到上下相邻
    // 行间隙, 变成 24×44 —— 对齐 iOS 44pt 最小触摸推荐, 又不动整体布局。
    //
    // 反馈效果对齐原生 `?android:attr/selectableItemBackgroundBorderless`
    // (view_detail_seek_bar.xml:24,41):无边界圆形涟漪。
    //
    // ⚠️ 踩坑记录(2026-07-13, 别再重蹈):
    // 手写 InkResponse/InkWell + 自套透明 Material 调了 5 轮, 始终出现"圆+方两层"。
    // 排查结论:
    //   - 诊断版去掉自套 Material → 完全无反馈, 证明**弹窗(SmartDialog)脱离
    //     MaterialApp 的 Material 树**, 无祖先 Material 可用。
    //   - 自套 Material 是必须的, 但其 ink 表面会同时渲染 splash(圆) + highlight(被
    //     clip 成方), 两层叠加 = "圆 + 方"。highlightColor:transparent / overlayColor
    //     都无法干净分离(overlayColor 优先级最高会同时关掉 splash)。
    //   - 根本原因: SmartDialog 用独立 Overlay 渲染弹窗, 脱离 MaterialApp 的 Material,
    //     ink 机制在这个上下文里不可靠。
    // 最终方案: 放弃 ink 机制, 用 StatefulWidget 自管理按下态 + AnimatedOpacity 手画
    // 圆形背景。完全可控, 不依赖 Material/ink, 不依赖祖先 surface, 不会有两层。
    return SizedBox(
      width: 24,
      height: 24,
      child: OverflowBox(
        minWidth: 44,
        maxWidth: 44,
        minHeight: 44,
        maxHeight: 44,
        alignment: Alignment.center,
        child: _RippleButton(icon: icon, onTap: onTap),
      ),
    );
  }
}

/// 自管理按下态的圆形 ripple 按钮。
///
/// 放弃 InkWell/InkResponse 的 ink 机制(SmartDialog 弹窗脱离 MaterialApp 的 Material
/// 树, ink surface 不可靠, 会同时渲染 splash+highlight 两层)。这里用 GestureDetector
/// 监听按下/抬起 + AnimatedOpacity 手画圆形背景, 完全可控:
/// - 按下(tapDown): 圆形背景淡入(模拟 borderless ripple 出现)
/// - 抬起/取消(tapUp/cancel): 圆形背景淡出
/// - tap: 触发回调
///
/// 视觉: 22 半径的浅灰圆(black12 → 透明), 对齐原生 selectableItemBackgroundBorderless
/// 的圆形涟漪观感(不带扩散动画, 只淡入淡出; 扩散动画用 AnimatedContainer 半径过渡
/// 会增加复杂度, 当前简化为淡入淡出, 观感接近且无 ink 机制问题)。
class _RippleButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _RippleButton({required this.icon, required this.onTap});

  @override
  State<_RippleButton> createState() => _RippleButtonState();
}

class _RippleButtonState extends State<_RippleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: SizedBox(
        width: 24,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 圆形 ripple 背景: 44×44 圆(black12), 按下时淡入。
            // 用 IgnorePointer 不挡图标点击, Positioned.fill 撑满 OverflowBox 的 44×44。
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _pressed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.black12,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // 图标在最上层。
            widget.icon,
          ],
        ),
      ),
    );
  }
}
