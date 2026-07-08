import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/controller/reading_controller.dart';
import '../entities/text_page.dart';

/// 滚动翻页模式核心状态机, 对齐原生 legado `ScrollPageDelegate` +
/// `ContentTextView.scroll`。
///
/// ## 核心模型(务必记住)
///
/// 单一状态变量 [pageOffset] ∈ `[-pageHeight, 0]`(对齐原生
/// `ContentTextView.pageOffset`, 范围 `0 ~ -textPage.height`):
/// - `0`        → 当前页顶部对齐视口顶(显示页首)
/// - `-pageHeight` → 当前页底部对齐视口底(显示页尾)
/// - `> 0`      → 越过顶部, 需要翻到上一页(moveToPrev)
/// - `< -pageHeight` → 越过底部, 需要翻到下一页(moveToNext)
///
/// 手指拖拽 / fling 惯性 / 点击翻页 都换算成 dy 喂给 [applyDragDelta],
/// 它累加 [pageOffset], 越过 `[−pageHeight, 0]` 边界即翻页/翻章并修正偏移
/// (保持视觉连续), 到首/末页钳制 + 中止 fling(回弹)。逐字对齐原生
/// `ContentTextView.scroll(mOffset)`(ContentTextView.kt:145-177)。
///
/// ## 渲染模型 cur / next / nextPlus(对齐原生 drawPage, ⚠️ 不画 prev)
///
/// 原生 `ContentTextView.drawPage`(ContentTextView.kt:116-131)只在当前页**下方**
/// 画三页: cur / next / nextPlus(最多 3 页, 第 3 页有 `< visibleHeight` 守卫)。
/// **不画 prev 页**。向上滚时靠 [movePrev] 立即把 cur 换成原 prev, 并把
/// pageOffset 修正到 `-pageHeight + 余量`, 让新 cur 页底部出现在屏幕顶部
/// (等价于 prev 从上方滑入)。这是原生滚动翻页的灵魂 —— 只维护"向下"的页缓存。
///
/// Flutter 端由 reader_view 的 `_buildScrollContent` 用 `Transform.translate`
/// 拼接这三页(paint 阶段平移, 不触发 relayout)。本 handler 只负责数据:
/// [pageOffset] + 当前章页 + 相邻章分页(cur/next/nextPlus 的 [TextPage])。
///
/// ## offset 修正数学(视觉连续的证明, 见 [applyDragDelta] 注释)
///
/// - 向下越过底部: 先存 `pageOffset += pageHeight`(用统一页高, 因 Flutter 每页
///   都 SizedBox(height: pageHeight) 渲染为等高), 再 moveToNext 换页。
///   翻页前 next 页在 `pageOffset + pageHeight` 位置, 翻页后新 cur 页在
///   修正后的 `pageOffset` 位置 —— 两者相等 → 同页同位 → 不跳变。
/// - 向上越过顶部: 先 moveToPrev 换页, 再 `pageOffset -= pageHeight`。
///   翻页前 prev(不可见, 在上方), 翻页后新 cur 底部出现在屏幕顶。
///
/// ## 与原生差异
///
/// - 原生 fling 用 Android `Scroller.fling` + `computeScroll` 每帧驱动;
///   Flutter 用 `AnimationController` + `ClampingScrollSimulation`, 每帧
///   取 simulation 的位移 delta 喂回 [applyDragDelta]。
/// - 原生跨章靠 `pageFactory.nextPage` 章末返回 `nextChapter.getPage(0)`
///   (nextChapter 已预加载); Flutter 端用 [paginateChapterAsync] 异步预取相邻章
///   (按章加载模式下正文懒加载, 必须走异步), 就绪后 notify 刷新渲染。
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

  /// 单页**纯内容**像素高度(对齐原生 `ChapterProvider.visibleHeight`)。
  ///
  /// = `正文区总高(controller.pageSize.height) - padding.top - padding.bottom`。
  /// **不含 body padding**(对齐原生: pageOffset 在内容坐标空间运行,
  /// 页步长 = visibleHeight, padding 是视口固定条不是每页的)。
  /// 渲染层 SizedBox 用本值, 保证页与页内容连续无 padding 空白带。
  double _contentHeight = 0;
  double get contentHeight => _contentHeight;

  /// 当前逻辑章 index(滚动过程领先于 controller, ScrollEnd 才同步)。
  int _chapterIndex;
  int get chapterIndex => _chapterIndex;

  /// 当前章内的页 index。
  int _pageInChapter;
  int get pageInChapter => _pageInChapter;

  /// 当前章分页结果。
  List<TextPage> _curPages = [];
  List<TextPage> get curPages => _curPages;

  /// 上一章分页(null = 未预取/无上一章)。仅 [movePrev] 跨章时用到。
  List<TextPage>? _prevPages;
  List<TextPage>? get prevPages => _prevPages;

  /// 下一章分页(null = 未预取/无下一章/加载中)。渲染层拼 next/nextPlus 用。
  List<TextPage>? _nextPages;
  List<TextPage>? get nextPages => _nextPages;

  /// 滚动偏移, 范围 `[-contentHeight, 0]`(纯内容坐标空间)。见类注释。
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

  /// 相邻章异步预取去重(章 index → 是否在加载), 防重复请求。
  final Set<int> _adjacentLoading = {};

  /// 已 dispose 标志: 异步预取回调守卫, 避免退出后 notify。
  bool _disposed = false;

  /// 是否正在 fling(用于区分拖拽/fling, ScrollEnd 判定)。
  bool get isFlinging => _fling.isAnimating || _pageTurn.isAnimating;

  @override
  void dispose() {
    _disposed = true;
    _fling.dispose();
    _pageTurn.dispose();
    super.dispose();
  }

  // ───────────────────────── 章页数据同步 ─────────────────────────

  /// reader_view 在 LayoutBuilder 拿到正文区尺寸时调用。尺寸变化(旋转/分屏)
  /// 时重新校准 contentHeight, 并重排相邻章。
  ///
  /// [height] = 正文区总高(已扣 chrome) = controller.pageSize.height。
  /// scroll 模式正文铺满整个 pageSize.height(不减 padding), 故 contentHeight = height。
  /// 对齐原生 ContentTextView: 约束在两 divider 间, 视口 = viewHeight(无额外 padding 条),
  /// padding 体现在 TextLine.lineTop 里, pageOffset 在内容坐标空间运行。
  void updatePageHeight(double height) {
    if (height <= 0) return;
    final newContent = height;
    final changed = (newContent - _contentHeight).abs() > 0.5;
    final wasZero = _contentHeight <= 0;
    _contentHeight = newContent;
    if (changed || wasZero && _curPages.isEmpty && _controller.pages.isNotEmpty) {
      // 尺寸变 → 当前章已由 controller 重排(走 updatePageSize 防抖), 这里同步。
      _curPages = List.from(_controller.pages);
      _pageInChapter = _curPages.isEmpty
          ? 0
          : _controller.currentPageIndex.clamp(0, _curPages.length - 1);
      // 相邻章分页失效, 异步重取。
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
  ///
  /// ⚠️ **只在章真的变了 / 当前章分页为空时同步并重置 offset**。不能因
  /// `_curPages` 与 `_controller.pages` 引用不同(本类用 List.from 拷贝, 永远
  /// 非同一引用)就重置 offset —— 那会让滚动中任何 controller notify(菜单显隐、
  /// 电池更新等)把 pageOffset 清零, 造成"滚着滚着跳回页首"的 bug。
  void syncFromController() {
    final ci = _controller.currentChapterIndex;
    if (ci != _chapterIndex || _curPages.isEmpty) {
      _chapterIndex = ci;
      _curPages = List.from(_controller.pages);
      _pageInChapter = _curPages.isEmpty
          ? 0
          : _controller.currentPageIndex.clamp(0, _curPages.length - 1);
      _prevPages = null;
      _nextPages = null;
      _ensureAdjacentPages();
      _pageOffset = 0;
      notifyListeners();
    }
  }

  /// 预取相邻两章分页(对齐原生 nextChapter 预加载链)。
  ///
  /// **先同步查缓存, 命中则立即填**(全量内存模式 + 已预取过的章都走这条 O(1) 快路径,
  /// 保证连续跨章翻页/fling 不被异步等待打断); 未命中再异步加载(按章加载模式)。
  void _ensureAdjacentPages() {
    if (_chapterIndex > 0 && _prevPages == null) {
      final sync = _controller.paginateChapterPreferSync(_chapterIndex - 1);
      if (sync.isNotEmpty) {
        _prevPages = sync;
      } else {
        _loadAdjacent(_chapterIndex - 1, isPrev: true);
      }
    }
    if (_chapterIndex < _controller.totalChapters - 1 && _nextPages == null) {
      final sync = _controller.paginateChapterPreferSync(_chapterIndex + 1);
      if (sync.isNotEmpty) {
        _nextPages = sync;
      } else {
        _loadAdjacent(_chapterIndex + 1, isPrev: false);
      }
    }
  }

  Future<void> _loadAdjacent(int chapterIndex, {required bool isPrev}) async {
    if (_adjacentLoading.contains(chapterIndex)) return;
    _adjacentLoading.add(chapterIndex);
    try {
      final pages = await _controller.paginateChapterAsync(chapterIndex);
      if (_disposed) return;
      // 加载期间章可能已翻走, 只填对应槽(不覆盖当前)。
      if (chapterIndex == _chapterIndex - 1 && isPrev) {
        _prevPages = pages.isNotEmpty ? pages : null;
      } else if (chapterIndex == _chapterIndex + 1 && !isPrev) {
        _nextPages = pages.isNotEmpty ? pages : null;
      }
      notifyListeners();
    } finally {
      _adjacentLoading.remove(chapterIndex);
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
  /// 3. `pageOffset > 0` → 翻到上一页/上一章, offset 减一个页高。
  /// 4. `pageOffset < -pageHeight` → 翻到下一页/下一章, offset 加一个页高。
  ///
  /// **offset 修正与视觉连续**(对齐原生 ContentTextView.kt:167-174):
  /// 向下越过底部时, 翻页前 next 页位于 `pageOffset + pageHeight`(因 Flutter 每页
  /// SizedBox 等高), 翻页后 pageOffset 加 pageHeight, 新 cur 页(原 next)位于
  /// 修正后的 pageOffset —— 两者相等 → 同页同位 → 无跳变。
  void applyDragDelta(double dy) {
    if (_contentHeight <= 0 || _curPages.isEmpty) return;
    _pageOffset += dy;

    // 循环消化越界(对齐原生逐帧小增量; fling 大步长或测试大 dy 时单次可能越过
    // 多页, 循环翻到 pageOffset 落回 [-contentHeight, 0] 为止)。guard 限制最多翻
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
          _pageOffset -= _contentHeight;
        } else {
          _pageOffset = 0;
          _abortAnim();
          notifyListeners();
          return;
        }
        continue; // 翻页后可能仍越界, 继续消化。
      }
      // 边界4: 越过底部(pageOffset < -pageHeight) → 翻下一页/下一章; 无下一页钳制。
      if (_pageOffset < -_contentHeight) {
        final moved = hasNext && _moveToNext();
        if (moved) {
          _pageOffset += _contentHeight;
        } else {
          _pageOffset = -_contentHeight;
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
      // 跨章向后: cur → 原上一章末页, 原 cur 成为新 next, 新 prev = 上上一章。
      final oldCurPages = _curPages; // 原 cur(当前章), 即将变 next
      _chapterIndex--;
      _curPages = List.from(_prevPages!);
      _pageInChapter = _curPages.length - 1;
      _nextPages = oldCurPages; // 原当前章成为新 next(回滚时 cur→next)
      _prevPages = null;
      _ensureAdjacentPages(); // 同步缓存命中则即时填, 否则异步补 prev
      _syncToController();
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
      // 跨章向前: cur → 原下一章首页, 原 cur 成为新 prev, 新 next = 下下一章。
      final oldCurPages = _curPages; // 原 cur(当前章), 即将变 prev
      _chapterIndex++;
      _curPages = List.from(_nextPages!);
      _pageInChapter = 0;
      _prevPages = oldCurPages; // 原当前章成为新 prev(回滚时 cur→prev)
      _nextPages = null;
      _ensureAdjacentPages(); // 同步缓存命中则即时填, 否则异步补 next
      _syncToController();
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
    if (sim == null || _contentHeight <= 0) return;
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
    if (_contentHeight <= 0 || _curPages.isEmpty) return;
    // 滚动一整页 ±contentHeight。多滚 0.5px 确保 offset 越过 -contentHeight 边界
    // (applyDragDelta 用严格小于判定; 恰好 = -contentHeight 不翻页, 显示页尾)。
    final dy = next ? -(_contentHeight + 0.5) : (_contentHeight + 0.5);
    if (dy == 0) return;
    if (noAnim) {
      applyDragDelta(dy);
      _syncToController();
      return;
    }
    // 启动平滑滚动动画(对齐 startScroll: duration = speed * |dy|/viewHeight,
    // 满页 = 300ms)。用 easeOut 起停更自然。
    final distance = dy.abs();
    final durationMs = (_pageAnimSpeedMs * distance / _contentHeight)
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
  ///
  /// 章内翻页时不调用(避免高频 notify); 仅跨章时调用(原生翻章会回调 ReadBook)。
  void _syncToController() {
    if (_chapterIndex == _controller.currentChapterIndex) {
      return; // 章没变, controller 的章内页码由 ScrollEnd 统一处理。
    }
    // 静默更新(不 notify, 避免整树 rebuild), 仅落盘。
    _controller.setCurrentPageSilent(_chapterIndex, _pageInChapter);
    _controller.scheduleProgressSave();
  }

  /// reader_view 在手势完全结束(松手且 fling 停)时调用, 兜底同步 + notify。
  void onScrollEnd() {
    // 章页码都可能已领先 controller, 静默同步 + 落盘。
    if (_chapterIndex != _controller.currentChapterIndex ||
        _pageInChapter != _controller.currentPageIndex) {
      _controller.setCurrentPageSilent(_chapterIndex, _pageInChapter);
      _controller.scheduleProgressSave();
    }
  }

  // ───────────────────────── 渲染辅助(cur/next/nextPlus) ─────────────────────────

  /// 当前页(对齐原生 `textPage`)。
  TextPage? get curPage =>
      _curPages.isNotEmpty ? _curPages[_pageInChapter] : null;

  /// 下一页(对齐原生 `pageFactory.nextPage`)。
  /// 章内 = pageInChapter+1; 跨章(章末) = 下一章首页(_nextPages[0])。
  /// null = 无下一页 或 下一章未加载。
  TextPage? get nextPage {
    if (_pageInChapter < _curPages.length - 1) {
      return _curPages[_pageInChapter + 1];
    }
    // 章末: 取下一章首页(未加载则 null, 渲染层不挂载, 不阻塞当前阅读)。
    final next = _nextPages;
    if (next != null && next.isNotEmpty) return next[0];
    return null;
  }

  /// 下下页(对齐原生 `pageFactory.nextPlusPage`)。
  /// 章内 = pageInChapter+2; 跨章 = 下一章第 2 页 或 下下章首页。
  /// null = 无下下页 或 未加载。渲染层有 `offset < pageHeight` 守卫才挂载。
  TextPage? get nextPlusPage {
    if (_pageInChapter < _curPages.length - 2) {
      return _curPages[_pageInChapter + 2];
    }
    // 涉及跨章: 章末或章末前一页。
    final next = _nextPages;
    if (next == null || next.isEmpty) return null;
    // 当前章还剩 1 页(本页是倒数第二) → nextPlus 在下一章第 1 页(index 1)。
    if (_pageInChapter == _curPages.length - 2) {
      return next.length > 1 ? next[1] : null;
    }
    // 当前章末页 → nextPlus 在下下章首页(需预取下下章, 暂不支持, 返回 null)。
    // 罕见场景(末页向下滚且下一章只有1页), 渲染守卫会跳过, 不影响功能。
    return null;
  }

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
