import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import '../../aloud/aloud_controller.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/models/reading_settings.dart';
import '../../core/storage/reading_style_preset.dart';
import 'chapter_list_page.dart';
import 'detail_seek_bar.dart';
import 'legado_icons.dart';
import 'read_aloud_dialog.dart';

class ReadMenu extends StatefulWidget {
  final ReadingController controller;

  /// 朗读控制器。非空时底栏「朗读」按钮接 [showReadAloudDialog];
  /// 为空时按钮不显示(对齐原生无 TTS 引擎时的占位, 也避免包强制依赖 aloud 子系统)。
  final AloudController? aloudController;

  /// 菜单是否可见(驱动顶栏/底栏/浮动按钮的滑入滑出动画)。
  ///
  /// 由 reader_view 的 _menuMounted 保证挂载, 本字段控制显隐方向:
  /// true → 滑入(Offset.zero + 不透明), false → 滑出(顶栏向上/底栏向下 + 透明)。
  /// 默认 true 保持向后兼容。
  final bool visible;

  const ReadMenu({
    super.key,
    required this.controller,
    this.aloudController,
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
        AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: _animDuration,
          child: _buildFloatingButtons(context),
        ),
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
      // horizontal 16 对齐 ll_floating_button paddingStart/End;
      // bottom 16 对齐 FAB layout_margin(bottom) —— 悬浮按钮行到面板顶的距离。
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    // 对齐原生 FloatingActionButton fabSize="mini":
    // - shape CircleBorder (M3 默认是圆角矩形, 需显式指定才为圆形)
    // - backgroundColor md_grey_200(#E0E0E0) = 原生 background_menu
    return FloatingActionButton.small(
      heroTag: tooltip,
      onPressed: onPressed,
      backgroundColor: const Color(0xFFE0E0E0),
      foregroundColor: Colors.black54,
      elevation: 2,
      tooltip: tooltip,
      shape: const CircleBorder(),
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
            // 对齐原生 seek_read_page (height=25dp): SizedBox 夹高度 +
            // SliderTheme 调细轨道让滑块在 25dp 高度内居中合理。
            child: SizedBox(
              height: 25,
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: totalPages > 1 ? widget.controller.currentPageIndex.toDouble() : 0,
                  min: 0,
                  max: totalPages > 1 ? (totalPages - 1).toDouble() : 1,
                  activeColor: Colors.black54,
                  inactiveColor: Colors.black26,
                  onChanged: (v) => widget.controller.goToPage(v.toInt()),
                ),
              ),
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
    final aloud = widget.aloudController;
    // 朗读按钮颜色: 注入了 AloudController 才用正常色 + 可点击; 否则灰显且不响应。
    final aloudEnabled = aloud != null;
    return Row(
      children: [
        const Spacer(flex: 1),
        _buildBottomIcon(LegadoIcons.toc(), '目录', () {
          widget.controller.hideMenu();
          _showChapterDrawer(context);
        }),
        const Spacer(flex: 2),
        // 朗读按钮: 对齐原生 legado 底栏固定四按钮之一。
        // 注入了 [AloudController] 才启用, 点击弹朗读控制弹窗; 未注入时灰显禁用
        // (避免宿主不使用 TTS 时按钮点了无反应)。
        _buildBottomIcon(
          LegadoIcons.readAloud(
            color: aloudEnabled ? const Color(0xFF595757) : Colors.black26,
          ),
          '朗读',
          aloudEnabled
              ? () {
                  widget.controller.hideMenu();
                  showReadAloudDialog(context, controller: aloud);
                }
              : null,
          iconColor: aloudEnabled ? Colors.black54 : Colors.black26,
        ),
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

  /// 底栏图标按钮(对齐原生 view_read_menu.xml 底部 ImageView+TextView)。
  /// [onTap] 为 null 时按钮不响应点击但仍占位(用于朗读按钮在未注入引擎时灰显)。
  /// [iconColor] 仅影响标签文字色(图标颜色由 icon widget 自身携带, 见 LegadoIcons)。
  Widget _buildBottomIcon(Widget icon, String label, VoidCallback? onTap,
      {Color? iconColor}) {
    final color = iconColor ?? Colors.black54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对齐原生 ImageView maxHeight=20dp (icon 24→20)。
            SizedBox(width: 20, height: 20, child: icon),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
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

/// 居中选项列表弹窗, 复刻原生 legado `context.alert{}` / `context.selector{}`
/// (`AndroidAlertBuilder.show()` + `filletBackground`)。
///
/// 原生这六个按钮(字重/字体/缩进/简繁/边距/信息)弹出的都是**居中** AlertDialog
/// (只有外层 ReadStyleDialog 自身是 Gravity.BOTTOM), 而非 bottom sheet。
/// AlertDialog 特征: 居中、3dp 圆角(`filletBackground.cornerRadius=3f.dpToPx`)、
/// 主题背景色填充、标准 dim 遮罩、顶部标题、下方 `setItems(...)` 纯文本列表(无 checkmark)。
///
/// 本 helper 同样: 居中、`BorderRadius.circular(3)`、白底、遮罩 0.5、标题在顶、
/// 下方纯文本列表项点击即选即关。字重/缩进/简繁 三处复用, 也供 TipConfigDialog 各行
/// 点开 selector 复用。
void _showOptionList(
  BuildContext context, {
  required String title,
  required List<String> items,
  required ValueChanged<int> onSelected,
}) {
  SmartDialog.show(
    alignment: Alignment.center,
    maskColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => Container(
      // 宽自适应内容(列表项最长决定), 不强制撑满, 贴近 AlertDialog 默认宽度。
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        // 对齐原生 filletBackground: 3dp 圆角 + 主题背景色(此处用白)。
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          for (int i = 0; i < items.length; i++)
            InkWell(
              onTap: () {
                SmartDialog.dismiss();
                onSelected(i);
              },
              child: Padding(
                // 对齐 AlertDialog item 默认 padding 24/12。
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Text(items[i], style: const TextStyle(fontSize: 15)),
              ),
            ),
        ],
      ),
    ),
  );
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
  // 共享排版(对齐原生 ReadBookConfig.shareLayout, 详见 ReadingSettings.shareLayout)。
  // true 时点颜色预设只换 bg/text, 不重置 字号/字距/行距/段距 滑块。
  late bool _shareLayout;
  // 用户自定义预设(从 DB 异步加载), 追加在内置 6 个之后。
  List<ReadingStylePreset> _userPresets = const [];
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
    _shareLayout = s.shareLayout;
    // fontWeight → textBold 反推(对齐原生三态):
    // w700(粗) → 1, w300(细) → 2, 其余 → 0(正常)。
    if (s.fontWeight == FontWeight.w700) {
      _textBold = 1;
    } else if (s.fontWeight == FontWeight.w300) {
      _textBold = 2;
    } else {
      _textBold = 0;
    }
    // 异步加载用户自定义预设(无 repository 时为空, 仅显示内置 6 个)。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserPresets());
  }

  Future<void> _loadUserPresets() async {
    final presets = await widget.controller.loadStylePresets();
    if (mounted) setState(() => _userPresets = presets);
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
        shareLayout: _shareLayout,
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
      _buildStrokeButton(const Text('边距', style: _strokeButtonStyle), _showPaddingConfig),
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

  /// 字重切换器文字 "中/粗/细"。
  /// 原生 strings.xml font_weight_text="N/B/L"(英文), 这里用中文更直观。
  /// 高亮当前项为红色(对齐 TextFontWeightConverter: 0=正常, 1=粗体, 2=细体)。
  Widget _buildWeightSpans() {
    const chars = ['中', '粗', '细'];
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

  /// 字重选择弹窗(对齐 TextFontWeightConverter.selectType)。
  /// 原生: 居中 AlertDialog, 标题"文章字重切换", 选项 正常/粗体/细体, 选中即关。
  void _showWeightPicker() {
    _showOptionList(
      context,
      title: '文章字重切换',
      items: const ['正常', '粗体', '细体'],
      onSelected: (i) {
        setState(() => _textBold = i);
        _apply();
      },
    );
  }

  /// 简繁选择弹窗(对齐 ChineseConverter.selectType)。
  /// 原生: 居中 AlertDialog, 标题"中文简繁体转换", 选项 关闭/繁转简/简转繁, 选中即关。
  void _showChinesePicker() {
    _showOptionList(
      context,
      title: '中文简繁体转换',
      items: const ['关闭', '繁体转简体', '简体转繁体'],
      onSelected: (i) {
        setState(() => _chineseConverterType = i);
      },
    );
  }

  /// 翻页动画模式选择, 复刻原生 legado ReadStyleDialog 的 RadioGroup
  /// (dialog_read_book_style.xml:165-256 + ThemeRadioNoButton)。
  ///
  /// 位于段距滑块之后、底色预设之前, 顶部带 0.8dp 分割线(对齐原生 vw_bg_fg)。
  /// 带边框圆角按钮水平等宽排列, 选中态填充主题强调色(对齐原生 accentColor)。
  /// 运行时 cover/slide/none/simulation 生效; scroll 暂从入口下线(见下)。
  /// ⚠️ scroll(滚动)模式暂从入口下线: 章节切换处内容跳变问题待后续修复,
  /// 代码(scroll_mode_handler.dart 等)保留, 修好后在下方 modes/labels 恢复即可。
  Widget _buildPageAnimSelector() {
    const labels = ['覆盖', '滑动', '仿真', '无动画'];
    const modes = [
      PageAnimMode.cover,
      PageAnimMode.slide,
      PageAnimMode.simulation,
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
            children: List.generate(labels.length, (i) {
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
            // 拖动只刷数字(对齐原生 onProgressChanged→upValue), 松手才 _apply 重排。
            onChanged: (v) => setState(() => _fontSizeProgress = v),
            onChangeEnd: (v) { setState(() => _fontSizeProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '字距',
            progress: _letterSpacingProgress,
            max: 100,
            display: ((_letterSpacingProgress - 50) / 100.0).toStringAsFixed(2),
            onChanged: (v) => setState(() => _letterSpacingProgress = v),
            onChangeEnd: (v) { setState(() => _letterSpacingProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '行距',
            progress: _lineHeightProgress,
            max: 20,
            // 对齐原生 dsbLineSize.valueFormat: ((it - 10) / 10f).toString()
            // 默认 progress=12 → 显示 0.2。
            display: ((_lineHeightProgress - 10) / 10.0).toStringAsFixed(1),
            onChanged: (v) => setState(() => _lineHeightProgress = v),
            onChangeEnd: (v) { setState(() => _lineHeightProgress = v); _apply(); },
          ),
          _buildSeekBar(
            title: '段距',
            progress: _paragraphSpacingProgress,
            max: 20,
            // 对齐原生 dsbParagraphSpacing.valueFormat: (it / 10f).toString()
            // 默认 progress=2 → 显示 0.2。
            display: (_paragraphSpacingProgress / 10.0).toStringAsFixed(1),
            onChanged: (v) => setState(() => _paragraphSpacingProgress = v),
            onChangeEnd: (v) { setState(() => _paragraphSpacingProgress = v); _apply(); },
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
    required ValueChanged<int> onChangeEnd,
  }) {
    return DetailSeekBar(
      title: title,
      progress: progress,
      max: max,
      display: display,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      textColor: Colors.black54,
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
              Expanded(
                // 对齐原生 tv_bg_ts: text_bg_style="颜色与背景 (长按自定义)"。
                child: Text(
                  '颜色与背景 (长按自定义)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Text('共享排版', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(width: 4),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  // 对齐原生 cb_share_layout: 绑定 ReadBookConfig.shareLayout。
                  value: _shareLayout,
                  onChanged: (v) {
                    setState(() => _shareLayout = v ?? false);
                    _apply();
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 对齐原生: 横向 RecyclerView, 内置 6 预设 + 用户自定义预设 + 末尾"+"添加。
          // 每 item 占屏宽 1/6(圆 48dp 居中 + 左右等宽间隔), 6 个预设首屏刚好填满不紧贴;
          // 用户预设与"+"在第 7 格起, 需向右滑动才能露出(对齐原生 RecyclerView 滚动行为)。
          LayoutBuilder(
            builder: (context, constraints) {
              // 可用宽度扣除 section 的左右 padding(各 16)后的内容区。
              final itemWidth = constraints.maxWidth / 6;
              final total = _stylePresets.length + _userPresets.length + 1;
              return SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: total,
                  itemBuilder: (ctx, i) {
                    // 最后一项 = "+"添加预设。
                    final isAdd = i == total - 1;
                    return SizedBox(
                      width: itemWidth,
                      child: Center(
                        child: isAdd
                            ? _buildAddSwatch()
                            : (i < _stylePresets.length
                                ? _buildBuiltinSwatch(i)
                                : _buildUserSwatch(i - _stylePresets.length)),
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

  /// "+"添加预设圆形(对齐原生 footer add swatch)。
  /// 点击: 用当前 bg/text 新建一个用户预设, 存库, 刷新列表, 自动选中。
  Widget _buildAddSwatch() {
    return GestureDetector(
      onTap: _addUserPreset,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black54),
        ),
        child: Center(
          child: LegadoIcons.add(size: 20, color: Colors.black54),
        ),
      ),
    );
  }

  /// 内置预设圆形(0~5)。选中态仅变色(宽度恒 1dp, 对齐原生)。
  Widget _buildBuiltinSwatch(int i) {
    final preset = _stylePresets[i];
    final selected = bgColor == preset.bg &&
        textColor == preset.text &&
        bgImage == null;
    return GestureDetector(
      onTap: () {
        setState(() {
          bgColor = preset.bg;
          textColor = preset.text;
          bgImage = null;
          _clearBgImage = true;
          // 共享排版: true 时只换 bg/text, 不重置排版参数(对齐原生 shareLayout)。
          if (!_shareLayout) {
            if (preset.fontSize != null) {
              _fontSizeProgress = preset.fontSize!.toInt() - 5;
            }
            if (preset.letterSpacing != null) {
              _letterSpacingProgress =
                  (preset.letterSpacing! * 100).toInt() + 50;
            }
            if (preset.lineHeight != null) {
              _lineHeightProgress = (preset.lineHeight! * 10).round();
            }
            if (preset.paragraphSpacing != null) {
              _paragraphSpacingProgress = preset.paragraphSpacing!.round();
            }
          }
        });
        _apply();
      },
      child: _swatchCircle(
        bg: preset.bg,
        text: preset.text,
        label: preset.label,
        selected: selected,
      ),
    );
  }

  /// 用户自定义预设圆形(从 DB 加载)。
  /// 长按 → 编辑弹窗(对齐原生 long-press → BgTextConfigDialog)。
  Widget _buildUserSwatch(int i) {
    final preset = _userPresets[i];
    final selected = bgColor == preset.bgColor &&
        textColor == preset.textColor &&
        bgImage == null;
    return GestureDetector(
      onTap: () {
        setState(() {
          bgColor = preset.bgColor;
          textColor = preset.textColor;
          bgImage = null;
          _clearBgImage = true;
          // 用户预设不携带排版参数, 点选只换色(等价 shareLayout=true 语义)。
        });
        _apply();
      },
      onLongPress: () => _showPresetEditor(preset),
      child: _swatchCircle(
        bg: preset.bgColor,
        text: preset.textColor,
        label: preset.name,
        selected: selected,
      ),
    );
  }

  /// 通用圆形色块(对齐原生 CircleImageView: 48dp, 1dp 边框恒定, 选中仅变色+加粗)。
  Widget _swatchCircle({
    required Color bg,
    required Color text,
    required String label,
    required bool selected,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        // 对齐原生 CircleImageView: border 宽度恒 1dp, 选中态 borderColor 从
        // textColor 变 accentColor(StyleAdapter.convert), 未选 borderColor=textColor。
        border: Border.all(
          color: selected ? Theme.of(context).colorScheme.primary : text,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: text,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 新建用户预设: 用当前 bg/text 色创建, 存库后刷新列表。
  Future<void> _addUserPreset() async {
    final uid = widget.controller.userId;
    if (uid == null) return; // 无 userId(纯内存模式)→ 不持久化。
    final now = DateTime.now();
    final preset = ReadingStylePreset(
      id: 'preset_${now.millisecondsSinceEpoch}',
      userId: uid,
      name: '预设${_stylePresets.length + _userPresets.length + 1}',
      bgColor: bgColor,
      textColor: textColor,
      sortOrder: _userPresets.length,
      createdAt: now,
    );
    await widget.controller.saveStylePreset(preset);
    await _loadUserPresets();
    // 新建的预设即当前选中色, 选中态会自动高亮。
  }

  /// 预设编辑弹窗(对齐原生 BgTextConfigDialog, 极简版: 名称 + bg 色 + text 色)。
  /// 用预设色板网格做颜色选择(不引第三方颜色选择器包)。
  void _showPresetEditor(ReadingStylePreset preset) {
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (_) => _PresetEditorDialog(
        preset: preset,
        onDelete: () async {
          await widget.controller.deleteStylePreset(preset.id);
          await _loadUserPresets();
        },
        onSave: (updated) async {
          await widget.controller.saveStylePreset(updated);
          await _loadUserPresets();
        },
      ),
    );
  }

  /// 缩进选择弹窗(对齐 ReadStyleDialog 的 `context?.selector`)。
  /// 原生 indent 数组 5 项, 段首缩进 = "　"(全角空格) × index, 故 index ∈ 0..4。
  /// 标题"缩进", 居中 AlertDialog, 选中即关。
  void _showIndentPicker() {
    _showOptionList(
      context,
      title: '缩进',
      items: const ['无缩进', '缩进 1 字符', '缩进 2 字符', '缩进 3 字符', '缩进 4 字符'],
      onSelected: (i) {
        setState(() => textIndent = i);
        _apply();
      },
    );
  }

  /// 信息弹窗(对齐原生 TipConfigDialog)。居中全宽, 默认遮罩。
  /// 内部自管理 titleMode 等(同步回 _StyleDialog 的 titleMode), 直接读写 controller.settings。
  void _showTipConfig() {
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _TipConfigDialog(
        controller: widget.controller,
        onTitleModeChanged: (v) {
          setState(() => titleMode = v);
          _apply();
        },
      ),
    );
  }

  /// 边距配置弹窗(对齐原生 PaddingConfigDialog + dialog_read_padding.xml)。
  /// 原生是居中弹窗(0.9 宽, 无 dim)。3 组(页眉/正文/页脚)×4 向 = 12 滑块 + 2 分隔线开关。
  void _showPaddingConfig() {
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (_) => _PaddingConfigDialog(controller: widget.controller),
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

/// 边距配置弹窗, 复刻原生 legado `PaddingConfigDialog`
/// (`dialog_read_padding.xml`)。居中弹窗(无 dim), 3 组×4 向 = 12 滑块
/// + 页眉/页脚分隔线开关。值整数 dp(对齐原生 DetailSeekBar 无 valueFormat)。
///
/// 默认值对齐微信读书预设(assets/defaultData/readConfig.json):
/// 正文 5/4/22/22、页眉 10/0/19/16、页脚 0/10/13/17;
/// 页脚内容行高不再由字段决定(已改为按 tip 内容自适应, 见 tip_layout.dart);
/// showHeaderLine=true, showFooterLine=true。
class _PaddingConfigDialog extends StatefulWidget {
  final ReadingController controller;
  const _PaddingConfigDialog({required this.controller});

  @override
  State<_PaddingConfigDialog> createState() => _PaddingConfigDialogState();
}

class _PaddingConfigDialogState extends State<_PaddingConfigDialog> {
  late double _bodyLeft, _bodyRight;
  late double _headerTop, _headerBottom, _headerLeft, _headerRight;
  late double _footerTop, _footerBottom, _footerLeft, _footerRight;
  late bool _showHeaderLine, _showFooterLine;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.settings.padding;
    _bodyLeft = p.left;
    _bodyRight = p.right;
    _headerTop = p.headerTop;
    _headerBottom = p.headerBottom;
    _headerLeft = p.headerLeft;
    _headerRight = p.headerRight;
    _footerTop = p.footerTop;
    _footerBottom = p.footerBottom;
    _footerLeft = p.footerLeft;
    _footerRight = p.footerRight;
    _showHeaderLine = widget.controller.settings.showHeaderDivider;
    _showFooterLine = widget.controller.settings.showFooterDivider;
  }

  void _apply() {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        padding: widget.controller.settings.padding.copyWith(
          left: _bodyLeft,
          right: _bodyRight,
          headerTop: _headerTop,
          headerBottom: _headerBottom,
          headerLeft: _headerLeft,
          headerRight: _headerRight,
          footerTop: _footerTop,
          footerBottom: _footerBottom,
          footerLeft: _footerLeft,
          footerRight: _footerRight,
        ),
        showHeaderDivider: _showHeaderLine,
        showFooterDivider: _showFooterLine,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 居中弹窗, 宽 0.9 屏宽(对齐原生 setLayout(0.9f, WRAP_CONTENT))。
    final dialogWidth = MediaQuery.of(context).size.width * 0.9;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(10),
          // 对齐原生 BaseDialogFragment: 仅 setBackgroundColor, 无圆角。
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 页眉组 ── 标题行内联 "显示分隔线" + 复选框(对齐 dialog_read_padding.xml)。
                _buildSectionTitle('页眉', _showHeaderLine, (v) {
                  setState(() => _showHeaderLine = v);
                  _apply();
                }),
                _bar('上边距', _headerTop, 100, (v) =>
                    setState(() => _headerTop = v.toDouble())),
                _bar('下边距', _headerBottom, 100, (v) =>
                    setState(() => _headerBottom = v.toDouble())),
                _bar('左边距', _headerLeft, 100, (v) =>
                    setState(() => _headerLeft = v.toDouble())),
                _bar('右边距', _headerRight, 100, (v) =>
                    setState(() => _headerRight = v.toDouble())),
                const SizedBox(height: 8),
                // ── 正文组 ── 无分隔线开关。
                // 上下边距不再生效: 正文上下贴分隔线(排版 availableHeight = pageSize.height,
                // 不减 padding.top/bottom), 故正文组只保留左右页边距。详见 page_engine。
                _buildSectionTitle('正文', null, null),
                _bar('左边距', _bodyLeft, 100, (v) =>
                    setState(() => _bodyLeft = v.toDouble())),
                _bar('右边距', _bodyRight, 100, (v) =>
                    setState(() => _bodyRight = v.toDouble())),
                const SizedBox(height: 8),
                // ── 页脚组 ──
                _buildSectionTitle('页脚', _showFooterLine, (v) {
                  setState(() => _showFooterLine = v);
                  _apply();
                }),
                _bar('上边距', _footerTop, 100, (v) =>
                    setState(() => _footerTop = v.toDouble())),
                _bar('下边距', _footerBottom, 100, (v) =>
                    setState(() => _footerBottom = v.toDouble())),
                _bar('左边距', _footerLeft, 100, (v) =>
                    setState(() => _footerLeft = v.toDouble())),
                _bar('右边距', _footerRight, 100, (v) =>
                    setState(() => _footerRight = v.toDouble())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 分组标题行(对齐原生 `tv_header_padding … showLine cb_show_top_line` 同行)。
  /// 左侧组名(AccentTextView, 18sp), 右侧"显示分隔线"+ SmoothCheckBox。
  /// [showLine]/[onToggle] 为 null 时(正文组)仅显示组名。
  Widget _buildSectionTitle(String text, bool? showLine, ValueChanged<bool>? onToggle) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (showLine != null && onToggle != null) ...[
            Text('显示分隔线', style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: showLine,
                onChanged: (v) => onToggle(v ?? false),
                activeColor: Theme.of(context).colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(String title, double value, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DetailSeekBar(
        title: title,
        progress: value.round().clamp(0, max),
        max: max,
        display: value.round().toString(),
        // 拖动只刷数字, 松手才 _apply(对齐原生 DetailSeekBar onStopTrackingTouch)。
        onChanged: onChanged,
        onChangeEnd: (v) { onChanged(v); _apply(); },
      ),
    );
  }
}

/// 预设编辑弹窗(极简版, 对齐原生 BgTextConfigDialog 的子集)。
/// 字段: 名称 + 背景色 + 文字色。颜色用预设色板网格选(不引第三方颜色选择器)。
class _PresetEditorDialog extends StatefulWidget {
  final ReadingStylePreset preset;
  final Future<void> Function() onDelete;
  final Future<void> Function(ReadingStylePreset updated) onSave;

  const _PresetEditorDialog({
    required this.preset,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<_PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<_PresetEditorDialog> {
  late final TextEditingController _nameController;
  late Color _bg;
  late Color _text;

  // 预设色板(对齐原生 readConfig.json 的 6 预设色 + 常用色, 网格点选)。
  static const _swatch = <Color>[
    Color(0xFFC0EDC6), Color(0xFFFFFFFF), Color(0xFFDDC090), Color(0xFFC2D8AA),
    Color(0xFFDBB8E2), Color(0xFFABCEE0), Color(0xFFF5F5DC), Color(0xFFE8E8E8),
    Color(0xFF0B0B0B), Color(0xFF3E3422), Color(0xFF596C44), Color(0xFF68516C),
    Color(0xFF3D4C54), Color(0xFF333333), Color(0xFF666666), Color(0xFF999999),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset.name);
    _bg = widget.preset.bgColor;
    _text = widget.preset.textColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = MediaQuery.of(context).size.width * 0.85;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 名称行
              Row(
                children: [
                  const Text('名称', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _colorSection('背景色', _bg, (c) => setState(() => _bg = c)),
              const SizedBox(height: 8),
              _colorSection('文字色', _text, (c) => setState(() => _text = c)),
              const SizedBox(height: 16),
              // 按钮行: 删除 / 保存
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      await widget.onDelete();
                      if (mounted) SmartDialog.dismiss();
                    },
                    child: const Text('删除',
                        style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final updated = widget.preset.copyWith(
                        name: _nameController.text.trim().isEmpty
                            ? '预设'
                            : _nameController.text.trim(),
                        bgColor: _bg,
                        textColor: _text,
                      );
                      await widget.onSave(updated);
                      if (mounted) SmartDialog.dismiss();
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorSection(
      String label, Color selected, ValueChanged<Color> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              // 当前选中色预览
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 8,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
          children: _swatch.map((c) {
            final isSel = c.toARGB32() == selected.toARGB32();
            return GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSel
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black12,
                    width: isSel ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
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

/// 信息弹窗(对齐原生 TipConfigDialog + dialog_tip_config.xml)。
/// 居中、近全宽(对齐 MATCH_PARENT)、默认遮罩。直接读写 controller.settings。
///
/// 结构(对齐原生):
/// - 正文标题: RadioGroup(靠左/居中/隐藏) + 3 个 DetailSeekBar(字号/上边距/下边距)
/// - 页眉/页脚: 每行(显示/左/中/右)可点 → 弹居中 selector(复用 _showOptionList)
/// - 页眉页脚: 提示颜色 / 分隔线颜色 行可点 → selector(跟随文字/自定义)
///
/// 「显示」行: 原生 headerMode 两态(0=显示跟随状态栏, 1=隐藏)。Flutter 映射为
/// headerConfig.hidden(true=隐藏)。点击 selector 在「显示」/「隐藏」间切。
/// 「左/中/右」行: 选项 = Flutter 支持的 TipPosition 全集, 选后 clearRepeat 去重
/// (对齐原生: 同一 tip 在三槽位中唯一, 非 none 不可重复, 重复则清旧槽)。
class _TipConfigDialog extends StatefulWidget {
  final ReadingController controller;
  /// titleMode 变更同步回外层 _StyleDialog(其 _apply 会一起持久化)。
  final ValueChanged<int> onTitleModeChanged;

  const _TipConfigDialog({
    required this.controller,
    required this.onTitleModeChanged,
  });

  @override
  State<_TipConfigDialog> createState() => _TipConfigDialogState();
}

class _TipConfigDialogState extends State<_TipConfigDialog> {
  late int _titleMode;
  late double _titleSize;
  late double _titleTopSpacing;
  late double _titleBottomSpacing;

  // TipPosition 名称, 对齐原生 read_tip 数组(取 Flutter 支持的 10 项, 顺序贴近原生)。
  static const _tipLabels = <TipPosition, String>{
    TipPosition.none: '无',
    TipPosition.bookName: '书名',
    TipPosition.chapterTitle: '标题',
    TipPosition.time: '时间',
    TipPosition.battery: '电量',
    TipPosition.batteryPercent: '电量%',
    TipPosition.pageNumber: '页数',
    TipPosition.progress: '进度(%)',
    TipPosition.timeAndBattery: '时间及电量',
    TipPosition.pageAndTotal: '页数及进度',
  };

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _titleMode = s.titleMode;
    _titleSize = s.titleSize;
    _titleTopSpacing = s.titleTopSpacing;
    _titleBottomSpacing = s.titleBottomSpacing;
  }

  void _updateSettings(ReadingSettings copy) {
    widget.controller.updateSettings(copy);
    setState(() {}); // 刷新行右侧当前值显示。
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.settings;
    return Center(
      child: Padding(
        // 对齐原生 MATCH_PARENT: 左右各留 16dp 边距 → 近全宽。
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).dialogTheme.backgroundColor ??
                  Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAccentTitle('正文标题'),
                  _buildTitleModeSelector(),
                  _buildTitleSeekBar('字号', _titleSize, 20,
                    onChanged: (v) => setState(() => _titleSize = v),
                    onChangeEnd: (v) =>
                        _updateSettings(s.copyWith(titleSize: v)),
                  ),
                  _buildTitleSeekBar('上边距', _titleTopSpacing, 100,
                    onChanged: (v) => setState(() => _titleTopSpacing = v),
                    onChangeEnd: (v) =>
                        _updateSettings(s.copyWith(titleTopSpacing: v)),
                  ),
                  _buildTitleSeekBar('下边距', _titleBottomSpacing, 100,
                    onChanged: (v) => setState(() => _titleBottomSpacing = v),
                    onChangeEnd: (v) =>
                        _updateSettings(s.copyWith(titleBottomSpacing: v)),
                  ),
                  _buildAccentTitle('页眉'),
                  _buildTipRow('显示/隐藏', s.headerConfig.hidden ? '隐藏' : '显示',
                      () => _showHeaderFooterVisibleSelector(isHeader: true)),
                  _buildTipRow('左', _tipLabels[s.headerConfig.left]!,
                      () => _showTipSlotSelector(isHeader: true, slot: _Slot.left)),
                  _buildTipRow('中', _tipLabels[s.headerConfig.center]!,
                      () => _showTipSlotSelector(isHeader: true, slot: _Slot.center)),
                  _buildTipRow('右', _tipLabels[s.headerConfig.right]!,
                      () => _showTipSlotSelector(isHeader: true, slot: _Slot.right)),
                  _buildAccentTitle('页脚'),
                  _buildTipRow('显示/隐藏', s.footerConfig.hidden ? '隐藏' : '显示',
                      () => _showHeaderFooterVisibleSelector(isHeader: false)),
                  _buildTipRow('左', _tipLabels[s.footerConfig.left]!,
                      () => _showTipSlotSelector(isHeader: false, slot: _Slot.left)),
                  _buildTipRow('中', _tipLabels[s.footerConfig.center]!,
                      () => _showTipSlotSelector(isHeader: false, slot: _Slot.center)),
                  _buildTipRow('右', _tipLabels[s.footerConfig.right]!,
                      () => _showTipSlotSelector(isHeader: false, slot: _Slot.right)),
                  _buildAccentTitle('页眉页脚'),
                  _buildTipRow(
                      '提示颜色',
                      s.tipColor == s.textColor ? '跟随文字' : '#${_hex(s.tipColor)}',
                      () => _showColorSelector(
                          isTip: true,
                          current: s.tipColor,
                          followColor: s.textColor)),
                  _buildTipRow(
                      '分隔线颜色',
                      _dividerColorLabel(s),
                      () => _showDividerColorSelector(s)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccentTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 标题模式 RadioGroup(对齐 dialog_tip_config.xml rg_title_mode: 靠左/居中/隐藏)。
  Widget _buildTitleModeSelector() {
    const options = ['靠左', '居中', '隐藏'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RadioGroup<int>(
        groupValue: _titleMode,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _titleMode = v);
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

  Widget _buildTitleSeekBar(
      String label, double value, int max,
      {required ValueChanged<double> onChanged,
       required ValueChanged<double> onChangeEnd}) {
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
              // 拖动只刷数字(右侧值 + label bubble), 松手才 _updateSettings 重排
              // (titleSize/titleTopSpacing/titleBottomSpacing 都进排版指纹)。
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(value.toStringAsFixed(0),
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// 单行(label + 当前值), 整行可点。padding 6dp(对齐 dialog_tip_config.xml 各 ll_* 项)。
  Widget _buildTipRow(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  /// 页眉/页脚「显示/隐藏」selector(对齐原生 headerMode/footerMode 两态)。
  void _showHeaderFooterVisibleSelector({required bool isHeader}) {
    final s = widget.controller.settings;
    final cfg = isHeader ? s.headerConfig : s.footerConfig;
    _showOptionList(
      context,
      title: isHeader ? '页眉显示' : '页脚显示',
      items: const ['显示', '隐藏'],
      onSelected: (i) {
        final newCfg = cfg.copyWith(hidden: i == 1);
        _updateSettings(s.copyWith(
          headerConfig: isHeader ? newCfg : null,
          footerConfig: isHeader ? null : newCfg,
        ));
      },
    );
  }

  /// 页眉/页脚某槽位的 TipPosition selector(对齐原生 tipNames selector)。
  /// 选后 clearRepeat: 非 none 的 tip 在两区六槽中唯一, 重复则把旧槽清成 none。
  void _showTipSlotSelector({required bool isHeader, required _Slot slot}) {
    final s = widget.controller.settings;
    final order = _tipLabels.keys.toList(); // 保持 selector 选项顺序稳定。
    _showOptionList(
      context,
      title: '选择显示内容',
      items: order.map((p) => _tipLabels[p]!).toList(),
      onSelected: (i) {
        final chosen = order[i];
        final updated = _clearRepeat(s, chosen, excludeIsHeader: isHeader, excludeSlot: slot);
        HeaderFooterConfig h = updated.headerConfig;
        HeaderFooterConfig f = updated.footerConfig;
        if (isHeader) {
          h = _withSlot(h, slot, chosen);
        } else {
          f = _withSlot(f, slot, chosen);
        }
        _updateSettings(s.copyWith(headerConfig: h, footerConfig: f));
      },
    );
  }

  /// 提示颜色 selector(对齐原生 tipColorNames: 跟随文字 / 自定义)。
  /// 自定义 → 复用 _PresetEditorDialog 的预设色板网格(独立小弹窗)。
  void _showColorSelector({
    required bool isTip,
    required Color current,
    required Color followColor,
  }) {
    _showOptionList(
      context,
      title: isTip ? '提示颜色' : '分隔线颜色',
      items: const ['跟随文字', '自定义'],
      onSelected: (i) {
        if (i == 0) {
          final s = widget.controller.settings;
          _updateSettings(s.copyWith(
            tipColor: isTip ? followColor : null,
            tipDividerColor: isTip ? null : followColor,
          ));
        } else {
          _showCustomColorSwatch(isTip: isTip);
        }
      },
    );
  }

  /// 分隔线颜色 selector(原生 tipDividerColorNames: 跟随文字 / 跟随背景 / 自定义)。
  /// Flutter 端分隔线颜色: null=跟随文字, 用 sentinel #00000000(完全透明) 表示跟随背景。
  void _showDividerColorSelector(ReadingSettings s) {
    _showOptionList(
      context,
      title: '分隔线颜色',
      items: const ['跟随文字', '跟随背景', '自定义'],
      onSelected: (i) {
        if (i == 0) {
          _updateSettings(s.copyWith(tipDividerColor: null));
        } else if (i == 1) {
          // 透明色作为「跟随背景」标记(page_view 渲染时若遇此色可回退背景)。
          _updateSettings(s.copyWith(tipDividerColor: const Color(0x00000000)));
        } else {
          _showCustomColorSwatch(isTip: false, isDivider: true);
        }
      },
    );
  }

  /// 自定义颜色: 预设色板网格点选(复用 _PresetEditorDialog 同款 _swatch)。
  void _showCustomColorSwatch({required bool isTip, bool isDivider = false}) {
    final s = widget.controller.settings;
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _ColorSwatchPicker(
        current: isDivider ? (s.tipDividerColor ?? s.tipColor) : s.tipColor,
        onPicked: (c) {
          _updateSettings(s.copyWith(
            tipColor: isTip && !isDivider ? c : null,
            tipDividerColor: isDivider ? c : null,
          ));
        },
      ),
    );
  }

  String _dividerColorLabel(ReadingSettings s) {
    if (s.tipDividerColor == null) return '跟随文字';
    if (s.tipDividerColor!.toARGB32() == 0x00000000) return '跟随背景';
    return '#${_hex(s.tipDividerColor!)}';
  }

  /// clearRepeat: 把与 [chosen](非 none) 相同的旧槽位清成 none, 跳过 (excludeIsHeader,excludeSlot)。
  HeaderFooterConfig _clearConfigRepeat(
      HeaderFooterConfig cfg, TipPosition chosen, bool isThis, _Slot slot) {
    if (chosen == TipPosition.none) return cfg;
    TipPosition clear(TipPosition p, _Slot which) {
      if (p == chosen && !(isThis && which == slot)) return TipPosition.none;
      return p;
    }
    return cfg.copyWith(
      left: clear(cfg.left, _Slot.left),
      center: clear(cfg.center, _Slot.center),
      right: clear(cfg.right, _Slot.right),
    );
  }

  ReadingSettings _clearRepeat(ReadingSettings s, TipPosition chosen,
      {required bool excludeIsHeader, required _Slot excludeSlot}) {
    return s.copyWith(
      headerConfig: _clearConfigRepeat(
          s.headerConfig, chosen, excludeIsHeader, excludeSlot),
      footerConfig: _clearConfigRepeat(
          s.footerConfig, chosen, !excludeIsHeader, excludeSlot),
    );
  }

  static HeaderFooterConfig _withSlot(HeaderFooterConfig cfg, _Slot slot, TipPosition v) {
    switch (slot) {
      case _Slot.left:
        return cfg.copyWith(left: v);
      case _Slot.center:
        return cfg.copyWith(center: v);
      case _Slot.right:
        return cfg.copyWith(right: v);
    }
  }

  static String _hex(Color c) {
    final v = c.toARGB32();
    return '${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }
}

/// TipConfigDialog 内槽位枚举(左/中/右), 仅用于参数传递。
enum _Slot { left, center, right }

/// 颜色色板点选弹窗(复用 _PresetEditorDialog 的预设色板, 不引第三方颜色选择器)。
class _ColorSwatchPicker extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onPicked;
  // 对齐 _PresetEditorDialog._swatch(常用底/字色 + 灰阶)。
  static const _swatch = <Color>[
    Color(0xFFC0EDC6), Color(0xFFFFFFFF), Color(0xFFDDC090), Color(0xFFC2D8AA),
    Color(0xFFDBB8E2), Color(0xFFABCEE0), Color(0xFFF5F5DC), Color(0xFFE8E8E8),
    Color(0xFF0B0B0B), Color(0xFF3E3422), Color(0xFF596C44), Color(0xFF68516C),
    Color(0xFF3D4C54), Color(0xFF333333), Color(0xFF666666), Color(0xFF999999),
  ];

  const _ColorSwatchPicker({required this.current, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
        ),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
          children: _swatch.map((c) {
            final isSel = c.toARGB32() == current.toARGB32();
            return GestureDetector(
              onTap: () {
                onPicked(c);
                SmartDialog.dismiss();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSel ? Theme.of(context).colorScheme.primary : Colors.black26,
                    width: isSel ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
