import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../aloud/aloud_controller.dart';
import '../../aloud/http_tts_config.dart';
import 'chapter_list_page.dart';
import 'legado_icons.dart';
import 'read_menu.dart' show MenuPalette;

/// 显示朗读控制弹窗(对齐原生 legado `ReadAloudDialog`)。
///
/// 原生 `dialog_read_aloud.xml` 的弹窗: 从底部弹出、`dimAmount=0`(背景不暗化)、
/// 无圆角直角贴屏底、背景 `md_grey_200`(#E0E0E0)。3 个区块:
/// ① 播放控制(上一章/上一段/播放/停止/下一段/下一章)
/// ② 语速(滑块 max45 + 加减按钮 + 跟随系统开关)
/// ③ 底部功能栏(目录/主菜单/设置)
///
/// 不含定时停止、后台朗读(需 Foreground Service)、通知栏(MediaSession)——这些
/// 依赖 audio_service 的能力暂不实现(`AudioHandler` 抽象已预留扩展点)。
void showReadAloudDialog(
  BuildContext context, {
  required AloudController controller,
  List<HttpTtsConfig> httpConfigs = const [],
}) {
  // ⚠️ 必须从调用方 context 取 Navigator: SmartDialog 的 builder 闭包里 widget 树挂在
  // SmartDialog 自己的 Overlay 上, 不在 MaterialApp 的 Navigator 下, dialog 内部
  // Navigator.of(context) 会抛 "context does not include a Navigator"。
  // 调用方(ReaderView)的 context 在 MaterialApp.Navigator 子树里, 故这里抓出来透传。
  final appNavigator = Navigator.of(context, rootNavigator: true);
  SmartDialog.show(
    alignment: Alignment.bottomCenter,
    // 对齐原生 ReadAloudDialog.onStart: dimAmount=0.0f, 背景不暗化。
    maskColor: Colors.transparent,
    animationBuilder: _bottomSheetAnimation,
    builder: (_) => _ReadAloudDialog(
      controller: controller,
      httpConfigs: httpConfigs,
      appNavigator: appNavigator,
    ),
  );
}

/// 底部滑入动画(复用 read_menu.dart 的 _bottomSheetAnimation 模式)。
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

class _ReadAloudDialog extends StatefulWidget {
  final AloudController controller;
  final List<HttpTtsConfig> httpConfigs;
  /// 宿主 Navigator(用于目录页跳转)。SmartDialog Overlay 不在 MaterialApp
  /// Navigator 子树下, dialog 内部无法用自身 context 取到, 须由调用方注入。
  final NavigatorState appNavigator;

  const _ReadAloudDialog({
    required this.controller,
    required this.httpConfigs,
    required this.appNavigator,
  });

  @override
  State<_ReadAloudDialog> createState() => _ReadAloudDialogState();
}

class _ReadAloudDialogState extends State<_ReadAloudDialog> {
  // 语速 progress(对齐原生 seek_tts_speechRate: max=45, 默认 5)。
  // 显示倍率 = (progress + 5) / 10, 即 5→1.0, 15→2.0, 45→5.0。
  // AloudController.rate 是 double 倍率, UI 层做 int↔double 换算。
  late int _speechRateProgress;

  // 控制面板配色: 朗读弹窗随 isNightTheme 切深/浅色(对齐原生主题系统)。
  MenuPalette get _palette =>
      MenuPalette.of(widget.controller.reader.settings);
  Color get _textColor => _palette.onSurface;

  @override
  void initState() {
    super.initState();
    // rate(double 倍率) → progress 整数: progress = rate × 10 - 5。
    _speechRateProgress = (widget.controller.rate * 10 - 5).round().clamp(0, 45);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 语速 progress → 倍率, 应用到 controller(对齐原生 upTtsSpeechRateText 公式)。
  void _applySpeechRate(int progress) {
    setState(() => _speechRateProgress = progress);
    widget.controller.setRate((progress + 5) / 10.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      // 对齐原生 ReadAloudDialog.onFragmentCreated: 运行时根背景被覆盖为
      // bottomBackground(主题色), 日间默认通常白色。包内走 palette(夜晚切 #1F1F1F)。
      color: _palette.surface,
      padding: EdgeInsets.fromLTRB(16, 6, 16, 6 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPlayControlRow(c),
          _buildSpeechRateSection(),
          _buildBottomActionBar(c),
        ],
      ),
    );
  }

  // ──────────────────────── 区块 ① 播放控制行 ────────────────────────
  //
  // 对齐原生: [上一章文字][弹性空][上一段][播放/暂停][停止][下一段][弹性空][下一章文字]
  // ImageView 30×30dp marginH8, 文字 14sp marginH10 paddingV10。
  Widget _buildPlayControlRow(AloudController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chapterTextButton('上一章', c.reader.canGoPrevious
            ? () => c.previousChapter()
            : null),
        const Expanded(child: SizedBox()),
        _iconButton(
          LegadoIcons.skipPrevious(color: _textColor),
          '上一段',
          c.previousParagraph,
        ),
        // 对齐原生 ImageView marginH=8: 相邻图标间总间距 8+8=16dp。
        const SizedBox(width: 16),
        _iconButton(
          c.isPlaying
              ? LegadoIcons.pause(color: _textColor)
              : LegadoIcons.play(color: _textColor),
          c.isPlaying ? '暂停' : '播放',
          () async {
            if (c.isPlaying) {
              await c.pause();
            } else if (c.isPaused) {
              await c.resume();
            } else {
              await c.start();
            }
          },
        ),
        const SizedBox(width: 16),
        _iconButton(
          LegadoIcons.stop(color: _textColor),
          '停止',
          () async {
            await c.stop();
            if (mounted) SmartDialog.dismiss();
          },
        ),
        const SizedBox(width: 16),
        _iconButton(
          LegadoIcons.skipNext(color: _textColor),
          '下一段',
          c.nextParagraph,
        ),
        const Expanded(child: SizedBox()),
        _chapterTextButton('下一章',
            c.reader.canGoNext ? () => c.nextChapter() : null),
      ],
    );
  }

  /// 上一章/下一章文字按钮(对齐原生 tv_pre/tv_next: 14sp, marginH10, paddingV10)。
  Widget _chapterTextButton(String text, VoidCallback? onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: onPressed != null ? _textColor : _palette.onSurfaceDisabled,
            ),
          ),
        ),
      ),
    );
  }

  /// 播放控制图标按钮(对齐原生 ImageView: marginH8, selectableItemBackgroundBorderless)。
  ///
  /// 传入的 icon 应是 size=24 的 LegadoIcons(矢量原始尺寸, 精致)。本方法用 32×32
  /// 触摸区把图标居中(对齐原生 30dp 触摸区装 24dp 矢量的精神, 同时保证可点性)。
  Widget _iconButton(Widget icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(child: icon),
        ),
      ),
    );
  }

  // ──────────────────────── 区块 ② 语速行 ────────────────────────
  //
  // 对齐原生: 垂直容器含两子行。
  // 子行 A(padding8): [朗读语速14sp][数值14sp][弹性空][跟随系统 Switch+label]
  // 子行 B(paddingH6): [减图标30×30][SeekBar weight1 max45 连续][加图标30×30]
  // 跟随系统开启时禁用滑块+加减(对齐原生 upTtsSpeechRateEnabled)。
  Widget _buildSpeechRateSection() {
    return Column(
      children: [
        // 子行 A: 标签 + 数值 + 跟随系统开关。
        // 对齐原生 cb_tts_follow_sys(ThemeSwitch=SwitchCompat, text="跟随系统" 直接
        // 挂在开关上): 文字紧贴开关左侧形成一组, 故这里 Text 与 Switch 之间无间距,
        // 且整组右侧对齐(前面 Spacer 撑开)。
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text('朗读语速',
                  style: TextStyle(fontSize: 14, color: _textColor)),
              const SizedBox(width: 3),
              // 对齐原生 upTtsSpeechRateText: ((progress + 5) / 10f).toString()。
              // ⚠️ 跟随系统开启时不显示数值(对齐原生 upTtsSpeechRateEnabled 隐藏 value)。
              if (!widget.controller.followSysRate)
                Text(
                  ((_speechRateProgress + 5) / 10).toString(),
                  style: TextStyle(fontSize: 14, color: _textColor),
                ),
              const Spacer(),
              // 跟随系统: 文字 + 开关紧贴成一组(对齐 SwitchCompat 的 text 内嵌)。
              // 开关态存 controller(持久化), 默认 true(对齐原生 ttsFollowSys)。
              GestureDetector(
                onTap: () => widget.controller
                    .setFollowSysRate(!widget.controller.followSysRate),
                child: Text('跟随系统',
                    style: TextStyle(
                        fontSize: 14,
                        color: widget.controller.followSysRate
                            ? Theme.of(context).colorScheme.primary
                            : _textColor)),
              ),
              Switch(
                value: widget.controller.followSysRate,
                onChanged: (v) => widget.controller.setFollowSysRate(v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        // 子行 B: 减 + 滑块 + 加
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              _iconButton(
                LegadoIcons.reduce(color: _textColor),
                '语速减',
                widget.controller.followSysRate
                    ? null
                    : () {
                        if (_speechRateProgress > 0) {
                          _applySpeechRate(_speechRateProgress - 1);
                        }
                      },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: _textColor.withValues(alpha: 0.3),
                    thumbColor: Theme.of(context).colorScheme.primary,
                    disabledActiveTrackColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                    disabledThumbColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                  child: Slider(
                    value: _speechRateProgress.toDouble(),
                    min: 0,
                    max: 45,
                    // 不设 divisions: 对齐原生 ThemeSeekBar(AppCompatSeekBar)
                    // 连续 track, 避免分段刻度颗粒。progress 内部 round 成整数。
                    onChanged: widget.controller.followSysRate
                        ? null
                        : (v) => setState(
                            () => _speechRateProgress = v.round()),
                    onChangeEnd: widget.controller.followSysRate
                        ? null
                        : (v) => _applySpeechRate(v.round()),
                  ),
                ),
              ),
              _iconButton(
                LegadoIcons.add(color: _textColor),
                '语速加',
                widget.controller.followSysRate
                    ? null
                    : () {
                        if (_speechRateProgress < 45) {
                          _applySpeechRate(_speechRateProgress + 1);
                        }
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────── 区块 ③ 底部功能栏 ────────────────────────
  //
  // 对齐原生: marginTop8, 3 按钮×60dp + 4 个 weight2 空隙(两端 + 项间)。
  // [目录][主菜单][设置], 每个垂直: 图标(maxH20) + 文字(12sp marginTop3 paddingBottom7)。
  //   目录 → 打开目录页(通过 reader)
  //   主菜单 → dismiss 露出下层 ReadMenu
  //   设置 → 暂只做引擎切换子弹窗(原生是 ReadAloudConfigDialog 高级配置)
  Widget _buildBottomActionBar(AloudController c) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Spacer(flex: 2),
          _buildActionItem(
            LegadoIcons.toc(size: 20, color: _textColor),
            '目录',
            () {
              SmartDialog.dismiss();
              _openChapterList(c);
            },
          ),
          const Spacer(flex: 2),
          _buildActionItem(
            LegadoIcons.mainMenu(size: 20, color: _textColor),
            '主菜单',
            // 对齐原生 showMenuBar + dismiss: dismiss 朗读弹窗后重新显示阅读主菜单。
            // 打开朗读弹窗时 ReadMenu 已 hideMenu(menuVisible=false), 故这里
            // dismiss 后调 toggleMenu() 翻转为 true 重新显示。
            () {
              SmartDialog.dismiss();
              c.reader.toggleMenu();
            },
          ),
          const Spacer(flex: 2),
          _buildActionItem(
            LegadoIcons.settings(size: 20, color: _textColor),
            '设置',
            () => _showEnginePicker(),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  /// 底部功能栏单项(对齐原生 ll_catalog 等: 60dp 宽, 图标 20dp + 文字 12sp)。
  /// icon 参数应传 size:20 的 LegadoIcons(对齐原生 maxHeight=20dp)。
  Widget _buildActionItem(Widget icon, String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: disabled ? _palette.onSurfaceDisabled : _textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开目录页(复用 ChapterListPage)。
  void _openChapterList(AloudController c) {
    final book = c.reader.book;
    if (book == null) return;
    // ⚠️ 不能用 dialog 自身 context 取 Navigator: SmartDialog 把本 widget 挂在
    // SmartDialog 自己的 Overlay 上, 不在 MaterialApp 的 Navigator 子树下,
    // Navigator.of(context) 会抛 "context does not include a Navigator"。
    // 用注入的 widget.appNavigator(调用方 ReaderView 的 context 抓的)。
    // 延迟到下一帧, 让 SmartDialog 先完成 dismiss 卸载, 避免 overlay 冲突。
    final nav = widget.appNavigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChapterListPage(controller: c.reader),
        ),
      );
    });
  }

  /// 引擎选择(原生在 ReadAloudConfigDialog 子对话框, 此处极简 selector)。
  void _showEnginePicker() {
    final c = widget.controller;
    SmartDialog.show(
      alignment: Alignment.center,
      maskColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _palette.dialogBackground,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                '朗读引擎',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _palette.onSurface),
              ),
            ),
            InkWell(
              onTap: () {
                SmartDialog.dismiss();
                c.selectEngine(AloudEngineType.system);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('系统 TTS',
                            style: TextStyle(
                                fontSize: 15, color: _palette.onSurface))),
                    if (c.engineType == AloudEngineType.system)
                      Icon(Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: widget.httpConfigs.isEmpty
                  ? null
                  : () {
                      SmartDialog.dismiss();
                      c.selectEngine(AloudEngineType.http,
                          httpConfig: widget.httpConfigs.first);
                    },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.httpConfigs.isEmpty
                            ? 'HTTP TTS(未配置)'
                            : 'HTTP TTS',
                        style: TextStyle(
                          fontSize: 15,
                          color: widget.httpConfigs.isEmpty
                              ? _palette.onSurfaceDisabled
                              : _palette.onSurface,
                        ),
                      ),
                    ),
                    if (c.engineType == AloudEngineType.http)
                      Icon(Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
