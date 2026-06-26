import 'package:flutter/material.dart';
import '../../core/controller/reading_controller.dart';
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
  late int titleMode;
  late Color bgColor;
  late Color textColor;
  late String? bgImage;
  bool _clearBgImage = false;

  static const _stylePresets = [
    _StylePreset('微信读书', Color(0xFFC0EDC6), Color(0xFF0B0B0B),
      fontSize: 24, letterSpacing: 0, lineHeight: 1.15, paragraphSpacing: 0.6),
    _StylePreset('预设1', Color(0xFFFFFFFF), Color(0xFF000000)),
    _StylePreset('预设2', Color(0xFFDDC090), Color(0xFF3E3422)),
    _StylePreset('预设3', Color(0xFFC2D8AA), Color(0xFF596C44)),
    _StylePreset('预设4', Color(0xFFDBB8E2), Color(0xFF68516C)),
    _StylePreset('预设5', Color(0xFFABCEE0), Color(0xFF3D4C54)),
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _fontSizeProgress = s.fontSize.toInt() - 5;
    _letterSpacingProgress = (s.letterSpacing * 100).toInt() + 50;
    _lineHeightProgress = ((s.lineHeight - 1.0) / 0.015).round();
    _paragraphSpacingProgress = (s.paragraphSpacing * 10).toInt();
    textIndent = s.textIndent;
    titleMode = s.titleMode;
    bgColor = s.backgroundColor;
    textColor = s.textColor;
    bgImage = s.backgroundImage;
  }

  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        fontSize: (_fontSizeProgress + 5).toDouble(),
        lineHeight: 1.0 + _lineHeightProgress * 0.015,
        paragraphSpacing: _paragraphSpacingProgress / 10.0,
        letterSpacing: (_letterSpacingProgress - 50) / 100.0,
        textIndent: textIndent,
        titleMode: titleMode,
        backgroundColor: bgColor,
        textColor: textColor,
        backgroundImage: bgImage,
        clearBackgroundImage: _clearBgImage,
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
          Expanded(child: _buildTextButton('信息', () => _showTipConfig())),
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
            title: '字距',
            progress: _letterSpacingProgress,
            max: 100,
            display: ((_letterSpacingProgress - 50) / 100.0).toStringAsFixed(2),
            onChanged: (v) { setState(() => _letterSpacingProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '行距',
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
                          if (preset.fontSize != null) {
                            _fontSizeProgress = preset.fontSize!.toInt() - 5;
                          }
                          if (preset.letterSpacing != null) {
                            _letterSpacingProgress = (preset.letterSpacing! * 100).toInt() + 50;
                          }
                          if (preset.lineHeight != null) {
                            _lineHeightProgress = ((preset.lineHeight! - 1.0) / 0.015).round();
                          }
                          if (preset.paragraphSpacing != null) {
                            _paragraphSpacingProgress = (preset.paragraphSpacing! * 10).toInt();
                          }
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

  void _showTipConfig() {
    showDialog(
      context: context,
      builder: (ctx) => _TipConfigDialog(
        titleMode: titleMode,
        titleSize: widget.controller.settings.titleSize,
        titleTopSpacing: widget.controller.settings.titleTopSpacing,
        titleBottomSpacing: widget.controller.settings.titleBottomSpacing,
        onTitleModeChanged: (v) {
          setState(() => titleMode = v);
          _apply();
        },
        onTitleSizeChanged: (v) {
          widget.controller.updateSettings(
            widget.controller.settings.copyWith(titleSize: v),
          );
        },
        onTitleTopSpacingChanged: (v) {
          widget.controller.updateSettings(
            widget.controller.settings.copyWith(titleTopSpacing: v),
          );
        },
        onTitleBottomSpacingChanged: (v) {
          widget.controller.updateSettings(
            widget.controller.settings.copyWith(titleBottomSpacing: v),
          );
        },
      ),
    );
  }
}

class _StylePreset {
  final String label;
  final Color bg;
  final Color text;
  final double? fontSize;
  final double? letterSpacing;
  final double? lineHeight;
  final double? paragraphSpacing;
  const _StylePreset(this.label, this.bg, this.text, {
    this.fontSize,
    this.letterSpacing,
    this.lineHeight,
    this.paragraphSpacing,
  });
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

class _TipConfigDialog extends StatelessWidget {
  final int titleMode;
  final double titleSize;
  final double titleTopSpacing;
  final double titleBottomSpacing;
  final ValueChanged<int> onTitleModeChanged;
  final ValueChanged<double> onTitleSizeChanged;
  final ValueChanged<double> onTitleTopSpacingChanged;
  final ValueChanged<double> onTitleBottomSpacingChanged;

  const _TipConfigDialog({
    required this.titleMode,
    required this.titleSize,
    required this.titleTopSpacing,
    required this.titleBottomSpacing,
    required this.onTitleModeChanged,
    required this.onTitleSizeChanged,
    required this.onTitleTopSpacingChanged,
    required this.onTitleBottomSpacingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 340,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 正文标题
              const Text('正文标题', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _buildTitleModeSelector(),
              _buildSeekBar('标题字号', titleSize, 20, onTitleSizeChanged),
              _buildSeekBar('上间距', titleTopSpacing, 100, onTitleTopSpacingChanged),
              _buildSeekBar('下间距', titleBottomSpacing, 100, onTitleBottomSpacingChanged),
              const Divider(),
              // 页头
              const Text('页头', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _buildTipRow('显示', '跟随状态栏'),
              _buildTipRow('左', '章节标题'),
              _buildTipRow('中', '无'),
              _buildTipRow('右', '时间'),
              const Divider(),
              // 页尾
              const Text('页尾', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _buildTipRow('显示', '显示'),
              _buildTipRow('左', '书名'),
              _buildTipRow('中', '无'),
              _buildTipRow('右', '页码/总进度'),
              const Divider(),
              // 页头页尾
              const Text('页头页尾', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _buildTipRow('提示颜色', '跟随文字'),
              _buildTipRow('分割线颜色', '跟随文字'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleModeSelector() {
    const options = ['居左', '居中', '隐藏'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('标题模式', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: List.generate(3, (i) =>
              ButtonSegment(value: i, label: Text(options[i])),
            ),
            selected: {titleMode},
            onSelectionChanged: (set) => onTitleModeChanged(set.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(String label, double value, int max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Slider(
              value: value.clamp(0, max.toDouble()),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              label: value.toStringAsFixed(0),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(value.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}
