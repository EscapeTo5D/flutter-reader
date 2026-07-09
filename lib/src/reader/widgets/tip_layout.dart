import 'package:flutter/material.dart';

import '../../core/models/reading_settings.dart';

/// 页眉/页脚 tip 文字与电量图标的尺寸常量。
///
/// 这些常量被 [measureTipContentHeight]（排版预算用）与 `page_view.dart` 的
/// 渲染（[_BatteryIcon] / `_buildTip`）**同时引用**, 保证"预算测出来的高度" ==
/// "实际渲染高度", 不出现正文与页脚错位。修改任何一个值都要两边同步(此处是
/// 唯一真相源, 改这里即可)。
const double kTipTextSize = 12.0;
const double kTipTimeBatteryTextSize = 11.0;
const double kBatteryIconSize = 18.0;
const double kTimeBatteryIconSize = 16.0;
const double kBatteryIconAspect = 0.6; // _BatteryIcon: Size(size, size * 0.6)

/// 测量单个 [TipPosition] 槽位的渲染高度(px)。
///
/// 逐分支镜像 `page_view._buildTip` 的渲染尺寸: 纯文字用 TextPainter 测单行高;
/// 电量图标按 `size × aspect`; timeAndBattery 取文字与图标两者最大。返回值与
/// 实际渲染行高一致, 供排版预算(nonContentHeight)使用。
///
/// 性能: 单行短文本 TextPainter.layout ~微秒级, 调一次页眉/页脚各 3 槽 = 6 次,
/// 相对排版本身(~170ms)可忽略, 不做缓存。
///
/// `direction` 与 `textScaleFactor` 未显式传, 默认从环境取; tip 均为单行短文本,
/// 不换行, 与 `_buildTip` 里 `Text` 不设 `softWrap` 的默认行为一致。
double measureTipContentHeight(ReadingSettings settings, TipPosition pos) {
  switch (pos) {
    case TipPosition.none:
      return 0;
    case TipPosition.battery:
      // _BatteryIcon: Size(size, size * aspect)
      return kBatteryIconSize * kBatteryIconAspect;
    case TipPosition.timeAndBattery:
      // 文字 11sp + 旁边 16px 电量图标, Row(min) → 取较高者
      final textH = _measureSingleLineText(
        '00:00',
        kTipTimeBatteryTextSize,
        settings.fontFamily,
        settings.tipColor,
      );
      final iconH = kTimeBatteryIconSize * kBatteryIconAspect;
      return textH > iconH ? textH : iconH;
    case TipPosition.chapterTitle:
    case TipPosition.time:
    case TipPosition.batteryPercent:
    case TipPosition.pageNumber:
    case TipPosition.progress:
    case TipPosition.bookName:
    case TipPosition.pageAndTotal:
      // 纯文字槽: 12sp, 不限宽(ellipsize=end, 但单行高度只看字号)
      return _measureSingleLineText(
        _probeText(pos),
        kTipTextSize,
        settings.fontFamily,
        settings.tipColor,
      );
  }
}

/// 测量一组页眉/页脚配置(三槽)的整体内容行高 = 三槽最高者。
///
/// `cfg.hidden` 直接返回 0(整体隐藏, 不占内容行高)。外层四向 padding
/// (footerTop/Bottom/Left/Right)不在此函数职责内, 由 caller 另行累加 ——
/// 对齐 `Padding` + `Row` 结构(padding 在 Row 外, 不影响 Row 内高度)。
double measureChromeContentHeight(
    ReadingSettings settings, HeaderFooterConfig cfg) {
  if (cfg.hidden) return 0;
  final l = measureTipContentHeight(settings, cfg.left);
  final c = measureTipContentHeight(settings, cfg.center);
  final r = measureTipContentHeight(settings, cfg.right);
  var m = l;
  if (c > m) m = c;
  if (r > m) m = r;
  return m;
}

// ─────────────────────────── helpers ───────────────────────────

/// 用一个代表样本测单行文字高度(高度只取决于字号/字体, 与具体字符无关)。
/// 显式传 `maxWidth: double.infinity` + `textWidthBasis: TextWidthBasis.parent`
/// 让 layout 一次性完成不换行。
double _measureSingleLineText(
    String text, double fontSize, String? fontFamily, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontFamily: fontFamily,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  painter.layout(maxWidth: double.infinity);
  final h = painter.height;
  painter.dispose();
  return h;
}

/// 给文字槽一个稳定测高样本(高度只看字号/字体, 内容任意)。
String _probeText(TipPosition pos) {
  switch (pos) {
    case TipPosition.chapterTitle:
    case TipPosition.bookName:
      return '书';
    case TipPosition.time:
      return '00:00';
    case TipPosition.batteryPercent:
      return '0%';
    case TipPosition.pageNumber:
    case TipPosition.pageAndTotal:
      return '0/0';
    case TipPosition.progress:
      return '0.0%';
    case TipPosition.none:
    case TipPosition.battery:
    case TipPosition.timeAndBattery:
      return ''; // 这些分支不走文字测量
  }
}
