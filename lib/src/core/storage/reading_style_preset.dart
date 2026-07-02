import 'package:flutter/material.dart';

/// 用户自定义阅读样式预设(对应 `reading_style_presets` 表一行)。
///
/// 用于「设置弹窗 → 颜色与背景」横滑列表: 除内置的 6 个预设(微信读书/预设1~5)外,
/// 用户可点「+」新建自定义预设(只存 bg/text 色, 不存排版参数——对齐 shareLayout
/// 语义), 长按可编辑。按 [userId] 隔离。
///
/// 字段极简: 仅存预设弹窗能选的背景色 + 文字色 + 名称。原生 legado 的 BgTextConfigDialog
/// 还含 day/night/eink 三套色 + bgImage + bgAlpha + textAccent, 本轮不实现(对齐
/// Flutter 当前模型能力)。
class ReadingStylePreset {
  /// 主键(UUID)。内置预设用固定 id(如 'builtin_wx')区分, 用户预设用 UUID。
  final String id;
  final String userId;
  final String name;
  final Color bgColor;
  final Color textColor;
  /// 排序序号(用户预设追加在内置之后, 按创建时间升序)。
  final int sortOrder;
  final DateTime createdAt;

  const ReadingStylePreset({
    required this.id,
    required this.userId,
    required this.name,
    required this.bgColor,
    required this.textColor,
    required this.sortOrder,
    required this.createdAt,
  });

  ReadingStylePreset copyWith({
    String? id,
    String? userId,
    String? name,
    Color? bgColor,
    Color? textColor,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return ReadingStylePreset(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      bgColor: bgColor ?? this.bgColor,
      textColor: textColor ?? this.textColor,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 从 DB 行构造(颜色以 int 形式存储, 转回 Color)。
  factory ReadingStylePreset.fromRow(Map<String, dynamic> row) {
    // ignore: deprecated_member_use
    Color c(int v) => Color(v);
    return ReadingStylePreset(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      name: (row['name'] as String?) ?? '预设',
      bgColor: c((row['bg_color'] as int?) ?? 0xFFEEEEEE),
      textColor: c((row['text_color'] as int?) ?? 0xFF3E3D3B),
      sortOrder: (row['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 转 DB 行(颜色 int 化)。
  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'bg_color': bgColor.toARGB32(),
        'text_color': textColor.toARGB32(),
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  String toString() =>
      'ReadingStylePreset(id: $id, name: $name, bg: ${bgColor.toARGB32().toRadixString(16)}, '
      'text: ${textColor.toARGB32().toRadixString(16)})';
}
