import 'package:flutter/material.dart';
import '../controller/reading_controller.dart';
import '../models/reading_settings.dart';

class ReadMenu extends StatefulWidget {
  final ReadingController controller;

  const ReadMenu({super.key, required this.controller});

  @override
  State<ReadMenu> createState() => _ReadMenuState();
}

class _ReadMenuState extends State<ReadMenu> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        _buildTopBar(context),
        const Spacer(),
        _buildFloatingButtons(context),
        _buildBottomBar(context),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final book = widget.controller.book;
    final chapter = widget.controller.currentChapter;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      color: Colors.white,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book?.title ?? '',
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chapter != null)
                    Text(
                      chapter.title,
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                widget.controller.isCurrentPageBookmarked() ? Icons.bookmark : Icons.bookmark_border,
                color: Colors.black87,
              ),
              onPressed: () => widget.controller.addBookmark(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildFab(Icons.search, '搜索', () {
            widget.controller.hideMenu();
            widget.controller.toggleSearch();
          }),
          _buildFab(Icons.play_circle_outline, '自动', () {}),
          _buildFab(Icons.find_replace, '替换', () {}),
          _buildFab(Icons.brightness_6, '夜间', () {}),
        ],
      ),
    );
  }

  Widget _buildFab(IconData icon, String tooltip, VoidCallback onPressed) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      onPressed: onPressed,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black54,
      elevation: 2,
      tooltip: tooltip,
      child: Icon(icon),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChapterSeekBar(),
          _buildBottomButtons(context),
        ],
      ),
    );
  }

  Widget _buildChapterSeekBar() {
    final totalPages = widget.controller.totalPages;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        children: [
          _buildChapterTextButton('上一章', widget.controller.canGoPrevious ? () => widget.controller.previousChapter() : null),
          Expanded(
            child: Slider(
              value: totalPages > 1 ? widget.controller.currentPageIndex.toDouble() : 0,
              min: 0,
              max: totalPages > 1 ? (totalPages - 1).toDouble() : 1,
              activeColor: Colors.black54,
              inactiveColor: Colors.black26,
              onChanged: (v) => widget.controller.goToPage(v.toInt()),
            ),
          ),
          _buildChapterTextButton('下一章', widget.controller.canGoNext ? () => widget.controller.nextChapter() : null),
        ],
      ),
    );
  }

  Widget _buildChapterTextButton(String text, VoidCallback? onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            color: onPressed != null ? Colors.black87 : Colors.black38,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Row(
      children: [
        const Spacer(flex: 1),
        _buildBottomIcon(Icons.toc, '目录', () {
          widget.controller.hideMenu();
          _showChapterDrawer(context);
        }),
        const Spacer(flex: 2),
        _buildBottomIcon(Icons.headphones, '朗读', () {}),
        const Spacer(flex: 2),
        _buildBottomIcon(Icons.font_download, '界面', () {
          widget.controller.hideMenu();
          _showStyleDialog(context);
        }),
        const Spacer(flex: 2),
        _buildBottomIcon(Icons.settings, '设置', () {
          widget.controller.hideMenu();
          _showMoreSettings(context);
        }),
        const Spacer(flex: 1),
      ],
    );
  }

  Widget _buildBottomIcon(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black54, size: 24),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 7),
          ],
        ),
      ),
    );
  }

  void _showChapterDrawer(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('目录', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: book.chapters.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(book.chapters[i].title),
                  selected: i == widget.controller.currentChapterIndex,
                  onTap: () {
                    widget.controller.goToChapter(i);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStyleDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => _StyleDialog(controller: widget.controller));
  }

  void _showMoreSettings(BuildContext context) {
    showDialog(context: context, builder: (ctx) => _MoreSettingsDialog(controller: widget.controller));
  }
}

class _StyleDialog extends StatefulWidget {
  final ReadingController controller;
  const _StyleDialog({required this.controller});

  @override
  State<_StyleDialog> createState() => _StyleDialogState();
}

class _StyleDialogState extends State<_StyleDialog> {
  late double fontSize;
  late double lineHeight;
  late double paragraphSpacing;
  late double letterSpacing;
  late int textIndent;
  late Color bgColor;
  late Color textColor;
  late String? bgImage;
  bool _clearBgImage = false;

  static const _bgColors = [
    Color(0xFFF5F5F5), Color(0xFFE8E0D0), Color(0xFFD5E8D4),
    Color(0xFFE8D4D4), Color(0xFF2C2C2C), Color(0xFF1A1A2E),
    Color(0xFFFDF6E3), Color(0xFF0D1117),
  ];
  static const _textColors = [
    Color(0xFF333333), Color(0xFF5B4636), Color(0xFF2D4A22),
    Color(0xFF4A2222), Color(0xFFCCCCCC), Color(0xFFC8C8D0),
    Color(0xFF3C3226), Color(0xFFC9D1D9),
  ];
  static const _bgImages = [
    'assets/bg/边彩画布.jpg',
    'assets/bg/护眼漫绿.jpg',
    'assets/bg/明媚倾城.jpg',
    'assets/bg/宁静夜色.jpg',
    'assets/bg/清新时光.jpg',
    'assets/bg/山水画.jpg',
    'assets/bg/山水墨影.jpg',
    'assets/bg/深宫魅影.jpg',
    'assets/bg/午后沙滩.jpg',
    'assets/bg/新羊皮纸.jpg',
    'assets/bg/羊皮纸1.jpg',
    'assets/bg/羊皮纸2.jpg',
    'assets/bg/羊皮纸3.jpg',
    'assets/bg/羊皮纸4.jpg',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    fontSize = s.fontSize;
    lineHeight = s.lineHeight;
    paragraphSpacing = s.paragraphSpacing;
    letterSpacing = s.letterSpacing;
    textIndent = s.textIndent;
    bgColor = s.backgroundColor;
    textColor = s.textColor;
    bgImage = s.backgroundImage;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: DefaultTabController(
        length: 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TabBar(
              tabs: [
                Tab(text: '排版'),
                Tab(text: '颜色'),
                Tab(text: '背景'),
              ],
            ),
            Flexible(
              child: TabBarView(
                children: [
                  _buildTypographyTab(),
                  _buildColorTab(),
                  _buildBackgroundTab(),
                ],
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypographyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSlider('字号', fontSize, 12, 32, (v) => setState(() => fontSize = v), '${fontSize.toInt()}'),
          _buildSlider('行高', lineHeight, 1.0, 3.0, (v) => setState(() => lineHeight = v), lineHeight.toStringAsFixed(1)),
          _buildSlider('段距', paragraphSpacing, 0, 32, (v) => setState(() => paragraphSpacing = v), paragraphSpacing.toInt().toString()),
          _buildSlider('字距', letterSpacing, -2, 8, (v) => setState(() => letterSpacing = v), letterSpacing.toStringAsFixed(1)),
          _buildSlider('缩进', textIndent.toDouble(), 0, 8, (v) => setState(() => textIndent = v.toInt()), textIndent.toString()),
        ],
      ),
    );
  }

  Widget _buildColorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('背景颜色'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bgColors.map((color) {
              final selected = bgColor == color && bgImage == null;
              return GestureDetector(
                onTap: () => setState(() { bgColor = color; bgImage = null; _clearBgImage = true; }),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(color: selected ? Colors.blue : Colors.grey.shade300, width: selected ? 3 : 1),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('文字颜色'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _textColors.map((color) {
              final selected = textColor == color;
              return GestureDetector(
                onTap: () => setState(() => textColor = color),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(color: selected ? Colors.blue : Colors.grey.shade300, width: selected ? 3 : 1),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('背景图片'),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5,
            ),
            itemCount: _bgImages.length,
            itemBuilder: (ctx, i) {
              final img = _bgImages[i];
              final selected = bgImage == img;
              return GestureDetector(
                onTap: () => setState(() { bgImage = img; _clearBgImage = false; }),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? Colors.blue : Colors.grey.shade300, width: selected ? 3 : 1),
                    image: DecorationImage(image: AssetImage(img, package: 'flutter_reader'), fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              widget.controller.updateSettings(
                widget.controller.settings.copyWith(
                  fontSize: fontSize, lineHeight: lineHeight,
                  paragraphSpacing: paragraphSpacing, letterSpacing: letterSpacing,
                  textIndent: textIndent, backgroundColor: bgColor,
                  textColor: textColor, backgroundImage: bgImage,
                  clearBackgroundImage: _clearBgImage,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, String display) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 36, child: Text(display, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

class _MoreSettingsDialog extends StatefulWidget {
  final ReadingController controller;
  const _MoreSettingsDialog({required this.controller});

  @override
  State<_MoreSettingsDialog> createState() => _MoreSettingsDialogState();
}

class _MoreSettingsDialogState extends State<_MoreSettingsDialog> {
  late PageAnimationType pageAnim;
  late bool showHeaderDivider;
  late bool showFooterDivider;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    pageAnim = s.pageAnimation;
    showHeaderDivider = s.showHeaderDivider;
    showFooterDivider = s.showFooterDivider;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('更多设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('翻页动画'),
              const Spacer(),
              DropdownButton<PageAnimationType>(
                value: pageAnim,
                items: const [
                  DropdownMenuItem(value: PageAnimationType.cover, child: Text('覆盖')),
                  DropdownMenuItem(value: PageAnimationType.slide, child: Text('滑动')),
                  DropdownMenuItem(value: PageAnimationType.scroll, child: Text('滚动')),
                  DropdownMenuItem(value: PageAnimationType.none, child: Text('无动画')),
                ],
                onChanged: (v) => setState(() => pageAnim = v!),
              ),
            ],
          ),
          SwitchListTile(title: const Text('页头分割线'), value: showHeaderDivider, onChanged: (v) => setState(() => showHeaderDivider = v)),
          SwitchListTile(title: const Text('页尾分割线'), value: showFooterDivider, onChanged: (v) => setState(() => showFooterDivider = v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            widget.controller.updateSettings(
              widget.controller.settings.copyWith(
                pageAnimation: pageAnim,
                showHeaderDivider: showHeaderDivider,
                showFooterDivider: showFooterDivider,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
