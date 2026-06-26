import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'legado_icons.dart';

class ReaderTextSelectionToolbar extends StatelessWidget {
  final String selectedText;
  final VoidCallback? onCopy;
  final VoidCallback? onBookmark;
  final VoidCallback? onSearch;

  const ReaderTextSelectionToolbar({
    super.key,
    required this.selectedText,
    this.onCopy,
    this.onBookmark,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey.shade800,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(context, LegadoIcons.copy(size: 18, color: Colors.white), '复制', () {
              Clipboard.setData(ClipboardData(text: selectedText));
              onCopy?.call();
            }),
            _buildButton(context, LegadoIcons.bookmark(size: 18, color: Colors.white), '书签', onBookmark),
            _buildButton(context, LegadoIcons.search(size: 18, color: Colors.white), '搜索', onSearch),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, Widget icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: () {
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 18, height: 18, child: icon),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
