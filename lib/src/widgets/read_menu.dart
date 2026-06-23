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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StyleDialog(controller: widget.controller),
    );
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
  late int _fontSizeProgress;
  late int _letterSpacingProgress;
  late int _lineHeightProgress;
  late int _paragraphSpacingProgress;
  late int textIndent;
  late Color bgColor;
  late Color textColor;
  late String? bgImage;
  late PageAnimationType pageAnim;
  late bool noAnimScrollPage;
  bool _clearBgImage = false;

  static const _stylePresets = [
    _StylePreset('默认', Color(0xFFF5F5F5), Color(0xFF333333)),
    _StylePreset('护眼', Color(0xFFD5E8D4), Color(0xFF2D4A22)),
    _StylePreset('羊皮纸', Color(0xFFE8E0D0), Color(0xFF5B4636)),
    _StylePreset('深色', Color(0xFF2C2C2C), Color(0xFFCCCCCC)),
    _StylePreset('夜间', Color(0xFF1A1A2E), Color(0xFFC8C8D0)),
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _fontSizeProgress = s.fontSize.toInt() - 5;
    _letterSpacingProgress = (s.letterSpacing * 100).toInt() + 50;
    _lineHeightProgress = (s.lineHeight * 10).toInt() + 10;
    _paragraphSpacingProgress = (s.paragraphSpacing * 10).toInt();
    textIndent = s.textIndent;
    bgColor = s.backgroundColor;
    textColor = s.textColor;
    bgImage = s.backgroundImage;
    pageAnim = s.pageAnimation;
    noAnimScrollPage = s.noAnimScrollPage;
  }

  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        fontSize: (_fontSizeProgress + 5).toDouble(),
        lineHeight: (_lineHeightProgress - 10) / 10.0,
        paragraphSpacing: _paragraphSpacingProgress / 10.0,
        letterSpacing: (_letterSpacingProgress - 50) / 100.0,
        textIndent: textIndent,
        backgroundColor: bgColor,
        textColor: textColor,
        backgroundImage: bgImage,
        clearBackgroundImage: _clearBgImage,
        pageAnimation: pageAnim,
        noAnimScrollPage: noAnimScrollPage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildTopButtons(),
          _buildSeekBars(),
          _buildDivider(),
          _buildPageAnimSection(),
          _buildDivider(),
          _buildStyleSection(),
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTopButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildTextButton('加粗', () {})),
          const SizedBox(width: 6),
          Expanded(child: _buildTextButton('字体', () {})),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTextButton('缩进', () {
              _showIndentPicker();
            }),
          ),
          const SizedBox(width: 6),
          Expanded(child: _buildTextButton('繁简', () {})),
          const SizedBox(width: 6),
          Expanded(child: _buildTextButton('内边距', () {})),
          const SizedBox(width: 6),
          Expanded(child: _buildTextButton('信息', () {})),
        ],
      ),
    );
  }

  Widget _buildTextButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    );
  }

  Widget _buildSeekBars() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildSeekBar(
            title: '字号',
            progress: _fontSizeProgress,
            max: 45,
            display: '${_fontSizeProgress + 5}',
            onChanged: (v) { setState(() => _fontSizeProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '字间距',
            progress: _letterSpacingProgress,
            max: 100,
            display: ((_letterSpacingProgress - 50) / 100.0).toStringAsFixed(2),
            onChanged: (v) { setState(() => _letterSpacingProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '行高',
            progress: _lineHeightProgress,
            max: 20,
            display: ((_lineHeightProgress - 10) / 10.0).toStringAsFixed(1),
            onChanged: (v) { setState(() => _lineHeightProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '段距',
            progress: _paragraphSpacingProgress,
            max: 20,
            display: (_paragraphSpacingProgress / 10.0).toStringAsFixed(1),
            onChanged: (v) { setState(() => _paragraphSpacingProgress = v); _apply(); },
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar({
    required String title,
    required int progress,
    required int max,
    required String display,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        _buildSeekBarButton(LegadoIcons.reduce(size: 24, color: Colors.black54), () {
          if (progress > 0) onChanged(progress - 1);
        }),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              thumbColor: Theme.of(context).colorScheme.primary,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: progress.toDouble().clamp(0, max.toDouble()),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        _buildSeekBarButton(LegadoIcons.add(size: 24, color: Colors.black54), () {
          if (progress < max) onChanged(progress + 1);
        }),
        SizedBox(
          width: 60,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekBarButton(Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 24, height: 24, child: icon),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 0.8,
      color: Colors.grey.shade200,
    );
  }

  Widget _buildPageAnimSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '翻页动画',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildAnimChip('覆盖', PageAnimationType.cover),
              const SizedBox(width: 8),
              _buildAnimChip('滑动', PageAnimationType.slide),
              const SizedBox(width: 8),
              _buildAnimChip('仿真', PageAnimationType.simulation),
              const SizedBox(width: 8),
              _buildAnimChip('滚动', PageAnimationType.scroll),
              const SizedBox(width: 8),
              _buildAnimChip('无动画', PageAnimationType.none),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimChip(String label, PageAnimationType type) {
    final selected = pageAnim == type || (type == PageAnimationType.none && noAnimScrollPage);
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            pageAnim = type;
            noAnimScrollPage = (type == PageAnimationType.none);
          });
          _apply();
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6),
          side: BorderSide(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          ),
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Theme.of(context).colorScheme.primary : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildStyleSection() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '文字底色',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const Text('共用布局', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(width: 4),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: false,
                  onChanged: (v) {},
                  activeColor: Theme.of(context).colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...List.generate(_stylePresets.length, (i) {
                  final preset = _stylePresets[i];
                  final selected =
                      bgColor == preset.bg && textColor == preset.text && bgImage == null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          bgColor = preset.bg;
                          textColor = preset.text;
                          bgImage = null;
                          _clearBgImage = true;
                        });
                        _apply();
                      },
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          color: preset.bg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            preset.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: preset.text,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Center(
                      child: LegadoIcons.add(size: 20, color: Colors.black54),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showIndentPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(9, (i) {
            final indent = i;
            return ListTile(
              title: Text(indent == 0 ? '无缩进' : '缩进 $indent 字符'),
              trailing: textIndent == indent
                  ? LegadoIcons.check(size: 18, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                setState(() => textIndent = indent);
                _apply();
                Navigator.pop(ctx);
              },
            );
          }),
        ),
      ),
    );
  }
}

class _StylePreset {
  final String label;
  final Color bg;
  final Color text;
  const _StylePreset(this.label, this.bg, this.text);
}

class _MoreSettingsSheet extends StatefulWidget {
  final ReadingController controller;
  const _MoreSettingsSheet({required this.controller});

  @override
  State<_MoreSettingsSheet> createState() => _MoreSettingsSheetState();
}

class _MoreSettingsSheetState extends State<_MoreSettingsSheet> {
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
        keepScreenOn: keepScreenOn,
        hideStatusBar: hideStatusBar,
        hideNavigationBar: hideNavigationBar,
        textFullJustify: textFullJustify,
        textBottomJustify: textBottomJustify,
        selectable: selectable,
        showBrightnessView: showBrightnessView,
        noAnimScrollPage: noAnimScrollPage,
        pageAnimation: noAnimScrollPage ? PageAnimationType.none : null,
        showHeaderDivider: showHeaderDivider,
        showFooterDivider: showFooterDivider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: bottomPadding),
              children: [
                _buildSwitch('屏幕常亮', keepScreenOn, (v) => setState(() { keepScreenOn = v; _apply(); })),
                _buildSwitch('隐藏状态栏', hideStatusBar, (v) => setState(() { hideStatusBar = v; _apply(); })),
                _buildSwitch('隐藏导航栏', hideNavigationBar, (v) => setState(() { hideNavigationBar = v; _apply(); })),
                _buildSwitch('文字两端对齐', textFullJustify, (v) => setState(() { textFullJustify = v; _apply(); })),
                _buildSwitch('文字底部对齐', textBottomJustify, (v) => setState(() { textBottomJustify = v; _apply(); })),
                _buildSwitch('允许选择文字', selectable, (v) => setState(() { selectable = v; _apply(); })),
                _buildSwitch('显示亮度调节', showBrightnessView, (v) => setState(() { showBrightnessView = v; _apply(); })),
                _buildSwitch('无动画翻页', noAnimScrollPage, (v) => setState(() {
                  noAnimScrollPage = v;
                  _apply();
                })),
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
}
