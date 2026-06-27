import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/system_ui_controller.dart';
import '../entities/text_page.dart';
import 'page_view.dart' as pv;
import 'read_menu.dart';
import 'search_menu.dart';

/// 菜单显隐动画时长。
///
/// 对齐原生 legado 顶栏/底栏退出动画 200ms(anim_readbook_top_out/bottom_out)。
/// 取 220ms 略大于 200, 确保覆盖 SystemChrome 经 platform channel 隐藏状态栏的
/// 固有延迟: 状态栏在动画开始时即开始隐藏, 动画结束 ≈ 状态栏隐藏完成, 视觉同步。
const Duration _menuAnimDuration = Duration(milliseconds: 220);

/// 阅读器主视图。
///
/// 当前实现为「无动画翻页」:
/// - 点击: 按九宫格区域触发翻页/菜单等动作。
/// - 拖拽: 横向拖拽超过阈值后, 松手即切换上一页/下一页(无过渡动画)。
class ReaderView extends StatefulWidget {
  final ReadingController controller;

  const ReaderView({super.key, required this.controller});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  double _dragOffset = 0;
  _PageDirection _direction = _PageDirection.none;
  Offset? _tapDownPosition;
  OverlayEntry? _selectionOverlay;

  /// 菜单层(遮罩 + ReadMenu)是否挂载。
  ///
  /// 比 controller.menuVisible "晚一拍"卸载: menuVisible 变 false 时, 菜单层
  /// 保持挂载 [_menuAnimDuration] 让退出动画播完, 再真正卸载。
  /// 这样退出动画才有 widget 可驱动(隐式动画 widget 一旦 unmount 动画即终止)。
  bool _menuMounted = false;
  Timer? _menuHideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _applySystemUI();
  }

  @override
  void dispose() {
    _menuHideTimer?.cancel();
    _selectionOverlay?.remove();
    widget.controller.removeListener(_onControllerUpdate);
    // 恢复显示系统栏(离开阅读页)。
    SystemUiController.setSystemBars(
      showStatusBar: true,
      showNavBar: true,
    );
    super.dispose();
  }

  void _onControllerUpdate() {
    final nowVisible = widget.controller.menuVisible;
    if (nowVisible) {
      // 显示菜单: 立即挂载, 取消任何待执行的卸载定时器。
      _menuHideTimer?.cancel();
      _menuHideTimer = null;
      _menuMounted = true;
    } else if (_menuMounted) {
      // 隐藏菜单: 保持挂载, 延迟卸载让退出动画播完。
      _menuHideTimer?.cancel();
      _menuHideTimer = Timer(_menuAnimDuration, () {
        _menuHideTimer = null;
        if (mounted) setState(() => _menuMounted = false);
      });
    }
    setState(() {});
    _applySystemUI();
  }

  void _applySystemUI() {
    final settings = widget.controller.settings;
    final menuVisible = widget.controller.menuVisible;
    // 菜单可见时显示系统栏(方便操作); 菜单隐藏时按配置决定。
    // 收敛为两个布尔值交由 SystemUiController 处理(优先原生 channel 即时隐藏,
    // 绕过 Android 15 下 SystemChrome.manual 的系统渐隐延迟)。
    final showStatusBar = menuVisible || !settings.hideStatusBar;
    final showNavBar = menuVisible || !settings.hideNavigationBar;
    SystemUiController.setSystemBars(
      showStatusBar: showStatusBar,
      showNavBar: showNavBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = widget.controller.settings;
        // 页眉/页脚显隐条件必须与 page_view.build() 完全一致, 否则预算高度
        // (喂给排版引擎的可用高度) 与实际渲染占用会错位, 导致正文与页脚重叠/留白。
        final showHeader =
            settings.hideStatusBar && !settings.headerConfig.hidden;
        final showFooter = !settings.footerConfig.hidden;
        // ⚠️ 这里用 viewPadding(物理固定值, 不随系统栏显隐变化), 不能用 padding
        // (padding 会随翻菜单时 _applySystemUI 显隐系统栏而变 → 重排延迟, 见 9565e06)。
        // viewPadding 始终报告状态栏/导航栏的物理高度。
        //
        // ⚠️ 必须把系统栏高度计入 nonContentHeight! page_view 内部 SafeArea
        // (top: !hideStatusBar, bottom: !hideNavigationBar) 会从内容区扣除系统栏高度,
        // 若排版引擎不扣同样的高度, 引擎会多排一行, 末行溢出被 ClipRect 裁 → 露头。
        // (这是 9565e06 删 systemPadding 引入的回归, 原生 legado 用独立占位 View
        // vw_status_bar 处理, 高度由 hideStatusBar 决定。)
        final viewPadding = MediaQuery.of(context).viewPadding;
        final statusBarH = showHeader ? 0.0 : viewPadding.top;
        final navBarH = settings.hideNavigationBar ? 0.0 : viewPadding.bottom;
        // footer 外层 Padding(top:2 + bottom:4) 来自 page_view._buildFooter
        final footerPadding = showFooter ? 6.0 : 0.0;
        final nonContentHeight = statusBarH +
            navBarH +
            (showHeader ? settings.padding.headerHeight : 0) +
            (showHeader && settings.showHeaderDivider ? 0.5 : 0) +
            (showFooter && settings.showFooterDivider ? 0.5 : 0) +
            (showFooter ? settings.padding.footerHeight + footerPadding : 0);
        final size = Size(
          constraints.maxWidth,
          (constraints.maxHeight - nonContentHeight)
              .clamp(0.0, constraints.maxHeight),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.updatePageSize(size);
        });

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onPanStart: _onDragStart,
          onPanUpdate: _onDragUpdate,
          onPanEnd: _onDragEnd,
          child: Stack(
            children: [
              _buildPageContent(),
              // 菜单层挂载由本地 _menuMounted 控制(晚于 menuVisible 卸载),
              // 显隐由 menuVisible 驱动 AnimatedOpacity / ReadMenu 内部滑入滑出,
              // 让退出动画覆盖状态栏隐藏延迟, 视觉同步。
              if (_menuMounted) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => widget.controller.hideMenu(),
                    child: AnimatedOpacity(
                      opacity: widget.controller.menuVisible ? 1.0 : 0.0,
                      duration: _menuAnimDuration,
                      curve: Curves.easeOut,
                      child: Container(color: Colors.black12),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ReadMenu(
                    controller: widget.controller,
                    visible: widget.controller.menuVisible,
                  ),
                ),
              ],
              if (widget.controller.searchVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SearchMenu(controller: widget.controller),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageContent() {
    final controller = widget.controller;
    final pages = controller.pages;
    final currentIndex = controller.currentPageIndex;

    if (pages.isEmpty) {
      return Center(
        child: Text(
          controller.currentChapter?.content ?? '',
          style: TextStyle(
            fontSize: controller.settings.fontSize,
            color: controller.settings.textColor,
          ),
        ),
      );
    }

    return _buildPage(pages[currentIndex], currentIndex);
  }

  Widget _buildPage(TextPage page, int index) {
    return pv.PageView(
      key: ValueKey('page_${controller.currentChapterIndex}_$index'),
      page: page,
      settings: widget.controller.settings,
      pageIndex: index,
      totalPages: widget.controller.totalPages,
      chapterIndex: controller.currentChapterIndex,
      chapterSize: controller.totalChapters,
      chapterTitle: widget.controller.currentChapter?.title,
      bookName: widget.controller.book?.title,
      searchQuery: widget.controller.searchQuery.isNotEmpty
          ? widget.controller.searchQuery
          : null,
      useSafeArea: true,
      showChrome: true,
    );
  }

  ReadingController get controller => widget.controller;

  void _onTapDown(TapDownDetails details) {
    _tapDownPosition = details.localPosition;
  }

  void _onTapUp(TapUpDetails details) {
    if (_tapDownPosition == null) return;
    if (controller.menuVisible) return;

    final size = MediaQuery.of(context).size;
    final action = controller.getClickAction(details.localPosition, size);
    controller.handleClickAction(action);
    _tapDownPosition = null;
  }

  void _onDragStart(DragStartDetails details) {
    _dragOffset = 0;
    _direction = _PageDirection.none;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragOffset += details.delta.dx;
    if (_dragOffset < 0) {
      _direction = _PageDirection.next;
    } else if (_dragOffset > 0) {
      _direction = _PageDirection.prev;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final threshold = MediaQuery.of(context).size.width * 0.25;
    if (_dragOffset.abs() > threshold) {
      if (_direction == _PageDirection.next && controller.canGoNext) {
        controller.nextPage();
      } else if (_direction == _PageDirection.prev &&
          controller.canGoPrevious) {
        controller.previousPage();
      }
    }
    _dragOffset = 0;
    _direction = _PageDirection.none;
  }
}

/// 拖拽方向(内部使用, 取代已移除的 PageDirection)。
enum _PageDirection { none, next, prev }
