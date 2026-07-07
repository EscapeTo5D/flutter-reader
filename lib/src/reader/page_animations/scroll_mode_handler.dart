import 'package:flutter/material.dart';

import '../../core/controller/reading_controller.dart';
import '../entities/text_page.dart';

/// 滚动翻页模式核心状态机, 对齐原生 legado `ScrollPageDelegate` +
/// `ContentTextView.scroll`。
///
/// ## 核心模型(务必记住)
///
/// 单一状态变量 [pageOffset] ∈ `[-pageHeight, 0]`:
/// - `0`        → 当前页顶部对齐视口顶(显示页首)
/// - `-pageHeight` → 当前页底部对齐视口底(显示页尾)
/// - `> 0`      → 内容下方露出(需要上一页)
/// - `< -pageHeight` → 上方露出(需要下一页)
///
/// 手指拖拽 / fling 惯性 / 点击翻页 都换算成 dy 喂给 [applyDragDelta],
/// 它累加 [pageOffset], 越过 `[−pageHeight, 0]` 边界即翻页/翻章并修正偏移
/// (保持视觉连续), 到首/末页钳制 + 中止 fling(回弹)。对齐原生
/// `ContentTextView.scroll(mOffset)`(ContentTextView.kt:145-177)。
///
/// ## 与原生差异
///
/// - 原生把 cur/next/nextPlus 三个逻辑页画在**同一个 ContentTextView** 上
///   (drawPage 用 relativeOffset 拼接)。Flutter 端由 reader_view 的
///   `_buildScrollContent` 用 `Transform.translate` + `Column` 拼接三页,
///   handler 只负责数据(pageOffset + 当前章页 + 相邻章页)。
/// - 原生 fling 用 Android `Scroller.fling` + `computeScroll` 每帧驱动;
///   Flutter 用 `AnimationController` + `ClampingScrollSimulation`, 每帧
///   取 simulation 的位移 delta 喂回 [applyDragDelta]。
/// - chrome(页眉页脚)在原生固定在 PageView 父布局, 不随滚动; Flutter 端
///   由 reader_view 用 Positioned 浮层实现, handler 不参与。
class ScrollModeHandler extends ChangeNotifier {
  ScrollModeHandler(this._controller, TickerProvider vsync)
    : _chapterIndex = _controller.currentChapterIndex,
      _pageInChapter = _controller.currentPageIndex {
    _curPages = List.from(_controller.pages);
    // fling 惯性动画器(对齐原生 Scroller.fling)。每帧把 simulation 位移
    // delta 喂给 applyDragDelta, 碰边界即 stop(对齐 computeScroll + abortAnim)。
    _fling = AnimationController(vsync: vsync)..addListener(_onFlingTick);
    // 点击翻页的平滑滚动(对齐原生 startScroll)。同样每帧喂 applyDragDelta。
    _pageTurn = AnimationController(vsync: vsync)..addListener(_onPageTurnTick);
  }

  final ReadingController _controller;

  /// 单页正文区像素高度(= controller.pageSize.height)。所有页等高。
  double _pageHeight = 0;
  double get pageHeight => _pageHeight;

  /// 当前逻辑章 index(可能领先于 controller.currentChapterIndex, 因滚动
  /// 过程静默更新, ScrollEnd 才同步)。
  int _chapterIndex;
  int get chapterIndex => _chapterIndex;

  /// 当前章内的页 index。
  int _pageInChapter;
  int get pageInChapter => _pageInChapter;

  /// 当前章分页结果。
  List<TextPage> _curPages = [];
  List<TextPage> get curPages => _curPages;

  /// 相邻章分页(null = 未预取/无相邻章)。翻章时复用, 避免同步重排卡顿。
  /// 暴露给渲染层(拼接 cur/next/prev 三页用, 对齐原生 relativePage)。
  List<TextPage>? _prevPages;
  List<TextPage>? _nextPages;
  List<TextPage>? get prevPages => _prevPages;
  List<TextPage>? get nextPages => _nextPages;

  /// 滚动偏移, 范围 `[-pageHeight, 0]`。见类注释。
  double _pageOffset = 0;
  double get pageOffset => _pageOffset;

  late final AnimationController _fling;
  late final AnimationController _pageTurn;

  /// fling 的位移 simulation(逐帧取 x 即位移)。
  Simulation? _flingSim;
  double _flingLastValue = 0;

  /// 点击翻页的目标位移容器(逐帧由 _onPageTurnTick 映射)。
  _SmoothScrollSimulation? _pageTurnSim;
  double _pageTurnLastValue = 0;

  /// 是否正在 fling(用于区分拖拽/fling, ScrollEnd 判定)。
  bool get isFlinging => _fling.isAnimating || _pageTurn.isAnimating;

  @override
  void dispose() {
    _fling.dispose();
    _pageTurn.dispose();
    super.dispose();
  }

  // ───────────────────────── 章页数据同步 ─────────────────────────

  /// reader_view 在 LayoutBuilder 拿到正文区尺寸时调用。尺寸变化(旋转/分屏)
  /// 时重新校准 pageHeight, 并重排相邻章。
  void updatePageHeight(double height) {
    if (height <= 0) return;
    final changed = (height - _pageHeight).abs() > 0.5;
    _pageHeight = height;
    if (changed || _curPages.isEmpty && _controller.pages.isNotEmpty) {
      // 尺寸变 → 当前章已由 controller 重排(走 updatePageSize 防抖), 这里同步。
      _curPages = List.from(_controller.pages);
      _pageInChapter = _curPages.isEmpty
          ? 0
          : _controller.currentPageIndex.clamp(0, _curPages.length - 1);
      // 相邻章分页失效, 重排。
      _prevPages = null;
      _nextPages = null;
      _ensureAdjacentPages();
      _pageOffset = 0;
      notifyListeners();
    } else if (_curPages.isEmpty && _controller.pages.isNotEmpty) {
      _curPages = List.from(_controller.pages);
      _ensureAdjacentPages();
      notifyListeners();
    }
  }

  /// controller 的章/页变化时(loadBook/restoreProgress/翻页提交)同步。
  /// 由 reader_view 监听 controller 后调用。
  void syncFromController() {
    final ci = _controller.currentChapterIndex;
    final pi = _controller.currentPageIndex;
    if (ci != _chapterIndex ||
        _curPages.isEmpty ||
        !identical(_curPages, _controller.pages) &&
            _curPages.length != _controller.pages.length) {
      _chapterIndex = ci;
      _curPages = List.from(_controller.pages);
      _pageInChapter = _curPages.isEmpty
          ? 0
          : pi.clamp(0, _curPages.length - 1);
      _prevPages = null;
      _nextPages = null;
      _ensureAdjacentPages();
      _pageOffset = 0;
      notifyListeners();
    }
  }

  /// 预取相邻两章分页(缓存命中 O(1), 复用 controller._adjacentChapterCache)。
  void _ensureAdjacentPages() {
    if (_chapterIndex > 0 && _prevPages == null) {
      _prevPages = _controller.paginateChapter(_chapterIndex - 1);
    }
    if (_chapterIndex < _controller.totalChapters - 1 && _nextPages == null) {
      _nextPages = _controller.paginateChapter(_chapterIndex + 1);
    }
  }

  // ───────────────────────── 核心滚动算法 ─────────────────────────

  /// 累加滚动偏移, 越过 `[−pageHeight, 0]` 边界即翻页/翻章并修正。
  ///
  /// dy 语义: 正值=内容下移(手指下滑, 往上一页方向), 负值=内容上移
  /// (手指上滑, 往下一页方向)。直接对齐原生 `ContentTextView.scroll(mOffset)`
  /// 的 `pageOffset += mOffset`。
  ///
  /// 边界处理(对齐 ContentTextView.kt:145-177):
  /// 1. 首章首页仍向下偏移 → 钳 0 + 中止 fling(回弹)。
  /// 2. 末章末页仍向上偏移(露出下方) → 钳制 + 中止 fling。
  /// 3. `pageOffset > 0` → 翻到上一页/上一章, offset 减一个旧页高度。
  /// 4. `pageOffset < -pageHeight` → 翻到下一页/下一章, offset 加一个旧页高度。
  void applyDragDelta(double dy) {
    if (_pageHeight <= 0 || _curPages.isEmpty) return;
    _pageOffset += dy;

    // 循环消化越界(对齐原生逐帧小增量; fling 大步长或测试大 dy 时单次可能越过
    // 多页, 循环翻到 pageOffset 落回 [-pageHeight, 0] 为止)。guard 限制最多翻
    // (总章×每章页数) 次, 防御异常 dy(如 1e9)导致死循环。
    final maxIterations =
        (_controller.totalChapters + 1) * (_curPages.length + 1) + 4;
    var iter = 0;
    while (iter++ < maxIterations) {
      final hasPrev = _hasPrev();
      final hasNext = _hasNext();

      // 边界1: 首章首页继续向下(dy>0) → 钳 0, 中止 fling(回弹)。
      if (!hasPrev && _pageOffset > 0) {
        _pageOffset = 0;
        _abortAnim();
        notifyListeners();
        return;
      }
      // 边界3: 越过顶部(pageOffset > 0, 且有上一页) → 翻上一页/上一章。
      if (_pageOffset > 0) {
        if (_moveToPrev()) {
          _pageOffset -= _pageHeight;
        } else {
          _pageOffset = 0;
          _abortAnim();
          notifyListeners();
          return;
        }
        continue; // 翻页后可能仍越界, 继续消化。
      }
      // 边界4: 越过底部(pageOffset < -pageHeight) → 翻下一页/下一章; 无下一页钳制。
      if (_pageOffset < -_pageHeight) {
        final moved = hasNext && _moveToNext();
        if (moved) {
          _pageOffset += _pageHeight;
        } else {
          _pageOffset = -_pageHeight;
          _abortAnim();
          notifyListeners();
          return;
        }
        continue; // 翻页后可能仍越界, 继续消化。
      }
      break; // pageOffset 已在 [-pageHeight, 0] 内, 退出。
    }
    notifyListeners();
  }

  /// 是否有上一页(章内或跨章)。对齐原生 `pageFactory.hasPrev`。
  bool _hasPrev() {
    if (_pageInChapter > 0) return true;
    return _chapterIndex > 0 && (_prevPages?.isNotEmpty ?? false);
  }

  /// 是否有下一页(章内或跨章)。对齐原生 `pageFactory.hasNext`。
  bool _hasNext() {
    if (_pageInChapter < _curPages.length - 1) return true;
    return _chapterIndex < _controller.totalChapters - 1 &&
        (_nextPages?.isNotEmpty ?? false);
  }

  /// 翻到上一页/上一章(对齐 `moveToPrev`)。成功返回 true。
  bool _moveToPrev() {
    if (_pageInChapter > 0) {
      _pageInChapter--;
      return true;
    }
    if (_chapterIndex > 0 && (_prevPages?.isNotEmpty ?? false)) {
      _chapterIndex--;
      _curPages = List.from(_prevPages!);
      _pageInChapter = _curPages.length - 1;
      // 相邻章滚动一格: 新 prev = 上上一章, 新 next = 原当前章。
      _nextPages = List.from(_controller.paginateChapter(_chapterIndex + 1));
      _prevPages = _chapterIndex > 0
          ? _controller.paginateChapter(_chapterIndex - 1)
          : null;
      return true;
    }
    return false;
  }

  /// 翻到下一页/下一章(对齐 `moveToNext`)。成功返回 true。
  bool _moveToNext() {
    if (_pageInChapter < _curPages.length - 1) {
      _pageInChapter++;
      return true;
    }
    if (_chapterIndex < _controller.totalChapters - 1 &&
        (_nextPages?.isNotEmpty ?? false)) {
      _chapterIndex++;
      _curPages = List.from(_nextPages!);
      _pageInChapter = 0;
      _prevPages = List.from(_controller.paginateChapter(_chapterIndex - 1));
      _nextPages = _chapterIndex < _controller.totalChapters - 1
          ? _controller.paginateChapter(_chapterIndex + 1)
          : null;
      return true;
    }
    return false;
  }

  // ───────────────────────── fling 惯性 ─────────────────────────

  /// 启动 fling(松手时调用)。velocityY 来自 DragEndDetails.velocity.pixelsPerSecond.dy。
  /// 对齐原生 `ScrollPageDelegate.onAnimStart` → `fling(0, touchY, 0, yVelocity, ...)`。
  void onFlingStart(double velocityY) {
    if (velocityY.abs() < 50) {
      // 速度过小不启动 fling, 直接同步进度。
      _syncToController();
      return;
    }
    // ClampingScrollSimulation 提供带摩擦减速的位移, 接近原生 Scroller.fling。
    // 它以「秒」为自变量, x(t) 返回该时刻的像素位置。用真实流逝时间驱动
    // (而非 AnimationController 的归一化 value), 否则摩擦衰减曲线会失真。
    // friction 用 Flutter 默认(0.025), 接近 Android Scroller 的 VISCOSITY。
    _flingSim = ClampingScrollSimulation(position: 0, velocity: velocityY);
    _flingLastValue = 0;
    _flingStartTime = null;
    _fling.duration = const Duration(seconds: 4); // 上限, isDone 后自停
    _fling.forward(from: 0);
  }

  Duration? _flingStartTime;

  void _onFlingTick() {
    final sim = _flingSim;
    if (sim == null || _pageHeight <= 0) return;
    // 用真实流逝时间驱动 simulation(秒)。lastElapsedDuration 是自 forward 起的耗时。
    final elapsed = _fling.lastElapsedDuration ?? Duration.zero;
    _flingStartTime ??= elapsed;
    final tSec = (elapsed - _flingStartTime!).inMicroseconds / 1e6;
    final pos = sim.x(tSec);
    final dy = pos - _flingLastValue;
    _flingLastValue = pos;
    // 碰边界(applyDragDelta 内部会 _abortAnim 停止 fling)。
    applyDragDelta(dy);
    // simulation 自身判定完成(速度衰减为 0)。
    if (sim.isDone(tSec) && _fling.isAnimating) {
      _fling.stop(canceled: false);
      _syncToController();
    }
  }

  /// 中止 fling/pageTurn(对齐原生 `abortAnim`)。边界钳制时调用。
  void _abortAnim() {
    if (_fling.isAnimating) _fling.stop(canceled: true);
    if (_pageTurn.isAnimating) _pageTurn.stop(canceled: true);
  }

  /// 手动停止 fling(不提交进度)。供 reader_view 在用户「fling 中再触摸」时
  /// 中断惯性、从当前位置接续拖拽(对齐原生 ACTION_DOWN → abortAnim 不 fillPage)。
  void stopFling() {
    if (_fling.isAnimating) _fling.stop(canceled: true);
    if (_pageTurn.isAnimating) _pageTurn.stop(canceled: true);
  }

  // ───────────────────────── 点击翻页(平滑滚动) ─────────────────────────

  /// 点击翻页(对齐原生 `nextPageByAnim`/`prevPageByAnim` → `startScroll`)。
  ///
  /// 在离散分页模型下, 点击翻页 = 平滑滚动一整页(±pageHeight), 落到下一页/
  /// 上一页顶部。原生的「保留最后一行」(calcNextPageOffset)是连续画布下的优化
  /// (一页底 + 下一页首同框); Flutter 端正文页离散, 直接翻整页语义更清晰、且与
  /// slide/simulation 模式的点击翻页行为一致(都是"进到下一页")。
  /// 无动画模式(pageAnimMode==none)直接跳过动画。
  void turnByClick(bool next, {bool noAnim = false}) {
    if (_pageHeight <= 0 || _curPages.isEmpty) return;
    // 滚动一整页 ±pageHeight。多滚 0.5px 确保 offset 越过 -pageHeight 边界
    // (applyDragDelta 用严格小于判定; 恰好 = -pageHeight 不翻页, 显示页尾)。
    final dy = next ? -(_pageHeight + 0.5) : (_pageHeight + 0.5);
    if (dy == 0) return;
    if (noAnim) {
      applyDragDelta(dy);
      _syncToController();
      return;
    }
    // 启动平滑滚动动画(对齐 startScroll: duration = speed * |dy|/viewHeight,
    // 满页 = 300ms)。用 easeOut 起停更自然。
    final distance = dy.abs();
    final durationMs = (_pageAnimSpeedMs * distance / _pageHeight)
        .round()
        .clamp(120, _pageAnimSpeedMs);
    _pageTurnLastValue = 0;
    _pageTurnSim = _SmoothScrollSimulation(from: 0, to: dy);
    _pageTurn.duration = Duration(milliseconds: durationMs);
    _pageTurn.forward(from: 0);
  }

  void _onPageTurnTick() {
    final sim = _pageTurnSim;
    if (sim == null) return;
    final t = _pageTurn.value; // 0..1 归一化进度
    final eased = 1 - (1 - t) * (1 - t) * (1 - t);
    final pos = sim.from + (sim.to - sim.from) * eased;
    final dy = pos - _pageTurnLastValue;
    _pageTurnLastValue = pos;
    applyDragDelta(dy);
  }

  // ───────────────────────── 进度同步 ─────────────────────────

  /// 滚动/动画结束(ScrollEnd/fling 停止)时, 把 handler 的章页码静默同步回
  /// controller + 触发防抖落盘。对齐原生 onAnimStop 后 `upContent`。
  void _syncToController() {
    if (_chapterIndex == _controller.currentChapterIndex &&
        _pageInChapter == _controller.currentPageIndex) {
      return;
    }
    // 静默更新(不 notify, 避免整树 rebuild), 仅落盘。
    _controller.setCurrentPageSilent(_chapterIndex, _pageInChapter);
    _controller.scheduleProgressSave();
  }

  /// reader_view 在手势完全结束(松手且 fling 停)时调用, 兜底同步 + notify。
  void onScrollEnd() {
    _syncToController();
  }

  // ───────────────────────── 渲染辅助 ─────────────────────────

  /// 当前页(对齐原生 `textPage`)。
  TextPage? get curPage =>
      _curPages.isNotEmpty ? _curPages[_pageInChapter] : null;

  /// 当前章总页数。
  int get curChapterPageCount => _curPages.length;

  /// 当前章标题。
  String? get curChapterTitle => _controller.getChapter(_chapterIndex)?.title;
}

/// 点击翻页的目标位移容器(from→to 像素)。逐帧由 _onPageTurnTick 用
/// AnimationController 的 0..1 value 经 easeOutCubic 映射到 [from,to]。
///
/// 对齐原生 startScroll 的 LinearInterpolator —— Flutter 这里用 easeOut
/// 让点击翻页起停更自然(原生线性在 touch 交互上略生硬, 这是合理的体验优化)。
class _SmoothScrollSimulation {
  _SmoothScrollSimulation({required this.from, required this.to});
  final double from;
  final double to;
}

/// 翻页动画速度(对齐原生 ReadView.defaultAnimationSpeed = 300ms)。
const int _pageAnimSpeedMs = 300;
