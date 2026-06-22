import 'package:flutter/material.dart';

class ReadingSettings {
  double fontSize;
  FontWeight fontWeight;
  double lineHeight;
  Color backgroundColor;
  Color textColor;
  String? fontFamily;

  ReadingSettings({
    this.fontSize = 18.0,
    this.fontWeight = FontWeight.normal,
    this.lineHeight = 1.5,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.textColor = const Color(0xFF333333),
    this.fontFamily,
  });

  ReadingSettings copyWith({
    double? fontSize,
    FontWeight? fontWeight,
    double? lineHeight,
    Color? backgroundColor,
    Color? textColor,
    String? fontFamily,
  }) {
    return ReadingSettings(
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
