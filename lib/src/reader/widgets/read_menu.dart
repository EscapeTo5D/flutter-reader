import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/models/reading_settings.dart';
import 'chapter_list_page.dart';
import 'legado_icons.dart';

class ReadMenu extends StatefulWidget {
  final ReadingController controller;

  /// 菜单是否可见(驱动顶栏/底栏/浮动按钮的滑入滑出动画)。
  ///
  /// 由 reader_view 的 _menuMounted 保证挂载, 本字段控制显隐方向:
  /// true → 滑入(Offset.zero + 不透明), false → 滑出(顶栏向上/底栏向下 + 透明)。
  /// 默认 true 保持向后兼容。
  final bool visible;

  const ReadMenu({
    super.key,
    required this.controller,
    this.visible = true,
  });

  @override
  State<ReadMenu> createState() => _ReadMenuState();
}

class _ReadMenuState extends State<ReadMenu> {
  // 对齐 reader_view._menuAnimDuration, 两处必须一致。
  static const Duration _animDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // 顶栏: 从顶部滑入/向上滑出。
        AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1),
          duration: _animDuration,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: _animDuration,
            child: _buildTopBar(context),
          ),
        ),
        const Spacer(),
        // 浮动按钮: 仅淡入淡出。
        AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: _animDuration,
          child: _buildFloatingButtons(context),
        ),
        // 底栏: 从底部滑入/向下滑出。
        AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: _animDuration,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: _animDuration,
            child: _buildBottomBar(context),
          ),
        ),
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
    SmartDialog.show(
      alignment: Alignment.bottomCenter,
      // 对齐原生 ReadStyleDialog.onStart: dimAmount=0.0f + clearFlags(DIM_BEHIND),
      // 阅读页正文完全可见(不被半透明黑遮罩盖住)。
      maskColor: Colors.transparent,
      animationBuilder: _bottomSheetAnimation,
      builder: (_) => _StyleDialog(controller: widget.controller),
    );
  }

  void _showMoreSettings(BuildContext context) {
    SmartDialog.show(
      alignment: Alignment.bottomCenter,
      maskColor: Colors.black.withValues(alpha: 0.5),
      animationBuilder: _bottomSheetAnimation,
      builder: (_) => _MoreSettingsSheet(controller: widget.controller),
    );
  }
}

/// 底部弹窗滑入/滑出动画(对齐 Material BottomSheet 行为)。
/// SmartDialog 默认 bottomCenter 是缩放动画, 改成 Y 轴平移更贴合原 showModalBottomSheet。
Widget _bottomSheetAnimation(
  AnimationController controller,
  Widget child,
  AnimationParam animationParam,
) {
  final offset = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
  return SlideTransition(position: offset, child: child);
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
  late PageAnimMode pageAnimMode;
  // 字重三态(对齐原生 ReadBookConfig.textBold: 0=正常 1=粗体 2=细体)。
  // TextFontWeightConverter 显示 "中/粗/细", 高亮当前项为红色。
  late int _textBold;
  // 简繁转换三态(对齐原生 AppConfig.chineseConverterType: 0=不转换 1=简 2=繁)。
  // ChineseConverter 显示 "简/繁", 高亮当前项(0 时不高亮)。
  // 注意: 本包无中文转换实现, 仅记录选中态, 文本不实际转换。
  int _chineseConverterType = 0;

  // 预设数据对齐原生 legado readConfig.json。
  // - 微信读书: textSize=24, letterSpacing=0, lineSpacingExtra=10, paragraphSpacing=6,
  //   bg=#ffc0edc6, text=#ff0b0b0b (ARGB 0xFF=完全不透明, 等价 #c0edc6/#0b0b0b)。
  // - 预设1~5: 原生 JSON 只存颜色, 其余字段用 Config 类默认值
  //   (textSize=20, letterSpacing=0.1, lineSpacingExtra=12, paragraphSpacing=2)。
  //   切到这些预设时, 文字参数需重置为该默认值(而非保留当前滑块值), 对齐原生语义。
  //
  // lineHeight/paragraphSpacing 用「progress 语义」:
  //   lineHeight 渲染行高 = textHeight × lineHeight;
  //   paragraphSpacing 段距 = textHeight × paragraphSpacing / 10。
  //   progress = lineHeight×10、progress = paragraphSpacing(字段值即 progress)。
  static const _stylePresets = [
    _StylePreset('微信读书', Color(0xFFC0EDC6), Color(0xFF0B0B0B),
      fontSize: 24, letterSpacing: 0, lineHeight: 1.0, paragraphSpacing: 6),
    _StylePreset('预设1', Color(0xFFFFFFFF), Color(0xFF000000),
      fontSize: 20, letterSpacing: 0.1, lineHeight: 1.2, paragraphSpacing: 2),
    _StylePreset('预设2', Color(0xFFDDC090), Color(0xFF3E3422),
      fontSize: 20, letterSpacing: 0.1, lineHeight: 1.2, paragraphSpacing: 2),
    _StylePreset('预设3', Color(0xFFC2D8AA), Color(0xFF596C44),
      fontSize: 20, letterSpacing: 0.1, lineHeight: 1.2, paragraphSpacing: 2),
    _StylePreset('预设4', Color(0xFFDBB8E2), Color(0xFF68516C),
      fontSize: 20, letterSpacing: 0.1, lineHeight: 1.2, paragraphSpacing: 2),
    _StylePreset('预设5', Color(0xFFABCEE0), Color(0xFF3D4C54),
      fontSize: 20, letterSpacing: 0.1, lineHeight: 1.2, paragraphSpacing: 2),
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _fontSizeProgress = s.fontSize.toInt() - 5;
    _letterSpacingProgress = (s.letterSpacing * 100).toInt() + 50;
    // 行距: 字段 lineHeight 是「倍数」(= 原生 lineSpacingExtra/10)。
    // 对齐原生 dsbLineSize(max=20, progress=lineSpacingExtra 整数):
    // progress = lineHeight × 10, 默认 1.2 → 12。
    // (旧实现用 /0.015 步长, 与原生 0.1 步长不符, 反推会漂移。)
    _lineHeightProgress = (s.lineHeight * 10).round();
    // 段距: 字段 paragraphSpacing 的值即原生 progress(默认 2)。
    // 对齐原生 dsbParagraphSpacing(max=20, progress=paragraphSpacing 整数):
    // progress = 字段值, 默认 2.0 → 2。渲染公式 textHeight × paragraphSpacing / 10 不变。
    // (旧实现 ×10 把默认 2.0 推成 20 满格, 与原生 progress=2 不符。)
    _paragraphSpacingProgress = s.paragraphSpacing.round();
    textIndent = s.textIndent;
    titleMode = s.titleMode;
    bgColor = s.backgroundColor;
    textColor = s.textColor;
    bgImage = s.backgroundImage;
    pageAnimMode = s.pageAnimMode;
    // fontWeight → textBold 反推(对齐原生三态):
    // w700(粗) → 1, w300(细) → 2, 其余 → 0(正常)。
    if (s.fontWeight == FontWeight.w700) {
      _textBold = 1;
    } else if (s.fontWeight == FontWeight.w300) {
      _textBold = 2;
    } else {
      _textBold = 0;
    }
  }

  /// textBold(0/1/2) → FontWeight, 对齐原生正常/粗体/细体。
  FontWeight _fontWeightForTextBold(int type) {
    switch (type) {
      case 1: return FontWeight.w700;
      case 2: return FontWeight.w300;
      default: return FontWeight.w400;
    }
  }

  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
      fontSize: (_fontSizeProgress + 5).toDouble(),
      // progress ↔ lineHeight: progress = lineHeight × 10, 步长 0.1(对齐原生)。
      lineHeight: _lineHeightProgress / 10.0,
      // progress ↔ paragraphSpacing: 字段值即 progress(对齐原生整数 progress)。
      paragraphSpacing: _paragraphSpacingProgress.toDouble(),
      letterSpacing: (_letterSpacingProgress - 50) / 100.0,
      // 字重三态 → FontWeight(对齐原生 textBold: 0=正常 w400, 1=粗体 w700, 2=细体 w300)。
      fontWeight: _fontWeightForTextBold(_textBold),
        textIndent: textIndent,
        titleMode: titleMode,
        backgroundColor: bgColor,
        textColor: textColor,
        backgroundImage: bgImage,
        clearBackgroundImage: _clearBgImage,
        pageAnimMode: pageAnimMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // 对齐原生 ReadStyleDialog: 无圆角(顶部直角), 背景=md_grey_50(#FAFAFA)。
    // 原生运行时会被主题 bottomBackground 覆盖, 本包无主题系统故取静态值。
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 对齐原生 dialog_read_book_style.xml: 无拖拽条, 顶部直接是按钮行(marginTop 16dp)。
          const SizedBox(height: 16),
          _buildTopButtons(),
          _buildSeekBars(),
          _buildPageAnimSelector(),
          _buildDivider(),
          _buildStyleSection(),
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  Widget _buildTopButtons() {
    // 对齐原生 dialog_read_book_style.xml: 6 个 StrokeTextView(wrap_content) + 5 个
    // Space(weight=1) 等宽撑开间隙。IntrinsicHeight 让所有按钮等高(stretch)。
    final buttons = <Widget>[
      _buildStrokeButton(_buildWeightSpans(), _showWeightPicker),
      _buildStrokeButton(const Text('字体', style: _strokeButtonStyle), () {}),
      _buildStrokeButton(const Text('缩进', style: _strokeButtonStyle), _showIndentPicker),
      _buildStrokeButton(_buildChineseSpans(), _showChinesePicker),
      _buildStrokeButton(const Text('边距', style: _strokeButtonStyle), () {}),
      _buildStrokeButton(const Text('信息', style: _strokeButtonStyle), _showTipConfig),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < buttons.length; i++) ...[
              if (i > 0) const Expanded(child: SizedBox()), // Space(weight=1)
              buttons[i],
            ],
          ],
        ),
      ),
    );
  }

  static const _strokeButtonStyle = TextStyle(fontSize: 14, color: Colors.black87);

  /// StrokeTextView 风格按钮: 描边圆角 3dp, padding 6/4/6/4dp(对齐原生)。
  Widget _buildStrokeButton(Widget child, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        // 对齐原生 StrokeTextView: paddingLeft/Right=6dp, Top/Bottom=4dp, radius=3dp。
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );
  }

  /// 字重切换器文字 "N/B/L"(对齐原生 strings.xml font_weight_text="N/B/L"),
  /// 高亮当前项为红色(对齐 TextFontWeightConverter: 0=N 正常, 1=B 粗体, 2=L 细体)。
  Widget _buildWeightSpans() {
    const chars = ['N', 'B', 'L'];
    return RichText(
      text: TextSpan(
        style: _strokeButtonStyle,
        children: [
          for (int i = 0; i < 3; i++) ...[
            TextSpan(
              text: chars[i],
              style: i == _textBold
                  ? _strokeButtonStyle.copyWith(color: Colors.red)
                  : null,
            ),
            if (i < 2) const TextSpan(text: '/'),
          ],
        ],
      ),
    );
  }

  /// 简繁切换器文字 "简/繁", 高亮当前项(对齐 ChineseConverter)。
  /// type=1 高亮"简", type=2 高亮"繁", type=0 不高亮。
  Widget _buildChineseSpans() {
    final accent = Theme.of(context).colorScheme.primary;
    return RichText(
      text: TextSpan(
        style: _strokeButtonStyle,
        children: [
          TextSpan(
            text: '简',
            style: _chineseConverterType == 1 ? _strokeButtonStyle.copyWith(color: accent) : null,
          ),
          const TextSpan(text: '/'),
          TextSpan(
            text: '繁',
            style: _chineseConverterType == 2 ? _strokeButtonStyle.copyWith(color: accent) : null,
          ),
        ],
      ),
    );
  }

  /// 字重选择弹窗(对齐 TextFontWeightConverter.selectType: 选项 正常/粗体/细体)。
  void _showWeightPicker() {
    const options = ['正常', '粗体', '细体'];
    SmartDialog.show(
      alignment: Alignment.bottomCenter,
      maskColor: Colors.black.withValues(alpha: 0.5),
      animationBuilder: _bottomSheetAnimation,
      builder: (_) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return ListTile(
                title: Text(options[i]),
                trailing: _textBold == i
                    ? LegadoIcons.check(size: 18, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() => _textBold = i);
                  _apply();
                  SmartDialog.dismiss();
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  /// 简繁选择弹窗(对齐 ChineseConverter.selectType: 不转换/简体/繁体)。
  void _showChinesePicker() {
    const options = ['不转换', '简体', '繁体'];
    SmartDialog.show(
      alignment: Alignment.bottomCenter,
      maskColor: Colors.black.withValues(alpha: 0.5),
      animationBuilder: _bottomSheetAnimation,
      builder: (_) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return ListTile(
                title: Text(options[i]),
                trailing: _chineseConverterType == i
                    ? LegadoIcons.check(size: 18, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() => _chineseConverterType = i);
                  SmartDialog.dismiss();
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  /// 翻页动画模式选择, 复刻原生 legado ReadStyleDialog 的 RadioGroup
  /// (dialog_read_book_style.xml:165-256 + ThemeRadioNoButton)。
  ///
  /// 位于段距滑块之后、底色预设之前, 顶部带 0.8dp 分割线(对齐原生 vw_bg_fg)。
  /// 5 个带边框圆角按钮水平等宽排列, 选中态填充主题强调色(对齐原生 accentColor)。
  /// 运行时 slide/none 生效; cover/simulation/scroll 动画尚未实现, 配置照存。
  Widget _buildPageAnimSelector() {
    const labels = ['覆盖', '滑动', '仿真', '滚动', '无动画'];
    const modes = [
      PageAnimMode.cover,
      PageAnimMode.slide,
      PageAnimMode.simulation,
      PageAnimMode.scroll,
      PageAnimMode.none,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分割线 0.8dp, 水平边距 16, 垂直边距 8 (对齐 vw_bg_fg)。
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 0.8,
          color: Colors.grey.shade200,
        ),
        // 标题: 12sp, alpha 0.75 (对齐 tv_page_anim: alpha=0.75, textSize=12sp)。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '翻页动画',
            style: TextStyle(fontSize: 12, color: Colors.black54.withValues(alpha: 0.75)),
          ),
        ),
        // RadioGroup: marginHorizontal=11dp, 等宽 5 份。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: List.generate(5, (i) {
              final selected = pageAnimMode == modes[i];
              return Expanded(
                child: Container(
                  // margin 4dp (对齐 layout_margin=4dp)。
                  margin: const EdgeInsets.all(4),
                  child: _buildAnimRadio(labels[i], selected, () {
                    if (!selected) {
                      setState(() => pageAnimMode = modes[i]);
                      _apply();
                    }
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// 单个翻页动画按钮, 复刻 ThemeRadioNoButton 选中态:
  /// 默认=透明底+文字色边框+文字色字; 选中=强调色底+强调色边框+白/黑字。
  /// 圆角 2dp, 边框 2dp, padding 5dp (对齐 ThemeRadioNoButton.cornerRadius/strokeWidth=2dp,
  /// padding=5dp)。选中字色按强调色亮暗取黑/白(对齐 ColorUtils.isColorLight)。
  Widget _buildAnimRadio(String label, bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    final isLightAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.light;
    final textColor = Colors.black87;
    final checkedTextColor = isLightAccent ? Colors.black : Colors.white;
    return Material(
      color: selected ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: selected ? accent : textColor,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              color: selected ? checkedTextColor : textColor,
            ),
          ),
        ),
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
            // 对齐原生 dsbLineSize.valueFormat: ((it - 10) / 10f).toString()
            // 默认 progress=12 → 显示 0.2。
            display: ((_lineHeightProgress - 10) / 10.0).toStringAsFixed(1),
            onChanged: (v) { setState(() => _lineHeightProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '段距',
            progress: _paragraphSpacingProgress,
            max: 20,
            // 对齐原生 dsbParagraphSpacing.valueFormat: (it / 10f).toString()
            // 默认 progress=2 → 显示 0.2。
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
    // bottom 16 对齐原生 RecyclerView marginBottom=16dp。
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
          // 对齐原生: 横向 RecyclerView, 6 个预设圆形 + 末尾"+"添加。
          // 每 item 占屏宽 1/6(圆 48dp 居中 + 左右等宽间隔), 6 个预设首屏刚好填满不紧贴;
          // "+"在第 7 格, 需向右滑动才能露出(对齐原生 RecyclerView 滚动行为)。
          LayoutBuilder(
            builder: (context, constraints) {
              // 可用宽度扣除 section 的左右 padding(各 16)后的内容区。
              final itemWidth = constraints.maxWidth / 6;
              return SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: _stylePresets.length + 1,
                  itemBuilder: (ctx, i) {
                    // 最后一项 = "+"添加预设。
                    final isAdd = i == _stylePresets.length;
                    return SizedBox(
                      width: itemWidth,
                      child: Center(
                        child: GestureDetector(
                          onTap: isAdd
                              ? () {}
                              : () {
                                  final preset = _stylePresets[i];
                                  setState(() {
                                    bgColor = preset.bg;
                                    textColor = preset.text;
                                    bgImage = null;
                                    _clearBgImage = true;
                                    if (preset.fontSize != null) {
                                      _fontSizeProgress = preset.fontSize!.toInt() - 5;
                                    }
                                    if (preset.letterSpacing != null) {
                                      _letterSpacingProgress =
                                          (preset.letterSpacing! * 100).toInt() + 50;
                                    }
                                    if (preset.lineHeight != null) {
                                      // progress = lineHeight × 10(对齐原生 lineSpacingExtra 整数语义)
                                      _lineHeightProgress = (preset.lineHeight! * 10).round();
                                    }
                                    if (preset.paragraphSpacing != null) {
                                      // progress = 字段值(对齐原生 paragraphSpacing 整数语义)
                                      _paragraphSpacingProgress = preset.paragraphSpacing!.round();
                                    }
                                  });
                                  _apply();
                                },
                          // 对齐原生 CircleImageView: 48dp 圆形, 1dp 边框。
                          // 选中时边框=accentColor 且文字加粗(StyleAdapter.convert)。
                          child: isAdd
                              ? Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black54),
                                  ),
                                  child: Center(
                                    child: LegadoIcons.add(size: 20, color: Colors.black54),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: _stylePresets[i].bg,
                                    shape: BoxShape.circle,
                                    // 对齐原生 CircleImageView: border 宽度恒 1dp,
                                    // 选中态仅 borderColor 从 textColor 变 accentColor
                                    // (StyleAdapter.convert: 选中 borderColor=accent,
                                    //  未选 borderColor=item.curTextColor(), 宽度均 1dp)。
                                    border: Border.all(
                                      color: bgColor == _stylePresets[i].bg &&
                                              textColor == _stylePresets[i].text &&
                                              bgImage == null
                                          ? Theme.of(context).colorScheme.primary
                                          : _stylePresets[i].text,
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _stylePresets[i].label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _stylePresets[i].text,
                                        fontWeight: bgColor == _stylePresets[i].bg &&
                                                textColor == _stylePresets[i].text &&
                                                bgImage == null
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showIndentPicker() {
    SmartDialog.show(
      alignment: Alignment.bottomCenter,
      maskColor: Colors.black.withValues(alpha: 0.5),
      animationBuilder: _bottomSheetAnimation,
      builder: (_) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
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
                  SmartDialog.dismiss();
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  void _showTipConfig() {
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _TipConfigDialog(
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

class _TipConfigDialog extends StatefulWidget {
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
  State<_TipConfigDialog> createState() => _TipConfigDialogState();
}

class _TipConfigDialogState extends State<_TipConfigDialog> {
  late int titleMode;
  late double titleSize;
  late double titleTopSpacing;
  late double titleBottomSpacing;

  @override
  void initState() {
    super.initState();
    titleMode = widget.titleMode;
    titleSize = widget.titleSize;
    titleTopSpacing = widget.titleTopSpacing;
    titleBottomSpacing = widget.titleBottomSpacing;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 340,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
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
              _buildSeekBar('标题字号', titleSize, 20, (v) { setState(() => titleSize = v); widget.onTitleSizeChanged(v); }),
              _buildSeekBar('上间距', titleTopSpacing, 100, (v) { setState(() => titleTopSpacing = v); widget.onTitleTopSpacingChanged(v); }),
              _buildSeekBar('下间距', titleBottomSpacing, 100, (v) { setState(() => titleBottomSpacing = v); widget.onTitleBottomSpacingChanged(v); }),
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
                  onPressed: () => SmartDialog.dismiss(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题模式选择器, 对齐原生 legado `dialog_tip_config.xml` 的 `rg_title_mode`:
  /// 横向 RadioGroup + 3 个 RadioButton(居左/居中/隐藏), padding 3dp, 点击即时切换选中。
  Widget _buildTitleModeSelector() {
    const options = ['居左', '居中', '隐藏'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RadioGroup<int>(
        groupValue: titleMode,
        onChanged: (v) {
          if (v == null) return;
          setState(() => titleMode = v);
          widget.onTitleModeChanged(v);
        },
        child: Row(
          children: List.generate(3, (i) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<int>(
                  value: i,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                ),
                Text(options[i], style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 3),
              ],
            );
          }),
        ),
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
