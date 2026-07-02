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
/// 动画类型由 `ReadingSettings.pageAnimMode` 决定; slide/none 已实现, cover/simulation/scroll 后续。
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

  /// 邻接页缓存(常驻预热)。渲染层用统一 Stack[cur,prev,next] 让 peek 页
  /// 在静止态就常驻屏外完成首次排版+绘制, 拖拽/动画时 element 复用 → 零首帧 hitch。
  /// 对齐原生 legado HorizontalPageDelegate.setBitmap 提前把 prev/next 录成位图。
  PeekInfo? _prevCache;
  PeekInfo? _nextCache;

  /// 翻页动画代际号(每次 _resetAnimState 自增)。
  ///
  /// 守护「推迟提交」机制: 动画完成(completion)时不立即切换状态, 而是让 progress=1.0
  /// (目标页完全到位)那一帧先渲染一次, 下一帧再 commit。期间若用户又触发了新的翻页/
  /// 拖拽(从而调 _resetAnimState), 代际号变化会让挂起的 _deferredCommit 自动失效,
  /// 不会用旧状态误覆盖新动画。对齐原生 abortAnim「打断即接管」语义。
  int _animGen = 0;

  /// 预热去重标记: 仅当章/页变化才刷新 peek, 避免无谓 setState 抖动。
  int? _peekedChapter;
  int? _peekedPage;

  /// 转场动画是否已结束(Navigator push 进入阅读页的滑入动画)。
  ///
  /// 关键优化: 阅读页转场动画期间(~300ms), LayoutBuilder 已拿到真实尺寸并
  /// PostFrame 回调 updatePageSize → controller 触发 ~170ms 同步排版。若这 170ms
  /// 砸在转场动画进行中的帧上, 动画会掉帧(肉眼卡顿)。
  /// 故首次布局先**不排版**(返回空页), 等 route.animation completed 后再排版:
  /// 转场丝滑, 排版延后到「页面已停稳」之后, 用户感知是「页面滑进来后内容淡入」。
  bool _routeReady = false;
  Animation<double>? _routeAnimation;

  /// 本路由是否为 Navigator 当前路由(无下一页覆盖)。
  ///
  /// 当目录页/菜单等 push 到本路由之上时, 键盘弹起会持续改变窗口 viewInsets
  /// → LayoutBuilder constraints 多帧变化 → updatePageSize → 重排整章(~170ms/
  /// 次), 把主线程占满, 表现为"打开搜索框后不停卡"。
  ///
  /// 守卫: 仅当本路由是 current route 时才响应尺寸变化排版。push 出去的页面
  /// (目录/书签/设置弹窗)由其自身负责, reader 此刻不可见, 无需重排。
  bool _isCurrentRoute = true;
  Animation<double>? _secondaryAnimation;

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
    // 初始预热邻接页。这里可能章节数据还没异步加载完(pages 为空)→ peek 返回 null,
    // 后续 _onControllerUpdate(章/页变化)会重新调 _refreshPeekCaches 补上。
    _refreshPeekCaches();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 挂一次 route 转场动画监听: 动画结束后解除「延迟排版」。
    // 只挂一次(_routeAnimation 非空表示已挂)。
    if (_routeAnimation == null) {
      final route = ModalRoute.of(context);
      final anim = route?.animation;
      if (anim != null) {
        _routeAnimation = anim;
        if (anim.isCompleted) {
          _routeReady = true;
        } else {
          anim.addStatusListener(_onRouteAnimation);
        }
      } else {
        // 非 Navigator 路由场景(测试/无 route): 直接就绪。
        _routeReady = true;
      }
    }
    // 监听 secondaryAnimation: 当 push 出新路由(目录/菜单/弹窗)覆盖本路由时,
    // secondaryAnimation 会从 0 推向 1。借此标记本路由是否 current route,
    // 用于在「被覆盖」期间屏蔽键盘 resize 引发的无谓重排(详见 _isCurrentRoute)。
    if (_secondaryAnimation == null) {
      final route = ModalRoute.of(context);
      final secondary = route?.secondaryAnimation;
      if (secondary != null) {
        _secondaryAnimation = secondary;
        _isCurrentRoute = secondary.value <= 0;
        secondary.addStatusListener(_onSecondaryAnimation);
        secondary.addListener(_onSecondaryFrame);
      }
    }
  }

  void _onSecondaryAnimation(AnimationStatus status) {
    // status 反映本路由被覆盖与否:
    //   completed = secondaryAnimation 推到 1(本路由被覆盖)
    //   dismissed = secondaryAnimation 回到 0(本路由恢复 current)
    final wasCurrent = _isCurrentRoute;
    _isCurrentRoute = status == AnimationStatus.dismissed ||
        (status == AnimationStatus.forward && _secondaryAnimation!.value <= 0);
    // 从被覆盖 → current 时, 触发一次重排让尺寸(可能已变)生效。
    if (!wasCurrent && _isCurrentRoute && mounted) {
      setState(() {});
    }
  }

  void _onSecondaryFrame() {
    // 反向(pop 覆盖页)动画进行中, value 一路从 1 降到 0; 在降到 0 的瞬间翻转标志。
    final v = _secondaryAnimation?.value ?? 0;
    final nowCurrent = v <= 0;
    if (nowCurrent != _isCurrentRoute) {
      _isCurrentRoute = nowCurrent;
    }
  }

  void _onRouteAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeReady = true;
      _routeAnimation?.removeStatusListener(_onRouteAnimation);
      _routeAnimation = null;
      // 转场结束, 触发一次重绘让 LayoutBuilder 走「就绪」分支排版。
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _menuHideTimer?.cancel();
    _selectionOverlay?.remove();
    _pageAnim.removeStatusListener(_onPageAnimStatus);
    _pageAnim.dispose();
    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimation);
    _secondaryAnimation?.removeListener(_onSecondaryFrame);
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
    // 章/页可能因翻页提交而变化 → 刷新预热缓存。
    _refreshPeekCaches();
    _applySystemUI();
    // 后台预计算相邻章分页: 用户在章内逐页阅读时, 下一/上一章已算好入缓存,
    // 翻到末页时 peekNext 命中缓存(O(1))。放到 PostFrame 避免阻塞当前提交帧。
    // 重排开销(~100ms)摊到「进入新章后静止阅读」时刻, 用户无感; 快速连点跨章
    // 时 peek 直接命中缓存, 不再卡顿。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.prefetchAdjacentChapters();
    });
  }

  /// 刷新邻接页缓存(预热)。仅在章/页变化时真正调 peekNext/peekPrev,
  /// 否则用缓存标记去重, 避免每次 setState 都重排(章内 peek 是 O(1), 但跨章
  /// peek 会触发目标章分页, 重复调用浪费)。
  ///
  /// ⚠️ 若 peek 返回 null(数据未就绪, 如章未加载/末尾), **不更新**去重标记,
  /// 这样后续章/页就绪后还能重试; 否则 initState 里 pages 为空时会把标记锁死在 0/0,
  /// 之后真正的章/页就绪也被去重跳过 → peek 永远 null → 翻不了页。
  void _refreshPeekCaches() {
    final c = widget.controller;
    if (c.currentChapterIndex == _peekedChapter &&
        c.currentPageIndex == _peekedPage) {
      return;
    }
    final next = c.peekNext();
    final prev = c.peekPrev();
    _nextCache = next;
    _prevCache = prev;
    // 仅当至少一个方向成功取到页时才更新标记; 两边都 null 说明数据未就绪,
    // 下次再重试。
    if (next != null || prev != null) {
      _peekedChapter = c.currentChapterIndex;
      _peekedPage = c.currentPageIndex;
    }
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
    // 切断键盘 viewInsets 对子树的影响: 键盘弹/收时 viewInsets.bottom 在多帧里变化,
    // 会逐帧让子树(MediaQuery 依赖者, 如 SafeArea / page_view 的 Padding) rebuild +
    // relayout, 持续 ~10 帧卡顿。正文被键盘/搜索框遮挡时本就无需适配其高度, 故移除
    // viewInsets 让子树始终看到「无键盘」的稳定布局环境。对齐 legado「目录/搜索是独立
    // Activity, 底层阅读 View 不 resize」; Flutter 同 Navigator 栈无 Activity 隔离,
    // 用 MediaQuery.removeViewInsets 在 widget 层复刻等效隔离。
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: LayoutBuilder(
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
          debugPrint(
            '[PERF] updatePageSize called: ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)} routeReady=$_routeReady',
          );
          // 转场动画期间不排版(~170ms 同步排版会砸掉转场动画的帧)。
          // _routeReady 由 didChangeDependencies 的 route.animation completed 回调置 true,
          // 届时 setState 触发重建, 这里才真正 updatePageSize → 排版。
          //
          // 同时屏蔽「本路由被覆盖」期间(目录页/菜单等 push 到上层)的排版: 此时 reader
          // 不可见, 但键盘弹起会让 viewInsets 多帧变化 → constraints 变 → 反复触发重排
          // 卡死主线程。仅当本路由是 current route 时才响应。
          //
          // 键盘收起/路由 pop 时的尺寸瞬变由 controller 侧 updatePageSize 的防抖 +
          // 反弹取消处理(对齐 legado ChapterProvider.upViewSize: 仅高度变延迟 300ms,
          // 期间尺寸反弹回原值则取消重排)。此处不重复判断。
          if (_routeReady && _isCurrentRoute) {
            widget.controller.updatePageSize(size);
          }
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
      ),
    );
  }

  Widget _buildPageContent() {
    final controller = widget.controller;
    final pages = controller.pages;
    final currentIndex = controller.currentPageIndex;

    if (pages.isEmpty) {
      // pages 为空时的占位渲染:
      // - 章节加载/排版中(controller.chapterLoading)→ 显示与正文背景一致的空白
      //   占位(不闪现未排版原文)。对齐 legado 排版未完成时不显示正文。
      // - 已就绪但章节无内容 → 轻提示。
      //
      // 旧实现这里直接 Text(currentChapter.content) 会闪现整章未排版原文, 是卡顿
      // 的可见症状之一(详见 AGENTS.md 根因)。改为占位后, 排版期间 UI 干净。
      final bg = controller.settings.backgroundColor;
      if (controller.chapterLoading) {
        return ColoredBox(
          color: bg,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  controller.settings.textColor.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        );
      }
      return ColoredBox(
        color: bg,
        child: Center(
          child: Text(
            '本章暂无内容',
            style: TextStyle(
              fontSize: controller.settings.fontSize,
              color: controller.settings.textColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    // 统一三页 Stack[cur, prev, next]: widget 树结构在静止/拖拽/动画三态下完全相同,
    // 仅 Transform offset 变化 → peek 页在静止态的空闲帧就完成首次排版+绘制(屏外),
    // 拖拽/动画时 element 复用、layer 缓存命中 → 零首帧 hitch。
    // 对齐原生 legado HorizontalPageDelegate.setBitmap 提前录好 prev/next 位图。
    //
    // 偏移矩阵(progress = 翻页完成度, none 态视为 0):
    // | 状态      | cur.x        | next.x           | prev.x           |
    // |----------|--------------|------------------|------------------|
    // | none     | 0            | +width (屏外)    | -width (屏外)    |
    // | NEXT(p)  | -p·w         | (1-p)·w          | -width (屏外)    |
    // | PREV(p)  | +p·w         | +width (屏外)    | (p-1)·w          |
    // none→NEXT 在 p=0 时各 offset 都等于静止态值, 过渡完全连续。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = _currentProgress(width);
        final isNext = _animDir == _PageDirection.next;
        final isPrev = _animDir == _PageDirection.prev;

        final curWidget = RepaintBoundary(
          child: _buildPage(pages[currentIndex], currentIndex),
        );
        // 屏外页用 IgnorePointer 避免接收不到手势(都在屏外, 本就不会被点, 但保险)。
        final nextWidget = _nextCache == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: RepaintBoundary(child: _buildPeekPage(_nextCache!)));
        final prevWidget = _prevCache == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: RepaintBoundary(child: _buildPeekPage(_prevCache!)));

        // cur 偏移: NEXT 向左(-p·w), PREV 向右(+p·w), none 留在原位。
        final curOffsetX = isNext ? -progress * width
            : isPrev ? progress * width
            : 0.0;
        // next 偏移: NEXT 从屏右滑入((1-p)·w → 0); 否则屏外(+width)。
        final nextOffsetX = isNext ? width - progress * width : width;
        // prev 偏移: PREV 从屏左滑入((p-1)·w → 0); 否则屏外(-width)。
        final prevOffsetX = isPrev ? progress * width - width : -width;

        // 层级 [prev, cur, next]: NEXT 时 next 在最上层覆盖 cur; PREV 时 prev 在 cur 下,
        // 但 PREV 过程中 cur 右移露出 prev, prev 不被覆盖, 视觉正确。
        return Stack(children: [
          Transform.translate(offset: Offset(prevOffsetX, 0), child: prevWidget),
          Transform.translate(offset: Offset(curOffsetX, 0), child: curWidget),
          Transform.translate(offset: Offset(nextOffsetX, 0), child: nextWidget),
        ]);
      },
    );
  }

  /// 当前翻页完成度 progress ∈ [0,1]。
  /// 拖拽阶段 = |offset| / width; 动画阶段 = _pageAnimCurved.value。
  double _currentProgress(double width) {
    if (width <= 0) return 0;
    if (_isDragging) {
      return (_dragOffset.abs() / width).clamp(0.0, 1.0);
    }
    // ⚠️ 必须读 _pageAnimCurved(由 Tween(from,to) 映射的真实进度),
    // 而非 _pageAnim.value(永远是 0→1 的原始时钟)。
    // 拖拽补完路径 from≠0(如 from=0.8,to=1.0): 若误读原始时钟, 松手第一帧
    // progress 会从 0.8 跳到 0(控制器被 forward(from:0) 置 0)再滑到 1,
    // 视觉上「先弹回再重滑」, 即松手那个多余动画。
    return (_pageAnimCurved?.value ?? _pageAnim.value).clamp(0.0, 1.0);
  }

  Widget _buildPage(TextPage page, int index) {
    return pv.PageView(
      // key 与 _buildPeekPage 一致(同为 page_C_I): 动画提交后 currentPageIndex 变到目标页,
      // 两者 key 完全相同 → Flutter 复用同一 element, 避免「松手那一帧重建」闪烁。
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
      // key 必须与 _buildPage 一致(page_C_I, 不带 peek_ 前缀):
      // 这样 commitTurn 后 currentPageIndex 变到本页, Flutter 视为同一 element 复用,
      // 不再卸载重建 → 消除松手时的「页面重建」闪烁。
      key: ValueKey('page_${info.chapterIndex}_${info.pageIndex}'),
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
  ///
  /// ⚠️ 完成帧时序陷阱: AnimationController 在一帧的 transient 阶段把 value 推到 1.0,
  /// 紧接着触发 status=completed。若在这里立即 _resetAnimState + commitTurn, 两个
  /// setState(completion 回调里的 tick + 这里)会被 Flutter 合并成同一次 rebuild,
  /// 于是 progress=1.0 那一帧根本没机会渲染 → 目标页从 ~0.97w 瞬跳到 0, 看着像
  /// 「末尾卡顿一下、整页左偏/右偏」(NEXT 左偏、PREV 右偏)。
  ///
  /// 修复: completion 时**不**重置状态, 只把 progress 钉在 1.0 等当前帧画完,
  /// 在 addPostFrameCallback 里再做状态切换 + commit。代际号 _animGen 守护:
  /// 其间若新翻页/拖拽触发了 _resetAnimState, _animGen 自增 → 挂起的回调失效。
  void _onPageAnimStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_animDir == _PageDirection.none) return;
    // 记下本次提交参数, 推迟到下一帧执行。
    final shouldCommit = !_isCancel;
    final dir = _animDir;
    final target = dir == _PageDirection.next ? _nextCache : _prevCache;
    final gen = _animGen;
    WidgetsBinding.instance.addPostFrameCallback((_) => _deferredCommit(
          gen: gen,
          shouldCommit: shouldCommit,
          dir: dir,
          target: target,
        ));
  }

  /// 下一帧执行真正的状态切换(让 completion 帧 progress=1.0 先渲染)。
  ///
  /// 守护: 若 [gen] 与当前 _animGen 不符, 说明本帧到下一帧之间已发生了新的翻页/
  /// 拖拽(它会 _resetAnimState 自增代际号), 本次提交作废, 不覆盖新动画。
  void _deferredCommit({
    required int gen,
    required bool shouldCommit,
    required _PageDirection dir,
    required PeekInfo? target,
  }) {
    if (gen != _animGen) return; // 已被新动画接管
    if (_animDir != dir) return; // 方向已被改变(防御)
    _resetAnimState();
    if (shouldCommit && target != null) {
      controller.commitTurn(target);
    } else {
      // 回弹或无目标: 仅重绘回到静止态。
      if (mounted) setState(() {});
    }
  }

  /// 重置动画状态到静止(none)。
  ///
  /// ⚠️ 不清空 _nextCache/_prevCache: 新架构下它们是常驻预热缓存,
  /// 由 _refreshPeekCaches 统一管理(章/页变化时刷新)。
  /// 清空会导致预热失效 → 拖拽首帧 hitch 回归 / 翻页失败。
  void _resetAnimState() {
    _animDir = _PageDirection.none;
    _isDragging = false;
    _isCancel = false;
    _dragOffset = 0;
    if (_pageAnimCurved != null) {
      _pageAnimCurved!.removeListener(_onAnimTick);
      _pageAnimCurved = null;
    }
    if (_pageAnim.isAnimating) _pageAnim.stop();
    _pageAnim.value = 0;
    // 自增代际号: 使任何挂起的 _deferredCommit 失效, 避免旧动画的延迟提交
    // 误覆盖刚启动的新翻页/拖拽状态。
    _animGen++;
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

  /// 程序化翻页(点击触发)。对齐原生 ReadView.kt:444 nextPageByAnim/prevPageByAnim
  /// + HorizontalPageDelegate.abortAnim。
  ///
  /// 关键(原生丝滑连点的来源): 若动画进行中再次点击, 不是忽略, 而是
  /// abortAnim —— 中断当前动画 + 若非取消则 fillPage 提交这次翻页(跳过动画
  /// 尾巴直接到位), 然后从新的当前页启动下一次动画。这样连点每一次都立即响应,
  /// 不被 300ms 动画尾巴阻塞。
  void _turnByAnim(_PageDirection dir) {
    final c = controller;
    // 动画进行中再次点击: 中断 + 提交当前翻页, 然后从新当前页继续(对齐 abortAnim)。
    if (_animDir != _PageDirection.none) {
      _abortAndCommit();
    }
    if (dir == _PageDirection.next && !c.canGoNext) return;
    if (dir == _PageDirection.prev && !c.canGoPrevious) return;
    // 邻接页已由 _refreshPeekCaches 预热常驻, 直接取用; 若预热失效(如数据异步
    // 就绪晚于 initState)则即时 peek 兜底, 保证翻页不会因预热 bug 彻底失败。
    var target = dir == _PageDirection.next ? _nextCache : _prevCache;
    if (target == null) {
      target = dir == _PageDirection.next
          ? controller.peekNext()
          : controller.peekPrev();
      if (dir == _PageDirection.next) {
        _nextCache = target;
      } else {
        _prevCache = target;
      }
    }
    if (target == null) return;
    // 无动画模式: 直接提交, 不进入叠加态也不启动动画。
    if (controller.settings.pageAnimMode == PageAnimMode.none) {
      controller.commitTurn(target);
      return;
    }
    _animDir = dir;
    _isCancel = false;
    _isDragging = false;
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
    // 邻接页已预热常驻, 这里只设方向, 不再单独 peek(消除拖拽首帧 hitch)。
    if (_animDir == _PageDirection.none && _dragOffset.abs() > 8) {
      if (_dragOffset < 0 && controller.canGoNext) {
        _animDir = _PageDirection.next;
      } else if (_dragOffset > 0 && controller.canGoPrevious) {
        _animDir = _PageDirection.prev;
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

    // 无动画模式: 拖拽过阈值直接提交, 不播滑入/回弹动画
    // (对齐原生 NoAnimPageDelegate, 拖拽与点击共用同一 delegate)。
    if (controller.settings.pageAnimMode == PageAnimMode.none) {
      final target = _animDir == _PageDirection.next ? _nextCache : _prevCache;
      _resetAnimState();
      if (shouldCommit && target != null) {
        controller.commitTurn(target);
      } else if (mounted) {
        setState(() {});
      }
      return;
    }

    final toProgress = shouldCommit ? 1.0 : 0.0;
    // 边界短路: 已拉满(或已回弹到原位)时直接提交/回弹, 不启动零长度动画。
    // 否则 _startPageAnim 会从 from=1→to=1(forward from: 0 让 value 跳 0→1),
    // 松手时多出一个多余的动画/抖动一帧(对齐原生 Scroller 距离为 0 时立即 finish 的行为)。
    if ((fromProgress - toProgress).abs() < 0.001) {
      final target = _animDir == _PageDirection.next ? _nextCache : _prevCache;
      _resetAnimState();
      if (shouldCommit && target != null) {
        controller.commitTurn(target);
      } else if (mounted) {
        setState(() {});
      }
      return;
    }
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
