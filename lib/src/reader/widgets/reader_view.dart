import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;
import '../../core/battery_provider.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/models/reading_settings.dart';
import '../../core/system_ui_controller.dart';
import '../entities/text_page.dart';
import '../page_animations/cover_layout.dart';
import '../page_animations/simulation_geometry.dart';
import '../page_animations/simulation_painter.dart';
import '../page_animations/scroll_mode_handler.dart';
import 'page_view.dart' as pv;
import 'tip_layout.dart';
import 'read_menu.dart';
import 'read_aloud_dialog.dart';
import 'legado_icons.dart';
import '../../aloud/aloud_controller.dart';

part 'reader_view_scroll.dart';
part 'reader_view_simulation.dart';

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
/// 动画类型由 `ReadingSettings.pageAnimMode` 决定:
/// - slide/none/simulation 已实现(simulation 为贝塞尔仿真翻页, 见
///   `page_animations/simulation_painter.dart`)。
/// - scroll 已实现(单一 pageOffset + 边界翻章修正, 见
///   `page_animations/scroll_mode_handler.dart`)。
/// - cover 已实现(目标页静止, 当前页/上一页像幕布抽走的覆盖翻页, 见
///   `page_animations/cover_layout.dart`)。
class ReaderView extends StatefulWidget {
  final ReadingController controller;

  /// 朗读控制器(可选)。非 null 时, 朗读进度变化会驱动本视图重绘当前段高亮。
  ///
  /// 用法: 宿主创建 [AloudController] 后传入。朗读高亮由 [PageView._markAloud]
  /// 在构建时按当前 [AloudCursor] 标记对应字符列, 本视图监听 aloudController
  /// 的变化触发 setState(复用现有 `_onControllerUpdate` 模式)。
  final AloudController? aloudController;

  const ReaderView({super.key, required this.controller, this.aloudController});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView>
    with TickerProviderStateMixin, _ScrollMixin, _SimulationMixin {
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
  @override
  late final AnimationController _pageAnim;
  @override
  Animation<double>? _pageAnimCurved;

  /// 当前翻页方向(none=静止)。拖拽和动画期间持有。
  @override
  _PageDirection _animDir = _PageDirection.none;

  /// 是否正在拖拽(跟手阶段)。true 时 _dragOffset 直接驱动页面偏移。
  bool _isDragging = false;

  /// 拖拽累计水平偏移(像素)。NEXT 为负(左滑), PREV 为正(右滑)。
  double _dragOffset = 0;

  /// 拖拽是否反向(松手时应回弹而非翻页)。对齐原生 isCancel。
  /// **逐帧判定**(对齐原生 HorizontalPageDelegate.onScroll:105 `isCancel = (NEXT
  /// 时 sumX > lastX) 或 (PREV 时 sumX < lastX)`): 用本帧 delta.dx 符号, 而非累积
  /// 位移符号。这样「拖到一半反悔、回缩松开」会回弹(尊重最后意图)。
  /// NEXT 时本帧右移(delta>0)即 cancel; PREV 时本帧左移(delta<0)即 cancel。
  @override
  bool _isCancel = false;

  // --- 仿真翻页状态(simulation 模式专用) ---
  // 仿真字段(_simTouch/_simCorner/_simCur 等 12 个)与方法(_initSimForDrag/
  // _captureSimBitmaps/_startSimAnim/_abortAndCommit 等 7 个)已抽到
  // _SimulationMixin (reader_view_simulation.dart)。build 里的 RepaintBoundary
  // 截图层与 SimulationPainter 覆盖层仍留本类(pageStack 核心)。

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
  @override
  int _animGen = 0;

  /// 预热去重标记: 仅当章/页变化才刷新 peek, 避免无谓 setState 抖动。
  int? _peekedChapter;
  int? _peekedPage;

  // --- 滚动翻页状态(scroll 模式专用) ---
  // _scrollHandler 字段与方法已抽到 _ScrollMixin (reader_view_scroll.dart)。

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

  /// 朗读引擎是否处于运行态(playing / paused)。
  /// 对齐原生 `BaseReadAloudService.isRun`(play/pause 都为 true, stopped/idle 为 false)。
  /// 用于点击「菜单区」时分支: 运行中直接弹朗读控制面板而非主菜单。
  bool get _isAloudRunning {
    final a = widget.aloudController;
    return a != null && (a.isPlaying || a.isPaused);
  }

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
    // 朗读高亮: 监听 aloudController 变化触发重绘(复用 _onControllerUpdate 模式)。
    widget.aloudController?.addListener(_onAloudUpdate);
    // 启动电量监听并跟随刷新(对齐原生 legado ACTION_BATTERY_CHANGED 实时刷页眉电量)。
    BatteryProvider.instance.start();
    BatteryProvider.instance.addListener(_onBatteryUpdate);
    _applySystemUI();
    // 初始预热邻接页。这里可能章节数据还没异步加载完(pages 为空)→ peek 返回 null,
    // 后续 _onControllerUpdate(章/页变化)会重新调 _refreshPeekCaches 补上。
    _refreshPeekCaches();
    _ensureScrollHandler();
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
    // scroll handler 常驻预热(不再随模式切换 dispose), 仅在 ReaderView 整体 dispose 时销毁。
    _scrollHandler?.dispose();
    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimation);
    _secondaryAnimation?.removeListener(_onSecondaryFrame);
    widget.controller.removeListener(_onControllerUpdate);
    widget.aloudController?.removeListener(_onAloudUpdate);
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

  /// 朗读进度/状态变化触发重绘(更新当前段朗读高亮)。
  /// 复用 _onBatteryUpdate 模式: 简单 setState 让 _buildPage 重跑,
  /// PageView 内部的 _markAloud 会按最新 aloudController.cursor 重标。
  void _onAloudUpdate() {
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
    // 翻页模式可能切换(设置弹窗); handler 常驻预热(不重建/销毁), 这里仅确保存在。
    _ensureScrollHandler();
    // controller 的章/页变化(loadBook/restoreProgress/翻页提交)同步给 handler。
    _scrollHandler?.syncFromController();
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
    // 状态栏图标明/暗跟随夜晚态(对齐原生 darkStatusIconNight=false 让图标变亮)。
    // Android only: iOS 状态栏不受此控制。仅菜单可见(状态栏一定可见)或
    // hideStatusBar=false 时有意义; 状态栏隐藏时设置无效但不报错。
    final iconBrightness =
        settings.isNightTheme ? Brightness.light : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: iconBrightness == Brightness.light
          ? Brightness.dark
          : Brightness.light, // iOS 反向
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
    ));
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
        // header/footer 总高 = 各向外边距(headerTop/Bottom + footerTop/Bottom)
        // + 内容行高。header 行高仍用固定 headerHeight(待后续同样迁移到自适应);
        // footer 行高用 measureChromeContentHeight 按当前 tip 配置实时测量,
        // 与 page_view._buildFooter 的 Row 自适应高度逐项一致(详见 tip_layout.dart)。
        final headerOuter =
            settings.padding.headerTop + settings.padding.headerBottom;
        final footerOuter =
            settings.padding.footerTop + settings.padding.footerBottom;
        final footerContentH = showFooter
            ? measureChromeContentHeight(settings, settings.footerConfig)
            : 0.0;
        final nonContentHeight = statusBarH +
            navBarH +
            (showHeader ? settings.padding.headerHeight + headerOuter : 0) +
            (showHeader && settings.showHeaderDivider ? 0.5 : 0) +
            (showFooter && settings.showFooterDivider ? 0.5 : 0) +
            (showFooter ? footerContentH + footerOuter : 0);
        final size = Size(
          constraints.maxWidth,
          (constraints.maxHeight - nonContentHeight)
              .clamp(0.0, constraints.maxHeight),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
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
            // scroll 模式: 把正文区高度同步给 handler(决定 pageOffset 边界)。
            if (size.height > 0) {
              _scrollHandler?.updatePageHeight(size.height);
            }
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
              // chrome(页眉/页脚): scroll 模式已并入 _buildScrollContent 的正文
              // Column(对齐普通 PageView 结构); 其他模式 chrome 由各页 PageView
              // 自带。此处不再单独挂 scroll chrome 浮层。
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
                    aloudController: widget.aloudController,
                    visible: widget.controller.menuVisible,
                  ),
                ),
              ],
              // 搜索结果浏览态浮层(对齐原生 view_search_menu.xml):
              // 左右导航 mini FAB + 底部信息条(结果数/主菜单/退出)。
              // 进入条件: controller.browseMode(由 enterSearchBrowse 置位)。
              if (widget.controller.browseMode) ...[
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 16,
                  child: _buildBrowseNavFab(
                    icon: LegadoIcons.skipPrevious(size: 22, color: Colors.black54),
                    onTap: () => widget.controller.previousBrowseResult(),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 16,
                  child: _buildBrowseNavFab(
                    icon: LegadoIcons.skipNext(size: 22, color: Colors.black54),
                    onTap: () => widget.controller.nextBrowseResult(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBrowseBottomBar(widget.controller),
                ),
              ],
            ],
          ),
        );
      },
      ),
    );
  }

  // ─────────── 搜索结果浏览态浮层(对齐原生 view_search_menu.xml) ───────────

  /// 浏览态左右导航 mini FAB: 垂直居中悬浮, 灰底圆形(对齐原生 fabLeft/fabRight)。
  Widget _buildBrowseNavFab({required Widget icon, required VoidCallback onTap}) {
    return Center(
      child: FloatingActionButton.small(
        heroTag: 'browse_nav_${identityHashCode(icon)}',
        onPressed: onTap,
        backgroundColor: const Color(0xFFE0E0E0),
        elevation: 2,
        shape: const CircleBorder(),
        child: icon,
      ),
    );
  }

  /// 浏览态底部信息条: 当前结果/总数 + 主菜单 + 退出(对齐原生 ll_search_results /
  /// ll_main_menu / ll_search_exit)。
  Widget _buildBrowseBottomBar(ReadingController c) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          const Spacer(flex: 2),
          _buildBrowseActionItem(
            '${c.browseIndex + 1}/${c.browseResults.length}',
            () {},
            isLabel: true,
          ),
          const Spacer(flex: 2),
          _buildBrowseActionItem(
            '主菜单',
            () => c.toggleMenu(),
          ),
          const Spacer(flex: 2),
          _buildBrowseActionItem(
            '退出',
            () => c.exitSearchBrowse(),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  /// 浏览态底部单项(文字按钮, 对齐原生 TextView 风格)。
  Widget _buildBrowseActionItem(
    String label,
    VoidCallback onTap, {
    bool isLabel = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isLabel ? Colors.black87 : Colors.black54,
                fontWeight: isLabel ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent() {
    final controller = widget.controller;
    final wantScroll = controller.settings.pageAnimMode == PageAnimMode.scroll;

    // ⚠️ 双子树常驻预热(消除切到/切出 scroll 的卡顿):
    //
    // scroll 子树与 slide/sim/none 三页 Stack 是两棵完全不同的 widget 树。旧实现
    // 用互斥 return 切换, 切到 scroll 时整棵滚动子树首次挂载 → 首次 layout(每行
    // CustomPaint 的 RenderObject 初始化)+ 首次 paint, 是肉眼可见的卡顿; 切回时
    // 同理。而 slide/none/sim 互切不卡, 正因为它们共用同一套三页 Stack, element
    // 互相复用、layer 缓存命中。
    //
    // 修复: 两棵子树都常驻挂载, 用 Visibility(maintainState/Size/Animation: true)
    // 切显隐。三个 maintain 全开 = 非活跃子树仍参与完整 layout + paint(只是不可见),
    // Element/RenderObject/已算好的 layout 全部保留 → 切换时 element 复用 → 零首帧开销。
    //
    // ⚠️ 用 RepaintBoundary 包裹: 非活跃子树 paint 一次后 layer 缓存, 仅在其后代
    // 标记 dirty 时才重绘(非 scroll 模式下 handler 不 notify → 不重绘), 避免常驻
    // paint 的每帧开销。代价是常驻一个隐藏子树的内存。
    //
    // ⚠️ 不能用 Offstage: 它跳过 layout + paint, layer 缓存不保留, 切回仍要首帧开销。
    // 对齐 AGENTS.md「首次挂载卡顿」记录的 maintain 三全开模式。
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Visibility(
              visible: !wantScroll,
              maintainState: true,
              maintainSize: true,
              maintainAnimation: true,
              child: _buildPagedContent(),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: Visibility(
              visible: wantScroll,
              maintainState: true,
              maintainSize: true,
              maintainAnimation: true,
              child: _buildScrollContent(),
            ),
          ),
        ),
      ],
    );
  }

  /// 非 scroll 模式(slide/simulation/none)的三页 Stack 渲染。
  ///
  /// 从 [_buildPageContent] 拆出, 与 [_buildScrollContent] 平级常驻。
  Widget _buildPagedContent() {
    final controller = widget.controller;

    final pages = controller.pages;
    final currentIndex = controller.currentPageIndex;

    if (pages.isEmpty) {
      // pages 为空时的占位渲染:
      // - 尚未加载完成(转场延迟排版期间、首次进入、正在加载/排版中) → 显示与正文
      //   背景一致的空白占位 + 转圈(不闪现未排版原文)。对齐 legado 排版未完成时
      //   不显示正文。
      // - 已加载完确实无内容(currentChapterLoaded && pages 仍空) → 轻提示。
      //
      // 关键: 这里用 currentChapterLoaded(而非仅 chapterLoading)判断。旧逻辑只看
      // chapterLoading, 但转场动画期间 `_routeReady` 延迟排版, pages 暂空且
      // `_loadingChapters` 还空 → chapterLoading=false → 误显示「本章暂无内容」闪一下,
      // 等动画结束开始排版才切回 loading。currentChapterLoaded 在正文真正取回排版完才置真,
      // 覆盖了「加载未开始」这一中间态, 消除闪现。
      final bg = controller.settings.backgroundColor;
      if (!controller.currentChapterLoaded) {
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
    // slide 偏移矩阵(progress = 翻页完成度, none 态视为 0):
    // | 状态      | cur.x        | next.x           | prev.x           |
    // |----------|--------------|------------------|------------------|
    // | none     | 0            | +width (屏外)    | -width (屏外)    |
    // | NEXT(p)  | -p·w         | (1-p)·w          | -width (屏外)    |
    // | PREV(p)  | +p·w         | +width (屏外)    | (p-1)·w          |
    // none→NEXT 在 p=0 时各 offset 都等于静止态值, 过渡完全连续。
    //
    // cover 偏移矩阵(目标页静止, 覆盖方平移; 推导见 cover_layout.dart):
    // | 状态      | cur.x        | next.x           | prev.x           |
    // |----------|--------------|------------------|------------------|
    // | none     | 0            | +width (屏外)    | -width (屏外)    |
    // | NEXT(p)  | -p·w (滑出)  | 0 (静止,被覆盖)  | -width (屏外)    |
    // | PREV(p)  | 0 (静止)     | +width (屏外)    | (p-1)·w (滑入)   |
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final progress = _currentProgress(width);
        final isNext = _animDir == _PageDirection.next;
        final isPrev = _animDir == _PageDirection.prev;
        final pageAnim = controller.settings.pageAnimMode;
        final isSim = pageAnim == PageAnimMode.simulation;
        final isCover = pageAnim == PageAnimMode.cover;

        // 仿真模式: 三页 STACK 始终挂载(供 RepaintBoundary 截图), 但翻页进行中
        // (_animDir != none) 在其上覆盖一层 CustomPaint 由 SimulationPainter 接管
        // 绘制卷曲效果(对齐原生 setBitmap 后整页由 bitmap 绘制)。静止态不覆盖,
        // 直接显示当前页, 避免无谓的 CustomPaint 重绘。
        final curWidget = RepaintBoundary(
          key: isSim ? _curBoundaryKey : null,
          child: _buildPage(pages[currentIndex], currentIndex),
        );
        // 屏外页用 IgnorePointer 避免接收不到手势(都在屏外, 本就不会被点, 但保险)。
        final nextWidget = _nextCache == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: RepaintBoundary(
                    key: isSim ? _nextBoundaryKey : null,
                    child: _buildPeekPage(_nextCache!)));
        final prevWidget = _prevCache == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: RepaintBoundary(
                    key: isSim ? _prevBoundaryKey : null,
                    child: _buildPeekPage(_prevCache!)));

        // 仿真模式: 翻页视觉完全由上层覆盖层 SimulationPainter 画卷曲承担, 底层
        // pageStack 必须静止在原位(offset=0)作为截图源 + 底层支撑。否则 pageStack 按
        // progress 平移会与覆盖层的卷曲叠加 → 用户看到 next 页"滑进来"+"卷曲"双重效果,
        // 即"内容提前变"(卷曲还没完成, 底层 next 已经滑到屏幕中央)。
        // slide/none/cover 模式才用 progress 偏移做翻页。
        final effProgress = isSim ? 0.0 : progress;
        final effIsNext = isSim ? false : isNext;
        final effIsPrev = isSim ? false : isPrev;

        double curOffsetX, nextOffsetX, prevOffsetX;
        double? shadowLeft;
        if (isCover) {
          // cover: 目标页静止, 覆盖方平移(对齐原生 CoverPageDelegate.onDraw)。
          final o = calcCoverOffsets(
            progress: effProgress,
            isNext: effIsNext,
            isPrev: effIsPrev,
            width: width,
          );
          curOffsetX = o.curX;
          nextOffsetX = o.nextX;
          prevOffsetX = o.prevX;
          shadowLeft = o.shadowLeft;
        } else {
          // slide/none: cur 和 next/prev 都按 progress 平移。
          // cur 偏移: NEXT 向左(-p·w), PREV 向右(+p·w), none 留在原位。
          curOffsetX = effIsNext ? -effProgress * width
              : effIsPrev ? effProgress * width
              : 0.0;
          // next 偏移: NEXT 从屏右滑入((1-p)·w → 0); 否则屏外(+width)。
          nextOffsetX = effIsNext ? width - effProgress * width : width;
          // prev 偏移: PREV 从屏左滑入((p-1)·w → 0); 否则屏外(-width)。
          prevOffsetX = effIsPrev ? effProgress * width - width : -width;
        }

        // 层级:
        // - slide/none/sim: [prev, cur, next](NEXT 时 next 在最上层覆盖 cur; PREV 时
        //   prev 在 cur 下但 cur 右移露出 prev)。
        // - cover: [next, cur, prev](PREV 时 prev 在最上层覆盖 cur; NEXT 时 next 在
        //   cur 下, cur 左滑露出 next)。none 态 next/prev 都屏外, 顺序变化不可见,
        //   故整个翻页周期 children 顺序固定不变, 无 element 重建闪烁。
        final List<Widget> pageChildren;
        if (isCover) {
          pageChildren = [
            Transform.translate(offset: Offset(nextOffsetX, 0), child: nextWidget),
            Transform.translate(offset: Offset(curOffsetX, 0), child: curWidget),
            Transform.translate(offset: Offset(prevOffsetX, 0), child: prevWidget),
          ];
        } else {
          pageChildren = [
            Transform.translate(offset: Offset(prevOffsetX, 0), child: prevWidget),
            Transform.translate(offset: Offset(curOffsetX, 0), child: curWidget),
            Transform.translate(offset: Offset(nextOffsetX, 0), child: nextWidget),
          ];
        }
        final pageStack = Stack(children: pageChildren);

        // cover 翻页阴影: 覆盖层后缘的 30px 渐变(对齐原生 addShadow)。静止态
        // (progress=0/1)shadowLeft 为 null 不画。
        if (isCover && shadowLeft != null) {
          return Stack(children: [
            pageStack,
            _buildCoverShadow(shadowLeft, height),
          ]);
        }

        if (!isSim || _animDir == _PageDirection.none) {
          return pageStack;
        }
        // 仿真覆盖层: 翻起页(cur)与目标页(next/prev)的位图由 painter 绘制卷曲。
        // PREV 时翻起页应是 prev(底层), 故 painter 的 curImage 传 prev 位图、
        // targetImage 传 cur 位图(对齐原生 onDraw PREV 分支: drawCurrentPageArea(prevBitmap),
        // drawNextPageAreaAndShadow(curBitmap))。
        final turningImage = isNext ? _simCur : _simPrev;
        final baseImage = isNext ? _simNext : _simCur;
        return Stack(children: [
          pageStack,
          Positioned.fill(
            child: CustomPaint(
              painter: SimulationPainter(
                curImage: turningImage,
                targetImage: baseImage,
                isNext: isNext,
                touch: _simTouch,
                corner: _simCorner ?? const SimCorner(cornerX: 0, cornerY: 0, isRtOrLb: false),
                bgColor: controller.settings.backgroundColor,
                viewSize: Size(width, height),
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        ]);
      },
    );
  }

  /// 拖拽阶段的翻页完成度 progress ∈ [0,1]。
  ///
  /// **无动画模式恒为 0**(对齐原生 `NoAnimPageDelegate.onDraw` 空实现): 该 delegate
  /// 继承 `HorizontalPageDelegate` 故手势判定(方向锁定/cancel/提交)照常生效, 但
  /// `onDraw`/`setBitmap` 全空 → 拖拽过程中画面纹丝不动, 松手才 `onAnimStart` 直接
  /// `fillPage` 跳转。这里 progress=0 让三页都停在静止偏移, 视觉与原生一致。
  ///
  /// **slide 模式防越界**(对齐原生 `SlidePageDelegate.onDraw:36-39`):
  /// 方向一旦锁定, 手指越过起点滑到相反侧(NEXT 时 `_dragOffset>0` / PREV 时
  /// `<0`) → 视为 0(页面停留原位, 不反向滑动)。原生在该情况下 `return` 不绘制;
  /// Flutter 用 progress=0 达到相同视觉效果(cur/next/prev 三页都在静止偏移)。
  ///
  /// 否则按 `|_dragOffset| / width` 计算。clamp 防 _dragOffset 超屏宽(超出右边缘)。
  ///
  /// **为什么不让 _animDir 跟着翻转**: legado 的设计是「方向锁定后, 想反向必须松手
  /// 重来」; 若中途翻转方向, 已预热的 peek 页(next/prev)与当前手势会错配, 且动画
  /// 起止/commit 目标都要重算, 复杂且与原生手感不符。防越界 → progress=0 是最小
  /// 改动且语义自洽的修复。
  double _dragProgress(double width) {
    if (width <= 0) return 0;
    // 无动画模式: 对齐原生 NoAnimPageDelegate.onDraw 空实现, 拖拽时画面静止。
    if (controller.settings.pageAnimMode == PageAnimMode.none) return 0;
    final signed = _dragOffset;
    if (_animDir == _PageDirection.next && signed > 0) return 0;
    if (_animDir == _PageDirection.prev && signed < 0) return 0;
    return (signed.abs() / width).clamp(0.0, 1.0);
  }

  /// 当前翻页完成度 progress ∈ [0,1]。
  /// 拖拽阶段 = [_dragProgress](带符号防越界); 动画阶段 = _pageAnimCurved.value。
  double _currentProgress(double width) {
    if (width <= 0) return 0;
    if (_isDragging) {
      return _dragProgress(width);
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
      aloudController: widget.aloudController,
      aloudVersion: widget.aloudController?.aloudVersion ?? 0,
    );
  }

  /// scroll 模式正文层: ClipRect(Stack) 用 pageOffset 偏移拼接 cur/prev/next 三页。
  ///
  /// 对齐原生 `ContentTextView.drawPage` + `relativeOffset`: 把三个逻辑页
  /// 拼接在同一视口, `pageOffset` 变化时整体平移。chrome 不在这里画 —— 由
  /// [_buildScrollChrome] 在外层 Stack 固定(对齐原生 chrome 在 PageView 父布局)。
  ///
  /// 页定位(对齐原生 relativeOffset):
  /// - prev(上一章末页) top = pageOffset - pageHeight  (向上滚时从顶部露出)
  /// - cur top = pageOffset                            (范围 [-pageHeight, 0])
  /// - next(下一章首页) top = pageOffset + pageHeight  (向下滚时从底部露出)
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
      // 跨章预取页用 PeekInfo.chapterPageCount(目标章总页数, 由 peek 时填入);
      // 章内预取用当前章 totalPages; 都没有则用 pageIndex+1 近似(翻页提交后
      // controller 重排会用准确值)。修复跨章拖拽时页脚"页码/总页数"显示错误。
      totalPages: info.chapterPageCount ??
          (info.chapterIndex == c.currentChapterIndex
              ? c.totalPages
              : info.pageIndex + 1),
      chapterIndex: info.chapterIndex,
      chapterSize: c.totalChapters,
      chapterTitle: c.getChapter(info.chapterIndex)?.title,
      bookName: c.book?.title,
      searchQuery: c.searchQuery.isNotEmpty ? c.searchQuery : null,
      useSafeArea: true,
      showChrome: true,
      batteryLevel: BatteryProvider.instance.value,
      aloudController: widget.aloudController,
      aloudVersion: widget.aloudController?.aloudVersion ?? 0,
    );
  }

  /// cover 翻页阴影: 覆盖层后缘的渐变(对齐原生 `CoverPageDelegate.addShadow`)。
  ///
  /// 原生用 30px 宽 `GradientDrawable(LEFT_RIGHT, [0x66111111, 0x00000000])` 画在
  /// 覆盖移动页的右边缘。Flutter 用 [Positioned] + [LinearGradient] 等价实现:
  /// 从 [left] 向右画 [kCoverShadowWidth] 宽, 深灰→透明。`IgnorePointer` 避免挡手势。
  Widget _buildCoverShadow(double left, double height) {
    return Positioned(
      left: left,
      top: 0,
      width: kCoverShadowWidth,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(kCoverShadowColorARGB),
                const Color(0x00000000),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
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
  /// **slide/none 模式**: 用 PostFrame 延迟 commit, 让 completion 帧 progress=1.0 先渲染。
  ///
  /// **仿真模式**: 反过来, 必须**立即** commit, 不延迟。因为仿真动画末态 touch 被推到
  /// 屏外(`to.x = -width` 或 `2·width`), calcPoints 算出的 path0 几何会严重变形 →
  /// 覆盖层画出扭曲的卷曲形状。延迟到 PostFrame 会让这帧扭曲几何先渲染 → 用户看到
  /// 末态扭曲跳变。立即 commit 让 completion 帧直接渲染 commit 后的静止态(底层
  /// pageStack 已是新页, 覆盖层因 _animDir=none 不挂), 视觉自然过渡, 无扭曲帧。
  void _onPageAnimStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_animDir == _PageDirection.none) return;
    // 记下本次提交参数。动画启动前已确定方向并预热 peek; 此处兜底以防预热失效
    // (跨章相邻缓存未就绪), 避免动画播完 target 仍为 null 导致白翻。
    final shouldCommit = !_isCancel;
    final dir = _animDir;
    final target = _resolveTarget(dir);
    final gen = _animGen;
    // 仿真模式: 立即提交, 不让末态扭曲几何渲染。
    if (controller.settings.pageAnimMode == PageAnimMode.simulation) {
      _deferredCommit(
        gen: gen,
        shouldCommit: shouldCommit,
        dir: dir,
        target: target,
      );
      return;
    }
    // slide/none 模式: 推迟到下一帧, 让 completion 帧 progress=1.0 先渲染。
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
    // 先停动画再 dispose 位图, 避免动画进行中 dispose painter 正在用的 image。
    _resetAnimState();
    _resetSimState();
    if (shouldCommit && target != null) {
      controller.commitTurn(target);
    } else {
      // 回弹或无目标: 仅重绘回到静止态。
      if (mounted) setState(() {});
    }
  }

  /// 替换 `_pageAnimCurved` 的统一入口, slide/sim 两种动画启动共用。
  ///
  /// **防 listener 泄漏**(竞态修复): 替换前先 removeListener 旧的 `_pageAnimCurved`。
  /// `_startPageAnim`/`_startSimAnim` 都直接赋值 `_pageAnimCurved`, 若上一轮还挂着
  /// 监听(未经 _resetAnimState 清理)就直接覆盖, 旧引用丢失 → 它的
  /// `_onAnimTick`/`_onSimAnimTick` 监听永远不再被 remove(绑在同一个 `_pageAnim`
  /// 上, 会继续被触发重复 setState)。removeListener 即阻断此反向触发, 解决 C2。
  ///
  /// ⚠️ 不调 `old.dispose()`: `_pageAnimCurved` 字段类型是 `Animation<double>`,
  /// 实际是 `Tween.animate(CurvedAnimation(...))` 的产物 `_AnimatedEvaluation`(无
  /// dispose 方法); 内层的 `CurvedAnimation` 引用未单独持有, 无法 dispose。残留的
  /// CurvedAnimation 内部 listener 会随 _pageAnim 空转, 开销极小, 不引发 bug; 留待
  /// 未来用单层 listener 架构(直接监听 _pageAnim + listener 内手算 from/to 映射)
  /// 彻底清理。
  @override
  void _attachAnimListener(
      double from, double to, void Function() listener) {
    final old = _pageAnimCurved;
    if (old != null) {
      // 两种监听都防御性移除(slide/sim 都可能挂过)。
      old.removeListener(_onAnimTick);
      old.removeListener(_onSimAnimTick);
    }
    _pageAnimCurved = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _pageAnim, curve: Curves.linear),
    );
    _pageAnimCurved!.addListener(listener);
  }

  /// 重置动画状态到静止(none)。
  ///
  /// ⚠️ 不清空 _nextCache/_prevCache: 新架构下它们是常驻预热缓存,
  /// 由 _refreshPeekCaches 统一管理(章/页变化时刷新)。
  /// 清空会导致预热失效 → 拖拽首帧 hitch 回归 / 翻页失败。
  @override
  void _resetAnimState() {
    _animDir = _PageDirection.none;
    _isDragging = false;
    _isCancel = false;
    _dragOffset = 0;
    final old = _pageAnimCurved;
    if (old != null) {
      // 两种动画监听都先移除(slide 用 _onAnimTick, sim 用 _onSimAnimTick), 防御性双移除。
      // (不调 old.dispose(): _pageAnimCurved 类型是 Animation<double>, 实际是
      // _AnimatedEvaluation 无 dispose 方法; 见 _attachAnimListener 注释。)
      old.removeListener(_onAnimTick);
      old.removeListener(_onSimAnimTick);
      _pageAnimCurved = null;
    }
    if (_pageAnim.isAnimating) _pageAnim.stop();
    _pageAnim.value = 0;
    // 自增代际号: 使任何挂起的 _deferredCommit / _captureSimBitmaps future 失效,
    // 避免旧动画的延迟提交 / 旧截图回填误覆盖刚启动的新翻页/拖拽状态。
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
    _pageAnim.duration = Duration(milliseconds: durationMs < 1 ? 1 : durationMs);
    _attachAnimListener(from, to, _onAnimTick);
    _pageAnim.forward(from: 0);
  }

  /// 动画逐帧驱动重绘。
  @override
  void _onAnimTick() {
    if (mounted) setState(() {});
  }

  /// 程序化翻页(点击触发)。对齐原生 ReadView.kt:444 nextPageByAnim/prevPageByAnim
  /// + HorizontalPageDelegate.abortAnim。
  ///
  /// 关键(原生丝滑连点的来源): 若动画进行中再次点击, 不是忽略, 而是
  /// abortAnim —— 中断当前动画 + 若非取消则 fillPage 提交这次翻页(跳过动画
  /// 尾巴直接到位), 然后从新的当前页启动下一次动画。这样连点每一次都立即响应,
  /// 取翻页目标页: 优先用 [_nextCache]/[_prevCache] 预热缓存, 为空则即时 peek 兜底
  /// 并回填缓存。点击与拖拽/动画提交共用此入口, 避免「拖拽路径漏兜底 → 缓存为空时
  /// 滑出纯白页 + 松手回弹、而点击能翻过去」的不一致(bug 修复)。
  @override
  PeekInfo? _resolveTarget(_PageDirection dir) {
    final cached = dir == _PageDirection.next ? _nextCache : _prevCache;
    if (cached != null) return cached;
    final fresh = dir == _PageDirection.next
        ? controller.peekNext()
        : controller.peekPrev();
    if (dir == _PageDirection.next) {
      _nextCache = fresh;
    } else {
      _prevCache = fresh;
    }
    return fresh;
  }

  /// 不被 300ms 动画尾巴阻塞。
  void _turnByAnim(_PageDirection dir) {
    final c = controller;
    // 动画进行中再次点击: 中断 + 提交当前翻页, 然后从新当前页继续(对齐 abortAnim)。
    // wasAborting 标记供仿真分支决定截图时机(连点需 PostFrame 延迟, 见下)。
    final wasAborting = _animDir != _PageDirection.none;
    if (wasAborting) {
      _abortAndCommit();
    }
    if (dir == _PageDirection.next && !c.canGoNext) return;
    if (dir == _PageDirection.prev && !c.canGoPrevious) return;
    // scroll 模式: 点击翻页 = 平滑滚动一整页(对齐原生 nextPageByAnim →
    // startScroll)。离散分页模型下整页翻(±pageHeight), 与 slide/sim 一致。
    if (controller.settings.pageAnimMode == PageAnimMode.scroll &&
        _scrollHandler != null) {
      _scrollHandler!.turnByClick(dir == _PageDirection.next);
      return;
    }
    // 邻接页已由 _refreshPeekCaches 预热常驻, 直接取用; 若预热失效(如数据异步
    // 就绪晚于 initState、跨章相邻缓存未填好)则即时 peek 兜底, 保证翻页不会因
    // 预热 bug 彻底失败。点击与拖拽共用同一兜底(见 _resolveTarget)。
    final target = _resolveTarget(dir);
    if (target == null) return;
    // 无动画模式: 直接提交, 不进入叠加态也不启动动画。
    if (controller.settings.pageAnimMode == PageAnimMode.none) {
      controller.commitTurn(target);
      return;
    }
    // 仿真翻页: 点击翻页从对应角启动卷曲动画(对齐原生点击翻页)。
    // ⚠️ corner 与 touch 起始点对齐原生 nextPageByAnim/prevPageByAnim:
    // - **NEXT**: corner = 右下角(W,H); touch 起始 = (W·0.9, H·0.9 或 1)。
    //   原生 nextPageByAnim: setDirection 后 setStartPoint(W·0.9, y)。touch 靠近
    //   corner(卷曲≈0), 动画把 touch 推向屏左(远离 corner)→ 卷曲越来越大, 整页翻过去。
    // - **PREV**: corner = **右下角(W,H)**(不是左下角!); touch 起始 = (0, H) 左下角。
    //   原生 prevPageByAnim: setDirection(PREV) 里 calcCornerXY 镜像 startX 后恒得
    //   右下角; setStartPoint(0, H)。touch 远离 corner(卷曲最大, prev 页卷在右下),
    //   动画把 touch 推向 corner(右下)→ 卷曲展开覆盖 cur, 结束整屏 prev。
    //
    // ⚠️ touch 起始不能精确等于 corner(否则 calcPoints 的 middleX==cornerX 分母 0,
    // 触发除零保护, 几何偏差)。故 NEXT 用 W·0.9 而非 W。
    if (controller.settings.pageAnimMode == PageAnimMode.simulation) {
      final size = MediaQuery.of(context).size;
      final isNext = dir == _PageDirection.next;
      _animDir = dir;
      _isCancel = false;
      _isDragging = false;
      // corner 两方向都用右下角(对齐原生 setDirection 镜像逻辑)。
      _simCorner = SimGeometry.calcCornerXY(
          size.width, size.height, size.width, size.height);
      _simStartLocal = isNext
          ? Offset(size.width * 0.9, size.height * 0.9)
          : Offset(0, size.height);
      // touch 起始: NEXT 靠近 corner(卷曲≈0); PREV 在左下角(远离 corner, 卷曲最大)。
      _simTouch = isNext
          ? Offset(size.width * 0.9, size.height * 0.9)
          : Offset(0, size.height);
      // 等截图完成后再启动动画。setState 进入叠加态(覆盖层挂载), 但 painter 在
      // curImage==null 时透明不画 → 底层静止 pageStack 显示当前页, 无闪烁; 截图完成
      // 内部 setState → painter 拿到位图开始画卷曲 → then 启动动画, 零跳跃。
      //
      // 代际守护: 捕获本次手势的 _animGen, 截图 future 完成时若 gen 已变(连点/abort/
      // 起新手势都会 _animGen++), 不启动动画。统一用 _animGen 替代旧 _animDir != dir
      // 判定 —— 跨方向连点(next→prev)和同方向连点(next→next)守护语义一致(对齐
      // _deferredCommit 的 gen 守护)。
      //
      // ⚠️ 连点时序(wasAborting=true): abort 提交一页后 controller notifyListeners →
      // setState 已调度, 但 widget 树 rebuild + RepaintBoundary 重绘要等下一帧 paint。
      // 若立即 toImage, 截到的是**旧 cur/next**(上一帧 layer 缓存) → painter 在旧图上
      // 做动画, 用户看到第二次点击毫无作用(从 P1 又翻到 P2, 而非从 P2 翻到 P3)。
      // 必须延迟到 PostFrame, 让 commit 触发的 rebuild + paint 完成, 此时
      // RepaintBoundary 已是新 cur(第2页)/新 next(第3页), 截图才正确。
      // 对比原生 legado: View.draw(Canvas) 是命令式绘制, 直接强制走完整 onDraw 拿到
      // 最新 View 状态; Flutter RepaintBoundary.toImage 截的是上一帧 paint 产生的
      // layer 缓存 —— 架构差异决定 Flutter 在 setState 后必须等下一帧。
      // 第一次点击(wasAborting=false)不延迟: 邻接页 initState 已预热绘制好, 立即可截。
      final gen = _animGen;
      setState(() {});
      void capture() {
        _captureSimBitmaps(gen: gen).then((ok) {
          if (!mounted || gen != _animGen || !ok) return;
          _startSimAnim(shouldCommit: true);
        });
      }
      if (wasAborting) {
        WidgetsBinding.instance.addPostFrameCallback((_) => capture());
      } else {
        capture();
      }
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
    // 朗读运行中点击「菜单区」: 直接弹朗读控制面板(对齐原生 ReadBookActivity.kt:1124-1130
    // showActionMenu: BaseReadAloudService.isRun -> showReadAloudDialog)。
    // isRun 在 play/pause 两种态都为 true, 故朗读期间点中心都是弹控制面板而非主菜单。
    if (action == ClickAction.menu && _isAloudRunning) {
      showReadAloudDialog(context, controller: widget.aloudController!);
      _tapDownPosition = null;
      return;
    }
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
    // scroll 模式: fling 进行中触摸 → 停止 fling 从当前位置接续拖拽
    // (对齐原生 ACTION_DOWN → abortAnim; 不提交, 让用户继续操控)。
    if (widget.controller.settings.pageAnimMode == PageAnimMode.scroll &&
        _scrollHandler != null) {
      _scrollHandler!.stopFling();
    }
    // 动画中触摸 → 中断并提交当前方向(对齐原生 abortAnim)。
    if (_animDir != _PageDirection.none && !_isDragging) {
      _abortAndCommit();
    }
    _isDragging = true;
    _dragOffset = 0;
    _isCancel = false;
    _animDir = _PageDirection.none;
    // 仿真翻页: 记录按下点(用于 touchY 锁边判定, 对齐原生 startY)。
    _simStartLocal = details.localPosition;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    // scroll 模式: 纯垂直滚动。dy 正值=手指下滑(往上一页), 负值=上滑(往下一页)。
    // 直接喂给 handler.applyDragDelta, 它累加 pageOffset + 边界翻章修正。
    // 对齐原生 ScrollPageDelegate.onScroll → curPage.scroll(touchY - lastY)。
    if (widget.controller.settings.pageAnimMode == PageAnimMode.scroll &&
        _scrollHandler != null) {
      _scrollHandler!.applyDragDelta(details.delta.dy);
      return;
    }
    _dragOffset += details.delta.dx;

    // 首次确定方向(对齐原生 onScroll: 右滑>0=PREV, 左滑<0=NEXT)。
    // 邻接页已预热常驻, 这里只设方向, 不再单独 peek(消除拖拽首帧 hitch)。
    if (_animDir == _PageDirection.none && _dragOffset.abs() > 8) {
      if (_dragOffset < 0 && controller.canGoNext) {
        _animDir = _PageDirection.next;
      } else if (_dragOffset > 0 && controller.canGoPrevious) {
        _animDir = _PageDirection.prev;
      }
      if (_animDir != _PageDirection.none) {
        // 方向锁定即兜底填 peek 缓存: 预热失效时(跨章相邻缓存未就绪等)立即 peek,
        // 让 slide 模式拖拽过程中目标页能渲染真实内容(否则 nextWidget 退化为
        // SizedBox.shrink → 纯白页), 松手也能翻过去(见 _resolveTarget)。
        _resolveTarget(_animDir);
        // 仿真翻页: 方向确定时算出拖拽角并异步截图三页(对齐原生 setBitmap)。
        if (controller.settings.pageAnimMode == PageAnimMode.simulation) {
          _initSimForDrag(details.localPosition);
        }
      }
    }

    // 反向移动判定 cancel(对齐原生 onScroll: isCancel 用「本帧 X vs 上帧 X」逐帧判定,
    // 而非累积位移符号)。原生 HorizontalPageDelegate.kt:105:
    //   isCancel = (NEXT 时 sumX > lastX) 或 (PREV 时 sumX < lastX)
    // delta.dx 即本帧相对上帧的增量, 符号直接反映松手瞬间的运动趋势。
    // 这样「拖到一半反悔、回缩松开」会回弹(尊重最后意图), 与原生手感一致。
    if (_animDir == _PageDirection.next) {
      // NEXT 基准是左滑(delta<0), 本帧 delta>0 即反向。
      _isCancel = details.delta.dx > 0;
    } else if (_animDir == _PageDirection.prev) {
      // PREV 基准是右滑(delta>0), 本帧 delta<0 即反向。
      _isCancel = details.delta.dx < 0;
    }

    // 仿真翻页: 更新二维触摸点(含 touchY 锁边, 对齐原生 onTouch MOVE 173-183)。
    if (controller.settings.pageAnimMode == PageAnimMode.simulation &&
        _animDir != _PageDirection.none) {
      _updateSimTouch(details.localPosition);
    }
    if (mounted) setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;

    // scroll 模式: 松手启动 fling 惯性(对齐原生 onAnimStart → fling(yVelocity))。
    // 速度过小则直接同步进度(不启动空 fling)。
    if (widget.controller.settings.pageAnimMode == PageAnimMode.scroll &&
        _scrollHandler != null) {
      _scrollHandler!.onFlingStart(details.velocity.pixelsPerSecond.dy);
      return;
    }

    final width = MediaQuery.of(context).size.width;

    if (_animDir == _PageDirection.none) {
      // 未确定方向(位移 < 8dp), 直接回静止(对齐原生 isMoved=false 时 UP 不进翻页)。
      _resetAnimState();
      if (mounted) setState(() {});
      return;
    }

    // 与拖拽渲染同源(用 _dragProgress): 手指越过起点到反向侧时 from=0,
    // 松手即走"回弹 0→0"短路(下方 < 0.001 分支), 不启动多余动画。视觉上页面
    // 本就停在原位(越界期间 progress=0), 松手无事发生, 与原生 return 不绘制一致。
    final fromProgress = _dragProgress(width);
    // 翻页条件: 方向已确定 且 非取消。**无位移阈值** ——
    // 对齐原生 HorizontalPageDelegate: ACTION_UP → onAnimStart 直接读 isCancel,
    // 不判断移动距离; onAnimStop: if (!isCancel) fillPage()。
    // 即只要拖动方向没反向(且超过 touch slop 确定了方向), 松手就翻页。
    final shouldCommit = !_isCancel;

    // 无动画模式: 直接提交, 不播滑入/回弹动画
    // (对齐原生 NoAnimPageDelegate, 拖拽与点击共用同一 delegate)。
    if (controller.settings.pageAnimMode == PageAnimMode.none) {
      final target = _resolveTarget(_animDir);
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
      final target = _resolveTarget(_animDir);
      _resetSimState();
      _resetAnimState();
      if (shouldCommit && target != null) {
        controller.commitTurn(target);
      } else if (mounted) {
        setState(() {});
      }
      return;
    }
    // 仿真翻页: 启动 touch 点滑动动画(从松手点滑到目标角/回弹点), 而非 slide 的
    // progress 0→1。计算 onAnimStart 的目标 dx/dy(对齐原生 208-238), 用 _simAnimFrom/To
    // 记录起止 touch, _onSimAnimTick 每帧插值 _simTouch。
    if (controller.settings.pageAnimMode == PageAnimMode.simulation) {
      _startSimAnim(shouldCommit: shouldCommit);
      return;
    }
    _startPageAnim(from: fromProgress, to: toProgress);
  }

}

/// 拖拽方向(内部使用)。
enum _PageDirection { none, next, prev }
