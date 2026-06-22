import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            _buildButton(context, Icons.content_copy, '复制', () {
              Clipboard.setData(ClipboardData(text: selectedText));
              onCopy?.call();
            }),
            _buildButton(context, Icons.bookmark_add, '书签', onBookmark),
            _buildButton(context, Icons.search, '搜索', onSearch),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: () {
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
