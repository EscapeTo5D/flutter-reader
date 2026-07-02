import 'package:flutter/material.dart';
import 'reading_settings.dart';

/// ReadingSettings 及其嵌套配置的 JSON 序列化编解码器。
///
/// 模型类本身保持纯净(无 toJson/fromJson), 序列化逻辑集中于此, 便于维护与
/// schema 演进。Color → 0xAARRGGBB int, 枚举 → .name, 嵌套 config 各自编解码。
///
/// schema 版本: 写入时带 `_version` 字段, 未来字段增删/重命名时用版本号做迁移。

const int _kSettingsSchemaVersion = 1;

// ─────────────────────────── Color / 枚举 工具 ───────────────────────────

int _colorToJson(Color c) => c.toARGB32();

// 注: Color.fromARGB32() 在 Flutter 3.41 尚不可用, 用 Color(value) 构造(value 已弃用
// 但仍是 3.41 唯一的 int→Color 入口; 升级到含 fromARGB32 的版本后改用之)。
// ignore: deprecated_member_use
Color _colorFromJson(int value) => Color(value);

String? _fontToJson(String? f) => f;

String? _fontFromJson(dynamic v) => v?.toString();

// ─────────────────────────── HeaderFooterConfig ───────────────────────────

Map<String, dynamic> _headerFooterToJson(HeaderFooterConfig c) => {
      'left': c.left.name,
      'center': c.center.name,
      'right': c.right.name,
      'hidden': c.hidden,
    };

HeaderFooterConfig _headerFooterFromJson(Map<String, dynamic> json) =>
    HeaderFooterConfig(
      left: _tipFromName(json['left'], TipPosition.chapterTitle),
      center: _tipFromName(json['center'], TipPosition.none),
      right: _tipFromName(json['right'], TipPosition.pageNumber),
      hidden: (json['hidden'] as bool?) ?? false,
    );

TipPosition _tipFromName(dynamic name, TipPosition fallback) {
  if (name == null) return fallback;
  for (final v in TipPosition.values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ─────────────────────────── ReaderPadding ───────────────────────────

Map<String, dynamic> _paddingToJson(ReaderPadding p) => {
      'top': p.top,
      'bottom': p.bottom,
      'left': p.left,
      'right': p.right,
      'headerHeight': p.headerHeight,
      'footerHeight': p.footerHeight,
      'headerTop': p.headerTop,
      'headerBottom': p.headerBottom,
      'headerLeft': p.headerLeft,
      'headerRight': p.headerRight,
      'footerTop': p.footerTop,
      'footerBottom': p.footerBottom,
      'footerLeft': p.footerLeft,
      'footerRight': p.footerRight,
    };

ReaderPadding _paddingFromJson(Map<String, dynamic> json) {
  const d = ReaderPadding();
  return ReaderPadding(
    top: _asDouble(json['top'], d.top),
    bottom: _asDouble(json['bottom'], d.bottom),
    left: _asDouble(json['left'], d.left),
    right: _asDouble(json['right'], d.right),
    headerHeight: _asDouble(json['headerHeight'], d.headerHeight),
    footerHeight: _asDouble(json['footerHeight'], d.footerHeight),
    headerTop: _asDouble(json['headerTop'], d.headerTop),
    headerBottom: _asDouble(json['headerBottom'], d.headerBottom),
    headerLeft: _asDouble(json['headerLeft'], d.headerLeft),
    headerRight: _asDouble(json['headerRight'], d.headerRight),
    footerTop: _asDouble(json['footerTop'], d.footerTop),
    footerBottom: _asDouble(json['footerBottom'], d.footerBottom),
    footerLeft: _asDouble(json['footerLeft'], d.footerLeft),
    footerRight: _asDouble(json['footerRight'], d.footerRight),
  );
}

// ─────────────────────────── ClickRegionConfig ───────────────────────────

Map<String, dynamic> _clickConfigToJson(ClickRegionConfig c) => {
      'topLeft': c.topLeft.name,
      'topCenter': c.topCenter.name,
      'topRight': c.topRight.name,
      'middleLeft': c.middleLeft.name,
      'center': c.center.name,
      'middleRight': c.middleRight.name,
      'bottomLeft': c.bottomLeft.name,
      'bottomCenter': c.bottomCenter.name,
      'bottomRight': c.bottomRight.name,
    };

ClickRegionConfig _clickConfigFromJson(Map<String, dynamic> json) {
  // 用默认实例兜底逐字段, 缺失字段回落默认
  const d = ClickRegionConfig();
  return ClickRegionConfig(
    topLeft: _actionFromName(json['topLeft'], d.topLeft),
    topCenter: _actionFromName(json['topCenter'], d.topCenter),
    topRight: _actionFromName(json['topRight'], d.topRight),
    middleLeft: _actionFromName(json['middleLeft'], d.middleLeft),
    center: _actionFromName(json['center'], d.center),
    middleRight: _actionFromName(json['middleRight'], d.middleRight),
    bottomLeft: _actionFromName(json['bottomLeft'], d.bottomLeft),
    bottomCenter: _actionFromName(json['bottomCenter'], d.bottomCenter),
    bottomRight: _actionFromName(json['bottomRight'], d.bottomRight),
  );
}

ClickAction _actionFromName(dynamic name, ClickAction fallback) {
  if (name == null) return fallback;
  for (final v in ClickAction.values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ─────────────────────────── 辅助: 宽松数值解析 ───────────────────────────
// JSON 反序列化时 int/double 类型可能混存(int 写入, double 读出), 统一转 double。
double _asDouble(dynamic v, double fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

int _asInt(dynamic v, int fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

// ─────────────────────────── ReadingSettings 主编解码 ───────────────────────────

/// 把 [ReadingSettings] 编码为可 JSON 序列化的 Map。
///
/// 含 schema 版本号 `_version`, 供 [decodeReadingSettings] 做兼容迁移。
Map<String, dynamic> encodeReadingSettings(ReadingSettings s) {
  return <String, dynamic>{
    '_version': _kSettingsSchemaVersion,
    'fontSize': s.fontSize,
    'fontWeight': _fontWeightToJson(s.fontWeight),
    'lineHeight': s.lineHeight,
    'paragraphSpacing': s.paragraphSpacing,
    'letterSpacing': s.letterSpacing,
    'backgroundColor': _colorToJson(s.backgroundColor),
    'textColor': _colorToJson(s.textColor),
    'tipColor': _colorToJson(s.tipColor),
    'tipDividerColor': s.tipDividerColor == null ? null : _colorToJson(s.tipDividerColor!),
    'fontFamily': _fontToJson(s.fontFamily),
    'backgroundImage': s.backgroundImage,
    'headerConfig': _headerFooterToJson(s.headerConfig),
    'footerConfig': _headerFooterToJson(s.footerConfig),
    'padding': _paddingToJson(s.padding),
    'clickConfig': _clickConfigToJson(s.clickConfig),
    'showHeaderDivider': s.showHeaderDivider,
    'showFooterDivider': s.showFooterDivider,
    'textIndent': s.textIndent,
    'keepScreenOn': s.keepScreenOn,
    'hideStatusBar': s.hideStatusBar,
    'hideNavigationBar': s.hideNavigationBar,
    'textFullJustify': s.textFullJustify,
    'textBottomJustify': s.textBottomJustify,
    'selectable': s.selectable,
    'showBrightnessView': s.showBrightnessView,
    'titleMode': s.titleMode,
    'isMiddleTitle': s.isMiddleTitle,
    'titleSize': s.titleSize,
    'titleTopSpacing': s.titleTopSpacing,
    'titleBottomSpacing': s.titleBottomSpacing,
    'pageAnimMode': s.pageAnimMode.name,
    'shareLayout': s.shareLayout,
  };
}

/// 从 JSON Map 解码 [ReadingSettings]。
///
/// 字段缺失时回落到 [ReadingSettings] 默认值; 未知枚举名回落到默认。
/// schema 版本不匹配时不报错(向前兼容: 多出的字段忽略, 缺失的用默认)。
ReadingSettings decodeReadingSettings(Map<String, dynamic> json) {
  final d = ReadingSettings(); // 默认实例, 用作各字段 fallback
  return ReadingSettings(
    fontSize: _asDouble(json['fontSize'], d.fontSize),
    fontWeight:
        _fontWeightFromJson(json['fontWeight'], d.fontWeight),
    lineHeight: _asDouble(json['lineHeight'], d.lineHeight),
    paragraphSpacing: _asDouble(json['paragraphSpacing'], d.paragraphSpacing),
    letterSpacing: _asDouble(json['letterSpacing'], d.letterSpacing),
    backgroundColor: _colorFromJson(_asInt(json['backgroundColor'], d.backgroundColor.toARGB32())),
    textColor: _colorFromJson(_asInt(json['textColor'], d.textColor.toARGB32())),
    tipColor: _colorFromJson(_asInt(json['tipColor'], d.tipColor.toARGB32())),
    tipDividerColor: json['tipDividerColor'] == null
        ? null
        : _colorFromJson(_asInt(json['tipDividerColor'], d.tipDividerColor?.toARGB32() ?? 0)),
    fontFamily: _fontFromJson(json['fontFamily']),
    backgroundImage: json['backgroundImage']?.toString(),
    headerConfig: _headerFooterFromJson(
        (json['headerConfig'] as Map?)?.cast<String, dynamic>() ?? const {}),
    footerConfig: _headerFooterFromJson(
        (json['footerConfig'] as Map?)?.cast<String, dynamic>() ?? const {}),
    padding: _paddingFromJson(
        (json['padding'] as Map?)?.cast<String, dynamic>() ?? const {}),
    clickConfig: _clickConfigFromJson(
        (json['clickConfig'] as Map?)?.cast<String, dynamic>() ?? const {}),
    showHeaderDivider: (json['showHeaderDivider'] as bool?) ?? d.showHeaderDivider,
    showFooterDivider: (json['showFooterDivider'] as bool?) ?? d.showFooterDivider,
    textIndent: _asInt(json['textIndent'], d.textIndent),
    keepScreenOn: (json['keepScreenOn'] as bool?) ?? d.keepScreenOn,
    hideStatusBar: (json['hideStatusBar'] as bool?) ?? d.hideStatusBar,
    hideNavigationBar: (json['hideNavigationBar'] as bool?) ?? d.hideNavigationBar,
    textFullJustify: (json['textFullJustify'] as bool?) ?? d.textFullJustify,
    textBottomJustify: (json['textBottomJustify'] as bool?) ?? d.textBottomJustify,
    selectable: (json['selectable'] as bool?) ?? d.selectable,
    showBrightnessView: (json['showBrightnessView'] as bool?) ?? d.showBrightnessView,
    titleMode: _asInt(json['titleMode'], d.titleMode),
    isMiddleTitle: (json['isMiddleTitle'] as bool?) ?? d.isMiddleTitle,
    titleSize: _asDouble(json['titleSize'], d.titleSize),
    titleTopSpacing: _asDouble(json['titleTopSpacing'], d.titleTopSpacing),
    titleBottomSpacing: _asDouble(json['titleBottomSpacing'], d.titleBottomSpacing),
    pageAnimMode: _pageAnimFromName(json['pageAnimMode'], d.pageAnimMode),
    shareLayout: (json['shareLayout'] as bool?) ?? d.shareLayout,
  );
}

// ─────────────────────────── FontWeight / PageAnimMode ───────────────────────────

/// FontWeight → 字重数值(w100~w900 → 100~900, normal=w400, bold=w700)。
/// 用 value(字重数值) 而非 index, 因新 API 中 FontWeight.index 已弃用;
/// 字重数值语义稳定且跨 Flutter 版本一致。
int _fontWeightToJson(FontWeight w) => w.value;

FontWeight _fontWeightFromJson(dynamic v, FontWeight fallback) {
  if (v == null) return fallback;
  final val = v is int ? v : int.tryParse(v.toString());
  if (val == null) return fallback;
  for (final fw in FontWeight.values) {
    if (fw.value == val) return fw;
  }
  return fallback;
}

PageAnimMode _pageAnimFromName(dynamic name, PageAnimMode fallback) {
  if (name == null) return fallback;
  for (final v in PageAnimMode.values) {
    if (v.name == name) return v;
  }
  return fallback;
}
