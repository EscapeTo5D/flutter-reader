import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../core/controller/reading_controller.dart';
import '../../core/models/bookmark.dart';
import '../../core/models/reading_settings.dart';

/// 书签编辑/查看弹窗, 对齐原生 legado `BookmarkDialog` + `dialog_bookmark.xml`。
///
/// 布局(自上而下):
/// - 顶部标题栏「书签」(对齐 `tool_bar` app:title="@string/bookmark")
/// - 章节名文本(对齐 `tv_chapter_name`, 不可编辑)
/// - 原文输入框(对齐 `edit_book_text`, hint「内容」)
/// - 笔记输入框(对齐 `edit_content`, hint「笔记内容」)
/// - 底部三按钮行(对齐 `FlexboxLayout` justifyContent=space_between):
///   左下「删除」(仅编辑已有书签时显示, 对齐 `tv_footer_left.visible(editPos>=0)`)
///   右侧「取消」「确定」
///
/// 调用: [showBookmarkDialog]。挂载用 SmartDialog(对齐项目其他弹窗),
/// 居中 + 0.5 黑遮罩; 外层套 `Material(transparent)` 给内部 TextField/按钮
/// 提供墨水宿主(对齐 `_PresetEditorDialog` 模板)。
class BookmarkDialog extends StatefulWidget {
  final ReadingController controller;

  /// 被编辑的书签。新建时也需传入(预填原文 + 章节名), 由 controller 落库。
  final Bookmark bookmark;

  /// 是否为「新建」态。true 时不显示「删除」按钮(对齐原生 editPos=-1)。
  final bool isNew;

  const BookmarkDialog({
    super.key,
    required this.controller,
    required this.bookmark,
    this.isNew = false,
  });

  @override
  State<BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<BookmarkDialog> {
  late final TextEditingController _bookTextController;
  late final TextEditingController _contentController;
  late final _DialogPalette _palette;

  @override
  void initState() {
    super.initState();
    _bookTextController =
        TextEditingController(text: widget.bookmark.bookText);
    _contentController = TextEditingController(text: widget.bookmark.content);
    _palette = _DialogPalette.of(widget.controller.settings);
  }

  @override
  void dispose() {
    _bookTextController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// 章节名: 取书签所在章的标题; 取不到回退「未知章节」。
  String get _chapterName {
    final book = widget.controller.book;
    if (book == null) return '未知章节';
    if (widget.bookmark.chapterIndex < 0 ||
        widget.bookmark.chapterIndex >= book.chapters.length) {
      return '未知章节';
    }
    return book.chapters[widget.bookmark.chapterIndex].title;
  }

  Future<void> _onSave() async {
    final updated = widget.bookmark.copyWith(
      bookText: _bookTextController.text.trim(),
      content: _contentController.text.trim(),
    );
    await widget.controller.updateBookmark(updated);
    if (mounted) SmartDialog.dismiss();
  }

  Future<void> _onDelete() async {
    await widget.controller.removeBookmark(widget.bookmark.id);
    if (mounted) SmartDialog.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final dialogWidth = MediaQuery.sizeOf(context).width * 0.85;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏「书签」(对齐 tool_bar)。
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: p.header,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Text(
                  '书签',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: p.onSurface,
                  ),
                ),
              ),
              // 章节名(对齐 tv_chapter_name, 不可编辑)。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  _chapterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.onSurface),
                ),
              ),
              // 原文输入框(对齐 edit_book_text)。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _bookTextController,
                  maxLines: 4,
                  minLines: 2,
                  style: TextStyle(fontSize: 14, color: p.onSurface),
                  decoration: InputDecoration(
                    hintText: '内容',
                    hintStyle: TextStyle(color: p.hint, fontSize: 14),
                    filled: true,
                    fillColor: p.field,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.accent),
                    ),
                  ),
                ),
              ),
              // 笔记输入框(对齐 edit_content)。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _contentController,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(fontSize: 14, color: p.onSurface),
                  decoration: InputDecoration(
                    hintText: '笔记内容',
                    hintStyle: TextStyle(color: p.hint, fontSize: 14),
                    filled: true,
                    fillColor: p.field,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: p.accent),
                    ),
                  ),
                ),
              ),
              // 底部按钮行(对齐 FlexboxLayout justifyContent=space_between)。
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左下「删除」: 仅编辑已有书签时显示(对齐 tv_footer_left.visible)。
                    if (!widget.isNew)
                      TextButton(
                        onPressed: _onDelete,
                        child: const Text(
                          '删除',
                          style: TextStyle(color: Colors.red),
                        ),
                      )
                    else
                      const SizedBox(width: 0),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => SmartDialog.dismiss(),
                          child: Text(
                            '取消',
                            style: TextStyle(color: p.onSurfaceMedium),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: _onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                          ),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹 BookmarkDialog。
///
/// [bookmark] 已加书签后从列表长按进入编辑态([isNew]=false, 显示「删除」);
/// 也可用于「快速加后立即编辑」场景([isNew]=true, 不显示「删除」)。
Future<void> showBookmarkDialog(
  BuildContext context, {
  required ReadingController controller,
  required Bookmark bookmark,
  bool isNew = false,
}) {
  return SmartDialog.show(
    alignment: Alignment.center,
    maskColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => BookmarkDialog(
      controller: controller,
      bookmark: bookmark,
      isNew: isNew,
    ),
  );
}

/// BookmarkDialog 内部日夜色板。
///
/// 色值与项目其他弹窗(`MenuPalette`/`_ChapterListPalette`)一致, 这里独立定义
/// 避免跨文件依赖私有类; 仅按 [ReadingSettings.isNightTheme] 切换。
class _DialogPalette {
  final Color background; // 弹窗背景
  final Color header; // 标题栏背景(略深于 background)
  final Color field; // 输入框填充
  final Color onSurface; // 主文字
  final Color onSurfaceMedium; // 次文字(取消按钮)
  final Color hint; // hint 文字
  final Color divider; // 边框
  final Color accent; // 强调色(确定按钮 / 焦点边框)

  const _DialogPalette._({
    required this.background,
    required this.header,
    required this.field,
    required this.onSurface,
    required this.onSurfaceMedium,
    required this.hint,
    required this.divider,
    required this.accent,
  });

  static const _DialogPalette _light = _DialogPalette._(
    background: Color(0xFFFAFAFA),
    header: Color(0xFFEDEDED),
    field: Color(0xFFF2F2F2),
    onSurface: Colors.black87,
    onSurfaceMedium: Colors.black54,
    hint: Colors.black38,
    divider: Color(0xFFBDBDBD),
    accent: Color(0xFF1976D2),
  );

  static const _DialogPalette _dark = _DialogPalette._(
    background: Color(0xFF2A2A2A),
    header: Color(0xFF333333),
    field: Color(0xFF1F1F1F),
    onSurface: Color(0xFFE0E0E0),
    onSurfaceMedium: Color(0xFFAAAAAA),
    hint: Color(0xFF666666),
    divider: Color(0xFF555555),
    accent: Color(0xFF64B5F6),
  );

  static _DialogPalette of(ReadingSettings settings) =>
      settings.isNightTheme ? _dark : _light;
}
