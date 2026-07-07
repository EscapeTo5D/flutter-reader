part of 'reader_view.dart';

/// 仿真翻页(simulation 模式)的状态与手势/动画驱动。
///
/// 贝塞尔卷曲翻页。状态字段(触摸点/拖拽角/三页位图/动画起止)与 7 个驱动方法
/// 在此; 卷曲几何由独立的 [SimGeometry] 计算, 绘制由 [SimulationPainter] 承担。
/// build 方法里的 RepaintBoundary 截图层 + SimulationPainter 覆盖层保留在主类
/// (reader_view.dart), 因为它们是 pageStack 的核心组成。
///
/// 对齐原生 legado `SimulationPageDelegate`。
///
/// 下列 abstract 成员是本 mixin 对宿主 _ReaderViewState 的依赖契约
/// (翻页动画骨架的共享状态/方法, 定义在主类, part 同 library 故 private 互通):
mixin _SimulationMixin on State<ReaderView> {
  // --- 宿主提供的翻页骨架状态(abstract getter, 由 _ReaderViewState 实现) ---
  AnimationController get _pageAnim;
  Animation<double>? get _pageAnimCurved;
  set _pageAnimCurved(Animation<double>? value);
  _PageDirection get _animDir;
  bool get _isCancel;
  int get _animGen;
  ReadingController get controller;

  // --- 宿主提供的翻页骨架方法(abstract, 由 _ReaderViewState 实现) ---
  void _attachAnimListener(double from, double to, void Function() listener);
  void _resetAnimState();
  PeekInfo? _resolveTarget(_PageDirection dir);
  void _onAnimTick();
  /// 仿真翻页的二维触摸点(对齐原生 mTouchX/mTouchY)。slide 模式仍用 _dragOffset。
  /// Y 由 _onDragUpdate 的锁边逻辑约束(对齐原生 onTouch MOVE 173-183)。
  Offset _simTouch = Offset.zero;

  /// 仿真翻页的拖拽角(由 down 时的触摸点经 calcCornerXY 算出)。
  SimCorner? _simCorner;

  /// 仿真翻页三页位图缓存(对齐原生 SimulationPageDelegate.setBitmap 截三页)。
  /// 由 RepaintBoundary.toImage 异步截图填充, _simBitmapsReady 标记就绪。
  ui.Image? _simCur;
  ui.Image? _simNext;
  ui.Image? _simPrev;

  /// 截图就绪标志。未就绪时 SimulationPainter 走纯色降级(卷曲形状仍可见)。
  /// 通过 painter 的 image null 判断即可驱动降级, 此字段用于调试/防御性判断。
  // ignore: unused_field
  bool _simBitmapsReady = false;

  /// 三个 RepaintBoundary 的 key, 用于截图(toImage)。
  final GlobalKey _curBoundaryKey = GlobalKey();
  final GlobalKey _nextBoundaryKey = GlobalKey();
  final GlobalKey _prevBoundaryKey = GlobalKey();

  /// 手势按下点(逻辑像素), 用于仿真翻页的 touchY 锁边判定(对齐原生 startY)。
  Offset _simStartLocal = Offset.zero;

  /// 仿真动画的起止触摸点(由 _onDragEnd/_turnByAnim 设置, _onSimAnimTick 插值)。
  Offset? _simAnimFrom;
  Offset? _simAnimTo;

  /// 拖拽方向首次确定时: 计算拖拽角 + 异步截图三页(对齐原生 setBitmap)。
  void _initSimForDrag(Offset localPosition) {
    final size = MediaQuery.of(context).size;
    final isNext = _animDir == _PageDirection.next;
    final startX = _simStartLocal.dx;
    final startY = _simStartLocal.dy;
    // 对齐原生 setDirection: PREV 不出现对角(强制底角); NEXT 仅左半屏拖拽才设对角。
    if (isNext) {
      if (size.width / 2 > startX) {
        _simCorner = SimGeometry.calcCornerXY(
            size.width - startX, startY, size.width, size.height);
      } else {
        // 右半屏 NEXT: 用 down 点本身算角(默认走右下角)。
        _simCorner = SimGeometry.calcCornerXY(
            startX, startY, size.width, size.height);
      }
    } else {
      // PREV: 强制 touchY = viewHeight(底角, 不对角), 对齐原生 setDirection。
      if (startX > size.width / 2) {
        _simCorner = SimGeometry.calcCornerXY(
            startX, size.height, size.width, size.height);
      } else {
        _simCorner = SimGeometry.calcCornerXY(
            size.width - startX, size.height, size.width, size.height);
      }
    }
    // 截图必须延迟到 PostFrame: 方向锁定时 _onDragUpdate 调了 _resolveTarget 兜底,
    // 可能刚把 _nextCache/_prevCache 从 null 回填 → nextWidget 从 SizedBox.shrink 换成
    // 带 RepaintBoundary 的真实页。但 widget 树 rebuild 要等下一帧, 若立即 toImage,
    // _nextBoundaryKey.currentContext 仍是 null → boundary2=null → 跳过 _simNext 截图
    // → NEXT 翻页底层露出的目标页 painter 降级成纯背景色(空白页 bug)。
    //
    // 与 _turnByAnim 的 wasAborting 分支同源(见其 906-915 注释): Flutter
    // RepaintBoundary.toImage 截的是上一帧 paint 的 layer 缓存, setState 后必须等
    // 下一帧才截到新树。拖拽方向锁定首帧卷曲极小(~8dp touch slop), painter 在
    // curImage==null 时透明降级、底层 pageStack 透出当前页, 1 帧延迟肉眼无感。
    //
    // 代际守护: 捕获本次手势的 _animGen, PostFrame 回调时若 gen 已变(松手/起新手势/
    // abort 都会 _animGen++), _captureSimBitmaps 内部 gen 检查自动放弃, 不交错覆盖。
    final gen = _animGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && gen == _animGen) {
        _captureSimBitmaps(gen: gen);
      }
    });
  }

  /// 更新仿真触摸点, 应用 touchY 锁边(对齐原生 onTouch MOVE 173-183):
  /// - startY 在中部(viewH/3 ~ 2·viewH/3) 或方向=PREV → touchY 锁到底边 viewH
  /// - startY 在上 1/3~1/2 且 NEXT → touchY 锁到顶 1
  void _updateSimTouch(Offset localPosition) {
    final size = MediaQuery.of(context).size;
    final startY = _simStartLocal.dy;
    var ty = localPosition.dy;
    final isNext = _animDir == _PageDirection.next;
    if ((startY > size.height / 3 && startY < size.height * 2 / 3) || !isNext) {
      ty = size.height;
    }
    if (startY > size.height / 3 &&
        startY < size.height / 2 &&
        isNext) {
      ty = 1.0;
    }
    _simTouch = Offset(localPosition.dx, ty);
  }

  /// 异步截图三页 RepaintBoundary → ui.Image(对齐原生 setBitmap)。
  ///
  /// 返回 `Future<bool>`: true=截图成功, false=失败(boundary 为空/异常)或已失效。
  /// **点击翻页**需 await 它完成后再启动落地动画, 否则截图未就绪的前几帧 painter
  /// 在 curImage==null 时整体不画(透明), 覆盖层透明期间底层静止 pageStack 显示当前页
  /// (不闪), 但动画已走了一段, 截图回来后卷曲"突然出现"会有跳跃感。
  /// **拖拽翻页**可 fire-and-forget: 用户手指按下到方向确定(~8dp 滑动)有几帧时间,
  /// 截图通常已就绪; 且 painter 透明降级底层显示当前页, 无闪烁。
  ///
  /// [gen] 调用方在调用前捕获的 `_animGen`(本次手势的代际号)。**连点/连拖竞态修复**:
  /// 每个 `await toImage` 后检查 `gen != _animGen` —— 若期间 abort/起新手势已让
  /// `_animGen++`, 立即 dispose 本批刚截的 image、返回 false、**不写回字段**。这样:
  /// (1) abort 后 pending 的截图不会把 image 回填进字段(C3); (2) 并发触发的多次截图
  /// 各自带自己的 gen, 早一代的 future 完成时 gen 已失效, 自动放弃, 不交错覆盖(C1)。
  /// 赋值前还 dispose 旧 image, 防止覆盖丢失造成泄漏(C1 的资源累积)。
  Future<bool> _captureSimBitmaps({required int gen}) async {
    _simBitmapsReady = false;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final boundary1 = _curBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    final boundary2 = _nextBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    final boundary3 = _prevBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary1 == null) return false;
    try {
      // 逐张截图, 每张 await 后做代际检查: 若期间 abort/起手新手势(_animGen 已变),
      // 立即 dispose 本批刚截的 image 并返回 false, 不写回字段(对齐原生同步语义:
      // 截图进行中被打断, 这批图作废, 由新一次手势重新截)。
      final cur = await boundary1.toImage(pixelRatio: ratio);
      if (gen != _animGen) {
        cur.dispose();
        return false;
      }
      ui.Image? next;
      if (boundary2 != null) {
        next = await boundary2.toImage(pixelRatio: ratio);
        if (gen != _animGen) {
          cur.dispose();
          next.dispose();
          return false;
        }
      }
      ui.Image? prev;
      if (boundary3 != null) {
        prev = await boundary3.toImage(pixelRatio: ratio);
        if (gen != _animGen) {
          cur.dispose();
          next?.dispose();
          prev.dispose();
          return false;
        }
      }
      // 全部成功且代际未变 → 赋值前 dispose 旧 image(防泄漏)。
      _simCur?.dispose();
      _simCur = cur;
      if (next != null) {
        _simNext?.dispose();
        _simNext = next;
      }
      if (prev != null) {
        _simPrev?.dispose();
        _simPrev = prev;
      }
      _simBitmapsReady = true;
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      // 截图失败不阻塞, painter 在 curImage==null 时透明降级继续。
      debugPrint('sim toImage failed: $e');
      return false;
    }
  }

  /// 启动仿真翻页动画: 从松手时的 touch 点滑动到目标点(翻页落地或回弹)。
  ///
  /// 对齐原生 `onAnimStart`(`SimulationPageDelegate.kt:208-238`) 的 dx/dy 计算:
  /// - shouldCommit=true(翻页落地): touch 推到对边
  /// - shouldCommit=false(回弹): touch 拉回 corner 同侧原位
  /// 用 AnimationController + Tween 插值 _simTouch, 每帧 _onSimAnimTick 重绘。
  void _startSimAnim({required bool shouldCommit}) {
    final size = MediaQuery.of(context).size;
    final cornerX = _simCorner?.cornerX ?? size.width;
    final cornerY = _simCorner?.cornerY ?? size.height;
    final isNext = _animDir == _PageDirection.next;
    var fromX = _simTouch.dx;
    var fromY = _simTouch.dy;
    if (fromX == 0) fromX = 0.1;
    if (fromY == 0) fromY = 0.1;

    double dx;
    double dy;
    if (!shouldCommit) {
      // 回弹: 拉回原位(corner 同侧)。
      if (cornerX > 0 && isNext) {
        dx = size.width - fromX;
      } else {
        dx = -fromX;
      }
      if (!isNext) {
        dx = -(size.width + fromX);
      }
      dy = cornerY > 0 ? size.height - fromY : -fromY;
    } else {
      // 翻页: 推到对边。
      if (cornerX > 0 && isNext) {
        dx = -(size.width + fromX);
      } else {
        dx = size.width - fromX;
      }
      dy = cornerY > 0 ? size.height - fromY : (1 - fromY);
    }
    _simAnimFrom = Offset(fromX, fromY);
    _simAnimTo = Offset(fromX + dx, fromY + dy);

    // 时长按原生公式 speed * |dx| / viewWidth, 满页约 300ms。
    final durationMs = (_pageAnimSpeedMs * dx.abs() / size.width)
        .round()
        .clamp(1, _pageAnimSpeedMs * 2);
    _pageAnim.duration = Duration(milliseconds: durationMs);
    _attachAnimListener(0, 1, _onSimAnimTick);
    _pageAnim.forward(from: 0);
  }

  /// 仿真动画逐帧: 用 controller value 在 _simAnimFrom → _simAnimTo 间线性插值 touch。
  void _onSimAnimTick() {
    final v = _pageAnimCurved?.value ?? 0;
    final from = _simAnimFrom;
    final to = _simAnimTo;
    if (from != null && to != null) {
      _simTouch = Offset(
        from.dx + (to.dx - from.dx) * v,
        from.dy + (to.dy - from.dy) * v,
      );
    }
    if (mounted) setState(() {});
  }

  /// 清空仿真翻页临时状态(位图缓存保留供下次复用, 仅重置 touch/corner/动画插值)。
  void _resetSimState() {
    _simCorner = null;
    _simTouch = Offset.zero;
    _simAnimFrom = null;
    _simAnimTo = null;
    _simBitmapsReady = false;
    // 释放位图避免内存累积(下次拖拽会重截)。
    _simCur?.dispose();
    _simNext?.dispose();
    _simPrev?.dispose();
    _simCur = null;
    _simNext = null;
    _simPrev = null;
  }

  /// 中断动画并按当前方向提交(对齐原生 HorizontalPageDelegate.abortAnim)。
  /// 原生: scroller 运行中且 !isCancel → fillPage 提交。
  void _abortAndCommit() {
    if (_pageAnim.isAnimating) _pageAnim.stop();
    final old = _pageAnimCurved;
    if (old != null) {
      old.removeListener(_onAnimTick);
      old.removeListener(_onSimAnimTick);
      _pageAnimCurved = null;
    }
    final dir = _animDir;
    final target = _resolveTarget(dir);
    final wasCancel = _isCancel;
    // ⚠️ 时序契约: _resetAnimState 会 _animGen++, 这正是让任何 pending 的
    // _captureSimBitmaps future 失效的关键(改动 1 的代际检查)。
    // 顺序必须是先 _resetAnimState(动画+代际) 再 _resetSimState(dispose 位图),
    // 反了会 dispose painter 正在用的 image。
    _resetAnimState();
    _resetSimState();
    if (!wasCancel && target != null) {
      controller.commitTurn(target);
    } else if (mounted) {
      setState(() {});
    }
  }
}
