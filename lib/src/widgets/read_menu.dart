import 'package:flutter/material.dart';
import '../controller/reading_controller.dart';
import '../models/reading_settings.dart';
import 'chapter_list_page.dart';
import 'legado_icons.dart';

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
              icon: LegadoIcons.arrowBack(size: 24, color: Colors.black87),
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
              icon: LegadoIcons.bookmark(size: 24, color: Colors.black87),
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
          _buildFab(LegadoIcons.search(), '搜索', () {
            widget.controller.hideMenu();
            widget.controller.toggleSearch();
          }),
          _buildFab(LegadoIcons.autoPage(), '自动', () {}),
          _buildFab(LegadoIcons.findReplace(), '替换', () {}),
          _buildFab(LegadoIcons.brightness(), '夜间', () {}),
        ],
      ),
    );
  }

  Widget _buildFab(Widget icon, String tooltip, VoidCallback onPressed) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      onPressed: onPressed,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black54,
      elevation: 2,
      tooltip: tooltip,
      child: icon,
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
        _buildBottomIcon(LegadoIcons.toc(), '目录', () {
          widget.controller.hideMenu();
          _showChapterDrawer(context);
        }),
        const Spacer(flex: 2),
        _buildBottomIcon(LegadoIcons.readAloud(), '朗读', () {}),
        const Spacer(flex: 2),
        _buildBottomIcon(LegadoIcons.interfaceSetting(), '界面', () {
          widget.controller.hideMenu();
          _showStyleDialog(context);
        }),
        const Spacer(flex: 2),
        _buildBottomIcon(LegadoIcons.settings(), '设置', () {
          widget.controller.hideMenu();
          _showMoreSettings(context);
        }),
        const Spacer(flex: 1),
      ],
    );
  }

  Widget _buildBottomIcon(Widget icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 24, child: icon),
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ChapterListPage(controller: widget.controller),
      ),
    );
  }

  void _showStyleDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => _StyleDialog(controller: widget.controller));
  }

  void _showMoreSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MoreSettingsSheet(controller: widget.controller),
    );
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

class _MoreSettingsSheet extends StatefulWidget {
  final ReadingController controller;
  const _MoreSettingsSheet({required this.controller});

  @override
  State<_MoreSettingsSheet> createState() => _MoreSettingsSheetState();
}

class _MoreSettingsSheetState extends State<_MoreSettingsSheet> {
  late PageAnimationType pageAnim;
  late bool keepScreenOn;
  late bool hideStatusBar;
  late bool hideNavigationBar;
  late bool textFullJustify;
  late bool textBottomJustify;
  late bool selectable;
  late bool showBrightnessView;
  late bool noAnimScrollPage;
  late bool showHeaderDivider;
  late bool showFooterDivider;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    pageAnim = s.pageAnimation;
    keepScreenOn = s.keepScreenOn;
    hideStatusBar = s.hideStatusBar;
    hideNavigationBar = s.hideNavigationBar;
    textFullJustify = s.textFullJustify;
    textBottomJustify = s.textBottomJustify;
    selectable = s.selectable;
    showBrightnessView = s.showBrightnessView;
    noAnimScrollPage = s.noAnimScrollPage;
    showHeaderDivider = s.showHeaderDivider;
    showFooterDivider = s.showFooterDivider;
  }

  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        pageAnimation: pageAnim,
        keepScreenOn: keepScreenOn,
        hideStatusBar: hideStatusBar,
        hideNavigationBar: hideNavigationBar,
        textFullJustify: textFullJustify,
        textBottomJustify: textBottomJustify,
        selectable: selectable,
        showBrightnessView: showBrightnessView,
        noAnimScrollPage: noAnimScrollPage,
        showHeaderDivider: showHeaderDivider,
        showFooterDivider: showFooterDivider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 360,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: bottomPadding),
              children: [
                _buildDropdown('翻页动画', pageAnim, const {
                  PageAnimationType.cover: '覆盖',
                  PageAnimationType.slide: '滑动',
                  PageAnimationType.scroll: '滚动',
                  PageAnimationType.none: '无动画',
                }, (v) => setState(() { pageAnim = v; _apply(); })),
                _buildSwitch('屏幕常亮', keepScreenOn, (v) => setState(() { keepScreenOn = v; _apply(); })),
                _buildSwitch('隐藏状态栏', hideStatusBar, (v) => setState(() { hideStatusBar = v; _apply(); })),
                _buildSwitch('隐藏导航栏', hideNavigationBar, (v) => setState(() { hideNavigationBar = v; _apply(); })),
                _buildSwitch('文字两端对齐', textFullJustify, (v) => setState(() { textFullJustify = v; _apply(); })),
                _buildSwitch('文字底部对齐', textBottomJustify, (v) => setState(() { textBottomJustify = v; _apply(); })),
                _buildSwitch('允许选择文字', selectable, (v) => setState(() { selectable = v; _apply(); })),
                _buildSwitch('显示亮度调节', showBrightnessView, (v) => setState(() { showBrightnessView = v; _apply(); })),
                _buildSwitch('无动画翻页', noAnimScrollPage, (v) => setState(() { noAnimScrollPage = v; _apply(); })),
                _buildSwitch('页头分割线', showHeaderDivider, (v) => setState(() { showHeaderDivider = v; _apply(); })),
                _buildSwitch('页尾分割线', showFooterDivider, (v) => setState(() { showFooterDivider = v; _apply(); })),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.blue,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildDropdown<T>(String title, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox(),
            items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }
}
