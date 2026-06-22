import 'package:flutter/material.dart';

enum PageAnimationType { cover, slide, scroll, none }

enum TipPosition { none, chapterTitle, time, battery, batteryPercent, pageNumber, progress, bookName, timeAndBattery }

class HeaderFooterConfig {
  final TipPosition left;
  final TipPosition center;
  final TipPosition right;

  const HeaderFooterConfig({
    this.left = TipPosition.chapterTitle,
    this.center = TipPosition.none,
    this.right = TipPosition.pageNumber,
  });

  HeaderFooterConfig copyWith({
    TipPosition? left,
    TipPosition? center,
    TipPosition? right,
  }) {
    return HeaderFooterConfig(
      left: left ?? this.left,
      center: center ?? this.center,
      right: right ?? this.right,
    );
  }
}

class ReaderPadding {
  final double top;
  final double bottom;
  final double left;
  final double right;
  final double headerHeight;
  final double footerHeight;

  const ReaderPadding({
    this.top = 16,
    this.bottom = 16,
    this.left = 16,
    this.right = 16,
    this.headerHeight = 24,
    this.footerHeight = 24,
  });

  ReaderPadding copyWith({
    double? top,
    double? bottom,
    double? left,
    double? right,
    double? headerHeight,
    double? footerHeight,
  }) {
    return ReaderPadding(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      left: left ?? this.left,
      right: right ?? this.right,
      headerHeight: headerHeight ?? this.headerHeight,
      footerHeight: footerHeight ?? this.footerHeight,
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
  double lineHeight;
  double paragraphSpacing;
  double letterSpacing;
  Color backgroundColor;
  Color textColor;
  Color tipColor;
  String? fontFamily;
  String? backgroundImage;
  PageAnimationType pageAnimation;
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
  bool noAnimScrollPage;

  ReadingSettings({
    this.fontSize = 18.0,
    this.fontWeight = FontWeight.normal,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 8.0,
    this.letterSpacing = 0.0,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.textColor = const Color(0xFF333333),
    this.tipColor = const Color(0xFF999999),
    this.fontFamily,
    this.backgroundImage,
    this.pageAnimation = PageAnimationType.cover,
    this.headerConfig = const HeaderFooterConfig(),
    this.footerConfig = const HeaderFooterConfig(
      left: TipPosition.time,
      center: TipPosition.none,
      right: TipPosition.pageNumber,
    ),
    this.padding = const ReaderPadding(),
    this.clickConfig = const ClickRegionConfig(),
    this.showHeaderDivider = true,
    this.showFooterDivider = true,
    this.textIndent = 2,
    this.keepScreenOn = true,
    this.hideStatusBar = false,
    this.hideNavigationBar = false,
    this.textFullJustify = true,
    this.textBottomJustify = true,
    this.selectable = true,
    this.showBrightnessView = true,
    this.noAnimScrollPage = false,
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
    PageAnimationType? pageAnimation,
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
    bool? noAnimScrollPage,
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
      pageAnimation: pageAnimation ?? this.pageAnimation,
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
      noAnimScrollPage: noAnimScrollPage ?? this.noAnimScrollPage,
    );
  }
}
