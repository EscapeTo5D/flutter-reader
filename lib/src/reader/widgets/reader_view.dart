import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/battery_provider.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/models/reading_settings.dart';
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

/// 翻页动画速度(满页滑动的基础时长, 毫秒)。
///
/// 对齐原生 legado `ReadView.defaultAnimationSpeed = 300`(ReadView.kt:68),
/// 配合 `LinearInterpolator`(匀速)。原生时长公式 `duration = speed * abs(dx) / viewWidth`
/// (PageDelegate.kt:74), 故满页滑动恰好 300ms, 半页 150ms。
const int _pageAnimSpeedMs = 300;

/// 阅读器主视图。
///
/// 翻页动画(对齐原生 legado PageDelegate):
/// - 点击翻页: 程序化启动 300ms 全宽滑动动画。
/// - 拖拽: 跟手(实时偏移), 松手后按阈值补完或回弹(匀速 300ms)。
/// - 动画中触摸: 中断并提交当前方向(对齐原生 HorizontalPageDelegate.abortAnim)。
/// 动画类型由 `ReadingSettings.pageAnimMode` 决定; 本实现先支持 slide, 其余后续。
class ReaderView extends StatefulWidget {
  final ReadingController controller;

  const ReaderView({super.key, required this.controller});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView>
    with SingleTickerProviderStateMixin {
  Offset? _tapDownPosition;
  OverlayEntry? _selectionOverlay;

  /// 菜单层(遮罩 + ReadMenu)是否挂载。
  ///
  /// 比 controller.menuVisible "晚一拍"卸载: menuVisible 变 false 时, 菜单层
  /// 保持挂载 [_menuAnimDuration] 让退出动画播完, 再真正卸载。
  /// 这样退出动画才有 widget 可驱动(隐式动画 widget 一旦 unmount 动画即终止)。
  bool _menuMounted = false;
  Timer? _menuHideTimer;

  // --- 翻页动画状态 ---
  /// 翻页动画控制器。匀速(Curves.linear)对齐原生 LinearInterpolator。
  /// value 含义: 0=未翻(当前页在位), 1=翻完(目标页完全到位)。
  /// NEXT 方向 value 从 0→1; PREV 方向同样 0→1(偏移方向由 _animDir 决定)。
  late final AnimationController _pageAnim;
  Animation<double>? _pageAnimCurved;

  /// 当前翻页方向(none=静止)。拖拽和动画期间持有。
  _PageDirection _animDir = _PageDirection.none;

  /// 是否正在拖拽(跟手阶段)。true 时 _dragOffset 直接驱动页面偏移。
  bool _isDragging = false;

  /// 拖拽累计水平偏移(像素)。NEXT 为负(左滑), PREV 为正(右滑)。
  double _dragOffset = 0;

  /// 拖拽是否反向(松手时应回弹而非翻页)。对齐原生 isCancel。
  /// NEXT 时右移(偏移变正)即为 cancel; PREV 时左移(偏移变负)即为 cancel。
  bool _isCancel = false;

  /// 拖拽/动画期间的目标页缓存。仅在 _animDir != none 时有意义。
  /// PREV 方向用 _prevCache; NEXT 方向用 _nextCache。
  PeekInfo? _prevCache;
  PeekInfo? _nextCache;

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      // 上限设大, 实际时长由 _startPageAnim 按 dx 动态算(duration 构造参数)。
      duration: const Duration(milliseconds: _pageAnimSpeedMs),
    );
    _pageAnim.addStatusListener(_onPageAnimStatus);
    widget.controller.addListener(_onControllerUpdate);
    // 启动电量监听并跟随刷新(对齐原生 legado ACTION_BATTERY_CHANGED 实时刷页眉电量)。
    BatteryProvider.instance.start();
    BatteryProvider.instance.addListener(_onBatteryUpdate);
    _applySystemUI();
  }

  @override
  void dispose() {
    _menuHideTimer?.cancel();
    _selectionOverlay?.remove();
    _pageAnim.removeStatusListener(_onPageAnimStatus);
    _pageAnim.dispose();
    widget.controller.removeListener(_onControllerUpdate);
    BatteryProvider.instance.removeListener(_onBatteryUpdate);
    // 恢复显示系统栏(离开阅读页)。
    SystemUiController.setSystemBars(
      showStatusBar: true,
      showNavBar: true,
    );
    super.dispose();
  }

  /// 电量变化触发重绘(更新页眉电量图标/百分比)。ValueNotifier 自身去重,
  /// 相同 level 不会重复回调。
  void _onBatteryUpdate() {
    if (mounted) setState(() {});
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

    // 静止状态: 只渲染当前页。拖拽/动画期间(_animDir != none)渲染三页叠加,
    // 用 Transform.translate 按 SlidePageDelegate.onDraw 公式偏移定位。
    if (_animDir == _PageDirection.none) {
      return RepaintBoundary(child: _buildPage(pages[currentIndex], currentIndex));
    }
    return _buildPageStack();
  }

  /// 拖拽/动画期间的三页叠加视图(对齐原生 SlidePageDelegate.onDraw)。
  ///
  /// Slide 偏移公式(对齐 SlidePageDelegate.kt:34-56):
  /// - NEXT(向左翻): next 页从屏右滑入, cur 页向左滑出。
  ///   next.translateX = progress * width; cur.translateX = progress * width - width
  /// - PREV(向右翻): prev 页从屏左滑入, cur 页向右滑出。
  ///   prev.translateX = progress * width - width; cur.translateX = progress * width
  /// 其中 progress ∈ [0,1] = 当前翻页完成度(0=未动, 1=翻完)。
  Widget _buildPageStack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // progress: 拖拽时由 _dragOffset 推导, 动画时由 _pageAnim value 推导。
        final progress = _currentProgress(width);

        final curWidget = RepaintBoundary(
          child: _buildPage(
            widget.controller.pages[widget.controller.currentPageIndex],
            widget.controller.currentPageIndex,
          ),
        );

        if (_animDir == _PageDirection.next && _nextCache != null) {
          final nextWidget = RepaintBoundary(
            child: _buildPeekPage(_nextCache!),
          );
          return Stack(children: [
            // cur 向左滑出: 0 → -width
            Transform.translate(
              offset: Offset(-progress * width, 0),
              child: curWidget,
            ),
            // next 从屏右滑入: width → 0
            Transform.translate(
              offset: Offset(width - progress * width, 0),
              child: nextWidget,
            ),
          ]);
        }

        if (_animDir == _PageDirection.prev && _prevCache != null) {
          final prevWidget = RepaintBoundary(
            child: _buildPeekPage(_prevCache!),
          );
          return Stack(children: [
            // prev 从屏左滑入
            Transform.translate(
              offset: Offset(progress * width - width, 0),
              child: prevWidget,
            ),
            // cur 向右滑出
            Transform.translate(
              offset: Offset(progress * width, 0),
              child: curWidget,
            ),
          ]);
        }

        // 缓存缺失(边界): 退化为只显示当前页。
        return curWidget;
      },
    );
  }

  /// 当前翻页完成度 progress ∈ [0,1]。
  /// 拖拽阶段 = |offset| / width; 动画阶段 = _pageAnim.value。
  double _currentProgress(double width) {
    if (width <= 0) return 0;
    if (_isDragging) {
      return (_dragOffset.abs() / width).clamp(0.0, 1.0);
    }
    return _pageAnim.value.clamp(0.0, 1.0);
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
      batteryLevel: BatteryProvider.instance.value,
    );
  }

  /// 用预取信息构建缓存页(跨章时 totalPages/chapterIndex 取自 PeekInfo)。
  Widget _buildPeekPage(PeekInfo info) {
    final c = widget.controller;
    return pv.PageView(
      key: ValueKey('peek_${info.chapterIndex}_${info.pageIndex}'),
      page: info.page,
      settings: c.settings,
      pageIndex: info.pageIndex,
      // 跨章预取页无法可靠知道目标章总页数(需完整分页), 用 pageIndex+1 近似页脚显示,
      // 翻页提交后 controller 重排会用准确值。章内则用当前章 totalPages。
      totalPages: info.chapterIndex == c.currentChapterIndex
          ? c.totalPages
          : info.pageIndex + 1,
      chapterIndex: info.chapterIndex,
      chapterSize: c.totalChapters,
      chapterTitle: c.getChapter(info.chapterIndex)?.title,
      bookName: c.book?.title,
      searchQuery: c.searchQuery.isNotEmpty ? c.searchQuery : null,
      useSafeArea: true,
      showChrome: true,
      batteryLevel: BatteryProvider.instance.value,
    );
  }

  ReadingController get controller => widget.controller;

  // ===================== 翻页动画核心 =====================

  /// 动画状态监听: 动画完成时提交翻页(对齐 SlidePageDelegate.onAnimStop)。
  void _onPageAnimStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_animDir == _PageDirection.none) return;
    // commit 标志: 动画自然播完且非取消 → 提交; 取消(回弹) → 不提交。
    final shouldCommit = !_isCancel;
    final dir = _animDir;
    final target = dir == _PageDirection.next ? _nextCache : _prevCache;
    _resetAnimState();
    if (shouldCommit && target != null) {
      controller.commitTurn(target);
    } else {
      // 回弹或无目标: 仅重绘回到静止态。
      if (mounted) setState(() {});
    }
  }

  /// 重置动画状态到静止(none)。
  void _resetAnimState() {
    _animDir = _PageDirection.none;
    _isDragging = false;
    _isCancel = false;
    _dragOffset = 0;
    _prevCache = null;
    _nextCache = null;
    if (_pageAnimCurved != null) {
      _pageAnimCurved!.removeListener(_onAnimTick);
      _pageAnimCurved = null;
    }
    if (_pageAnim.isAnimating) _pageAnim.stop();
    _pageAnim.value = 0;
  }

  /// 启动翻页动画(匀速)。
  ///
  /// [from] 起始 progress, [to] 目标 progress(1=翻完, 0=回弹)。
  /// 时长按原生公式 `speed * |dx| / width`, |dx| = |to - from| * width,
  /// 即 `speed * |to - from|`。满页(0→1)恰为 _pageAnimSpeedMs。
  void _startPageAnim({required double from, required double to}) {
    final dxRatio = (to - from).abs();
    final durationMs = (_pageAnimSpeedMs * dxRatio).round();
    _pageAnimCurved = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _pageAnim,
        // 匀速对齐原生 LinearInterpolator。
        curve: Curves.linear,
      ),
    );
    _pageAnim.duration = Duration(milliseconds: durationMs < 1 ? 1 : durationMs);
    _pageAnimCurved!.addListener(_onAnimTick);
    _pageAnim.forward(from: 0);
  }

  /// 动画逐帧驱动重绘。
  void _onAnimTick() {
    if (mounted) setState(() {});
  }

  /// 程序化翻页(点击触发)。对齐原生 ReadView.kt:444-445 nextPageByAnim/prevPageByAnim。
  ///
  /// peek 目标页 → 设方向 → 启动 0→1 全宽动画 → onAnimStop 提交。
  void _turnByAnim(_PageDirection dir) {
    if (_animDir != _PageDirection.none) return; // 动画/拖拽进行中, 忽略
    if (dir == _PageDirection.next && !controller.canGoNext) return;
    if (dir == _PageDirection.prev && !controller.canGoPrevious) return;
    final target =
        dir == _PageDirection.next ? controller.peekNext() : controller.peekPrev();
    if (target == null) return;
    _animDir = dir;
    _isCancel = false;
    _isDragging = false;
    if (dir == _PageDirection.next) {
      _nextCache = target;
    } else {
      _prevCache = target;
    }
    setState(() {}); // 立即进入叠加态, 显示目标页
    _startPageAnim(from: 0, to: 1);
  }

  // ===================== 手势处理 =====================

  void _onTapDown(TapDownDetails details) {
    _tapDownPosition = details.localPosition;
  }

  void _onTapUp(TapUpDetails details) {
    if (_tapDownPosition == null) return;
    if (controller.menuVisible) return;

    final size = MediaQuery.of(context).size;
    final action = controller.getClickAction(details.localPosition, size);
    // 点击翻页改走动画路径(对齐原生 ReadView.kt:444-445)。
    if (action == ClickAction.nextPage) {
      _turnByAnim(_PageDirection.next);
    } else if (action == ClickAction.prevPage) {
      _turnByAnim(_PageDirection.prev);
    } else {
      controller.handleClickAction(action);
    }
    _tapDownPosition = null;
  }

  void _onDragStart(DragStartDetails details) {
    // 动画中触摸 → 中断并提交当前方向(对齐原生 abortAnim)。
    if (_animDir != _PageDirection.none && !_isDragging) {
      _abortAndCommit();
    }
    _isDragging = true;
    _dragOffset = 0;
    _isCancel = false;
    _animDir = _PageDirection.none;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    _dragOffset += details.delta.dx;

    // 首次确定方向(对齐原生 onScroll: 右滑>0=PREV, 左滑<0=NEXT)。
    if (_animDir == _PageDirection.none && _dragOffset.abs() > 8) {
      if (_dragOffset < 0 && controller.canGoNext) {
        _animDir = _PageDirection.next;
        _nextCache = controller.peekNext();
      } else if (_dragOffset > 0 && controller.canGoPrevious) {
        _animDir = _PageDirection.prev;
        _prevCache = controller.peekPrev();
      }
    }

    // 反向移动判定 cancel(对齐原生 isCancel)。
    if (_animDir == _PageDirection.next) {
      // NEXT 基准是左滑(负), 变正即反向。
      _isCancel = _dragOffset > 0;
    } else if (_animDir == _PageDirection.prev) {
      // PREV 基准是右滑(正), 变负即反向。
      _isCancel = _dragOffset < 0;
    }
    if (mounted) setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.25;
    _isDragging = false;

    if (_animDir == _PageDirection.none) {
      // 未确定方向(位移太小), 直接回静止。
      _resetAnimState();
      if (mounted) setState(() {});
      return;
    }

    final fromProgress = _dragOffset.abs() / width;
    final beyondThreshold = _dragOffset.abs() > threshold;
    // 翻页条件: 超阈值 且 非取消。否则回弹。
    final shouldCommit = beyondThreshold && !_isCancel;
    final toProgress = shouldCommit ? 1.0 : 0.0;
    _startPageAnim(from: fromProgress, to: toProgress);
  }

  /// 中断动画并按当前方向提交(对齐原生 HorizontalPageDelegate.abortAnim)。
  /// 原生: scroller 运行中且 !isCancel → fillPage 提交。
  void _abortAndCommit() {
    if (_pageAnim.isAnimating) _pageAnim.stop();
    if (_pageAnimCurved != null) {
      _pageAnimCurved!.removeListener(_onAnimTick);
    }
    final dir = _animDir;
    final target = dir == _PageDirection.next ? _nextCache : _prevCache;
    final wasCancel = _isCancel;
    _resetAnimState();
    if (!wasCancel && target != null) {
      controller.commitTurn(target);
    } else if (mounted) {
      setState(() {});
    }
  }
}

/// 拖拽方向(内部使用)。
enum _PageDirection { none, next, prev }
