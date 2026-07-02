import 'package:flutter/material.dart';

enum TipPosition { none, chapterTitle, time, battery, batteryPercent, pageNumber, progress, bookName, timeAndBattery, pageAndTotal }

/// 翻页动画类型, 对齐原生 legado `PageAnim`(`app/.../constant/PageAnim.kt`)。
/// 枚举值与原生常量一一对应(0=cover, 1=slide, 2=simulation, 3=scroll, 4=none)。
enum PageAnimMode {
  cover,       // 覆盖翻页
  slide,       // 滑动翻页(本步骤实现)
  simulation,  // 仿真翻页(贝塞尔曲线)
  scroll,      // 滚动翻页
  none,        // 无动画
}

class HeaderFooterConfig {
  final TipPosition left;
  final TipPosition center;
  final TipPosition right;

  /// 整体显示/隐藏开关, 对应原生 legado 的 headerMode/footerMode。
  /// false(默认)=显示; true=隐藏整个区域(高度归零, 不占排版空间)。
  final bool hidden;

  const HeaderFooterConfig({
    this.left = TipPosition.chapterTitle,
    this.center = TipPosition.none,
    this.right = TipPosition.pageNumber,
    this.hidden = false,
  });

  HeaderFooterConfig copyWith({
    TipPosition? left,
    TipPosition? center,
    TipPosition? right,
    bool? hidden,
  }) {
    return HeaderFooterConfig(
      left: left ?? this.left,
      center: center ?? this.center,
      right: right ?? this.right,
      hidden: hidden ?? this.hidden,
    );
  }
}

class ReaderPadding {
  // 正文区内边距(对齐原生 ReadBookConfig.paddingTop/Bottom/Left/Right, 默认 6/6/16/16)。
  final double top;
  final double bottom;
  final double left;
  final double right;
  // 页眉/页脚内容行高(原生无此字段, 由文字行高+padding 决定; 此处抽象为固定行高)。
  final double headerHeight;
  final double footerHeight;
  // 页眉外层四向内边距(对齐原生 headerPaddingTop/Bottom/Left/Right, 默认 0/0/16/16)。
  final double headerTop;
  final double headerBottom;
  final double headerLeft;
  final double headerRight;
  // 页脚外层四向内边距(对齐原生 footerPaddingTop/Bottom/Left/Right, 默认 6/6/16/16)。
  final double footerTop;
  final double footerBottom;
  final double footerLeft;
  final double footerRight;

  const ReaderPadding({
    this.top = 16,
    this.bottom = 16,
    this.left = 16,
    this.right = 16,
    this.headerHeight = 24,
    this.footerHeight = 24,
    this.headerTop = 0,
    this.headerBottom = 0,
    this.headerLeft = 16,
    this.headerRight = 16,
    this.footerTop = 6,
    this.footerBottom = 6,
    this.footerLeft = 16,
    this.footerRight = 16,
  });

  ReaderPadding copyWith({
    double? top,
    double? bottom,
    double? left,
    double? right,
    double? headerHeight,
    double? footerHeight,
    double? headerTop,
    double? headerBottom,
    double? headerLeft,
    double? headerRight,
    double? footerTop,
    double? footerBottom,
    double? footerLeft,
    double? footerRight,
  }) {
    return ReaderPadding(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      left: left ?? this.left,
      right: right ?? this.right,
      headerHeight: headerHeight ?? this.headerHeight,
      footerHeight: footerHeight ?? this.footerHeight,
      headerTop: headerTop ?? this.headerTop,
      headerBottom: headerBottom ?? this.headerBottom,
      headerLeft: headerLeft ?? this.headerLeft,
      headerRight: headerRight ?? this.headerRight,
      footerTop: footerTop ?? this.footerTop,
      footerBottom: footerBottom ?? this.footerBottom,
      footerLeft: footerLeft ?? this.footerLeft,
      footerRight: footerRight ?? this.footerRight,
    );
  }
}

enum ClickAction { menu, nextPage, prevPage, nextChapter, prevChapter, bookmark, search, none }

class ClickRegionConfig {
  final ClickAction topLeft;
  final ClickAction topCenter;
  final ClickAction topRight;
  final ClickAction middleLeft;
  final ClickAction center;
  final ClickAction middleRight;
  final ClickAction bottomLeft;
  final ClickAction bottomCenter;
  final ClickAction bottomRight;

  const ClickRegionConfig({
    this.topLeft = ClickAction.none,
    this.topCenter = ClickAction.menu,
    this.topRight = ClickAction.none,
    this.middleLeft = ClickAction.prevPage,
    this.center = ClickAction.menu,
    this.middleRight = ClickAction.nextPage,
    this.bottomLeft = ClickAction.prevPage,
    this.bottomCenter = ClickAction.menu,
    this.bottomRight = ClickAction.nextPage,
  });

  ClickRegionConfig copyWith({
    ClickAction? topLeft,
    ClickAction? topCenter,
    ClickAction? topRight,
    ClickAction? middleLeft,
    ClickAction? center,
    ClickAction? middleRight,
    ClickAction? bottomLeft,
    ClickAction? bottomCenter,
    ClickAction? bottomRight,
  }) {
    return ClickRegionConfig(
      topLeft: topLeft ?? this.topLeft,
      topCenter: topCenter ?? this.topCenter,
      topRight: topRight ?? this.topRight,
      middleLeft: middleLeft ?? this.middleLeft,
      center: center ?? this.center,
      middleRight: middleRight ?? this.middleRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
      bottomCenter: bottomCenter ?? this.bottomCenter,
      bottomRight: bottomRight ?? this.bottomRight,
    );
  }
}

class ReadingSettings {
  double fontSize;
  FontWeight fontWeight;
  /// 行距倍数, 对应原生 ReadBookConfig.lineSpacingExtra/10(默认 config=12 → 1.2)。
  /// 渲染行高 = 纯字体度量 textHeight × lineHeight。同时作为 TextPainter 的
  /// style.height 用于换行测量(贴合原生换行点)。
  double lineHeight;
  /// 段落间距系数, 对应原生 ReadBookConfig.paragraphSpacing(默认 2, 整数)。
  /// 段距 = textHeight × paragraphSpacing / 10(对齐原生公式, 非固定 px)。
  double paragraphSpacing;
  double letterSpacing;
  Color backgroundColor;
  Color textColor;
  Color tipColor;
  String? fontFamily;
  String? backgroundImage;
  HeaderFooterConfig headerConfig;
  HeaderFooterConfig footerConfig;
  ReaderPadding padding;
  ClickRegionConfig clickConfig;
  bool showHeaderDivider;
  bool showFooterDivider;
  int textIndent;
  bool keepScreenOn;
  bool hideStatusBar;
  bool hideNavigationBar;
  bool textFullJustify;
  bool textBottomJustify;
  bool selectable;
  bool showBrightnessView;
  int titleMode;       // 0:居左, 1:居中, 2:隐藏
  bool isMiddleTitle;  // 强制所有标题居中
  double titleSize;    // 标题字号偏移量
  double titleTopSpacing;    // 标题上方间距
  double titleBottomSpacing; // 标题下方间距
  /// 翻页动画类型, 对齐原生 legado PageAnim。默认 slide(对齐原生默认)。
  PageAnimMode pageAnimMode;
  /// 共享排版, 对齐原生 ReadBookConfig.shareLayout。
  /// 原生语义: true 时排版参数(字号/字距/行距/段距)跨「样式槽」共享。
  /// Flutter 无多槽配置, 重新定义为: true 时点颜色预设只换 bg/text,
  /// 不重置滑块值(保留当前排版参数); false 时切预设连同排版参数一起重置(原生默认行为)。
  bool shareLayout;

  ReadingSettings({
    // 默认值对齐原生 legado「微信读书」预设(readConfig.json 第 0 项):
    // textSize=24, letterSpacing=0, lineSpacingExtra=10, paragraphSpacing=6,
    // bg=#ffc0edc6, text=#ff0b0b0b。
    // lineSpacingExtra=10 → lineHeight = 10/10 = 1.0; paragraphSpacing 字段值即
    // 原生 progress(6), 段距 = textHeight × 6 / 10。
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.lineHeight = 1.0,
    this.paragraphSpacing = 6.0,
    this.letterSpacing = 0.0,
    this.backgroundColor = const Color(0xFFC0EDC6),
    this.textColor = const Color(0xFF0B0B0B),
    this.tipColor = const Color(0xFF999999),
    this.fontFamily,
    this.backgroundImage,
    // 对齐原生 legado ReadBookConfig.kt:585-590 默认值:
    // 页眉 左=time 中=none 右=battery; 页脚 左=chapterTitle 中=none 右=pageAndTotal。
    this.headerConfig = const HeaderFooterConfig(
      left: TipPosition.time,
      center: TipPosition.none,
      right: TipPosition.battery,
    ),
    this.footerConfig = const HeaderFooterConfig(
      left: TipPosition.chapterTitle,
      center: TipPosition.none,
      right: TipPosition.pageAndTotal,
    ),
    this.padding = const ReaderPadding(),
    this.clickConfig = const ClickRegionConfig(),
    this.showHeaderDivider = false,
    this.showFooterDivider = true,
    this.textIndent = 2,
    this.keepScreenOn = true,
    this.hideStatusBar = false,
    this.hideNavigationBar = false,
    this.textFullJustify = true,
    this.textBottomJustify = true,
    this.selectable = true,
    this.showBrightnessView = true,
    this.titleMode = 0,
    this.isMiddleTitle = false,
    this.titleSize = 2.0,
    this.titleTopSpacing = 12.0,
    this.titleBottomSpacing = 8.0,
    this.pageAnimMode = PageAnimMode.slide,
    this.shareLayout = false,
  });

  ReadingSettings copyWith({
    double? fontSize,
    FontWeight? fontWeight,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    Color? backgroundColor,
    Color? textColor,
    Color? tipColor,
    String? fontFamily,
    String? backgroundImage,
    bool clearBackgroundImage = false,
    HeaderFooterConfig? headerConfig,
    HeaderFooterConfig? footerConfig,
    ReaderPadding? padding,
    ClickRegionConfig? clickConfig,
    bool? showHeaderDivider,
    bool? showFooterDivider,
    int? textIndent,
    bool? keepScreenOn,
    bool? hideStatusBar,
    bool? hideNavigationBar,
    bool? textFullJustify,
    bool? textBottomJustify,
    bool? selectable,
    bool? showBrightnessView,
    int? titleMode,
    bool? isMiddleTitle,
    double? titleSize,
    double? titleTopSpacing,
    double? titleBottomSpacing,
    PageAnimMode? pageAnimMode,
    bool? shareLayout,
  }) {
    return ReadingSettings(
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      tipColor: tipColor ?? this.tipColor,
      fontFamily: fontFamily ?? this.fontFamily,
      backgroundImage: clearBackgroundImage ? null : (backgroundImage ?? this.backgroundImage),
      headerConfig: headerConfig ?? this.headerConfig,
      footerConfig: footerConfig ?? this.footerConfig,
      padding: padding ?? this.padding,
      clickConfig: clickConfig ?? this.clickConfig,
      showHeaderDivider: showHeaderDivider ?? this.showHeaderDivider,
      showFooterDivider: showFooterDivider ?? this.showFooterDivider,
      textIndent: textIndent ?? this.textIndent,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      hideNavigationBar: hideNavigationBar ?? this.hideNavigationBar,
      textFullJustify: textFullJustify ?? this.textFullJustify,
      textBottomJustify: textBottomJustify ?? this.textBottomJustify,
      selectable: selectable ?? this.selectable,
      showBrightnessView: showBrightnessView ?? this.showBrightnessView,
      titleMode: titleMode ?? this.titleMode,
      isMiddleTitle: isMiddleTitle ?? this.isMiddleTitle,
      titleSize: titleSize ?? this.titleSize,
      titleTopSpacing: titleTopSpacing ?? this.titleTopSpacing,
      titleBottomSpacing: titleBottomSpacing ?? this.titleBottomSpacing,
      pageAnimMode: pageAnimMode ?? this.pageAnimMode,
      shareLayout: shareLayout ?? this.shareLayout,
    );
  }
}
