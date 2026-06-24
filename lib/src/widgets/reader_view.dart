import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../controller/reading_controller.dart';
import '../models/reading_settings.dart';
import '../models/text_page.dart';
import 'page_view.dart' as pv;
import 'read_menu.dart';
import 'search_menu.dart';
import 'page_animations/page_animation.dart';
import 'page_animations/cover_animation.dart';
import 'page_animations/slide_animation.dart';
import 'page_animations/no_animation.dart';
import 'page_animations/simulation_animation.dart';
import 'page_animations/scroll_mode_handler.dart';

class ReaderView extends StatefulWidget {
  final ReadingController controller;

  const ReaderView({super.key, required this.controller});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> with TickerProviderStateMixin {
  PageAnimation? _pageAnimation;
  PageDirection _direction = PageDirection.none;
  bool _isDragging = false;
  double _dragOffset = 0;
  Offset? _tapDownPosition;
  OverlayEntry? _selectionOverlay;
  PageAnimationType? _lastAnimType;

  final GlobalKey _curPageKey = GlobalKey();
  final GlobalKey _nextPageKey = GlobalKey();
  final GlobalKey _prevPageKey = GlobalKey();

  ui.Image? _curImage;
  ui.Image? _nextImage;
  ui.Image? _prevImage;
  Offset _simulationTouchPoint = Offset.zero;
  AnimationController? _simulationAnimController;
  bool _simulationDragCommitted = false;

  ScrollModeHandler? _scrollHandler;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _lastAnimType = _currentAnimType;
    _initAnimation(_currentAnimType);
    _applySystemUI();
  }

  @override
  void dispose() {
    _selectionOverlay?.remove();
    widget.controller.removeListener(_onControllerUpdate);
    _pageAnimation?.dispose();
    _simulationAnimController?.dispose();
    _scrollHandler?.dispose();
    _releaseImages();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _releaseImages() {
    _curImage?.dispose();
    _curImage = null;
    _nextImage?.dispose();
    _nextImage = null;
    _prevImage?.dispose();
    _prevImage = null;
  }

  void _onControllerUpdate() {
    if (_currentAnimType != _lastAnimType) {
      _initAnimation(_currentAnimType);
      _lastAnimType = _currentAnimType;
    }
    if (_currentAnimType == PageAnimationType.scroll) {
      _scrollHandler?.onPageChangedFromController();
      _applySystemUI();
      return;
    }
    setState(() {});
    _applySystemUI();
  }

  void _applySystemUI() {
    final settings = widget.controller.settings;
    final menuVisible = widget.controller.menuVisible;

    if (menuVisible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    } else if (settings.hideStatusBar && settings.hideNavigationBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (settings.hideStatusBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom]);
    } else if (settings.hideNavigationBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  PageAnimationType get _currentAnimType {
    if (widget.controller.settings.noAnimScrollPage) return PageAnimationType.none;
    return widget.controller.settings.pageAnimation;
  }

  void _initAnimation(PageAnimationType type) {
    _pageAnimation?.dispose();
    _simulationAnimController?.dispose();
    _simulationAnimController = null;
    _scrollHandler?.dispose();
    _scrollHandler = null;

    switch (type) {
      case PageAnimationType.cover:
        _pageAnimation = CoverAnimation();
        break;
      case PageAnimationType.slide:
        _pageAnimation = SlideAnimation();
        break;
      case PageAnimationType.simulation:
        _pageAnimation = SimulationAnimation();
        _simulationAnimController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        );
        _simulationAnimController!.addListener(() {
          final start = _simulationTouchPoint;
          final end = _simulationAnimTarget;
          _simulationAnimCurrentPoint = Offset(
            start.dx + (end.dx - start.dx) * _simulationAnimController!.value,
            start.dy + (end.dy - start.dy) * _simulationAnimController!.value,
          );
          setState(() {});
        });
        _simulationAnimController!.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _onSimulationAnimStop();
          }
        });
        break;
      case PageAnimationType.scroll:
        _scrollHandler = ScrollModeHandler(widget.controller);
        _scrollHandler!.onStateChanged = () {
          if (mounted) setState(() {});
        };
        _pageAnimation = NoAnimation();
        break;
      case PageAnimationType.none:
        _pageAnimation = NoAnimation();
        break;
    }
    _pageAnimation!.init(this);
  }

  Offset _simulationAnimTarget = Offset.zero;
  Offset _simulationAnimCurrentPoint = Offset.zero;
  bool _simulationAnimStarted = false;

  void _onSimulationAnimStop() {
    if (!_simulationAnimStarted) return;
    _simulationAnimStarted = false;
    final direction = _direction;
    _direction = PageDirection.none;
    _isDragging = false;
    _simulationDragCommitted = false;
    _releaseImages();
    if (direction == PageDirection.next && widget.controller.canGoNext) {
      widget.controller.nextPage();
    } else if (direction == PageDirection.prev && widget.controller.canGoPrevious) {
      widget.controller.previousPage();
    }
    setState(() {});
  }

  Future<ui.Image?> _capturePage(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return null;
      return await boundary.toImage(pixelRatio: MediaQuery.of(context).devicePixelRatio);
    } catch (_) {
      return null;
    }
  }

  void _startSimulationAnimation(Offset target) {
    _simulationAnimTarget = target;
    _simulationAnimStarted = true;
    _simulationAnimController?.reset();
    _simulationAnimController?.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = widget.controller.settings;
        final systemPadding = MediaQuery.of(context).padding;
        final showHeader = settings.hideStatusBar;
        final topInset = showHeader ? 0.0 : systemPadding.top;
        final bottomInset = settings.hideNavigationBar ? 0.0 : systemPadding.bottom;
        final nonContentHeight = topInset + bottomInset
            + (showHeader ? settings.padding.headerHeight : 0)
            + (showHeader && settings.showHeaderDivider ? 0.5 : 0)
            + (settings.showFooterDivider ? 0.5 : 0)
            + settings.padding.footerHeight;
        final size = Size(
          constraints.maxWidth - systemPadding.left - systemPadding.right,
          (constraints.maxHeight - nonContentHeight).clamp(0.0, constraints.maxHeight),
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
              if (widget.controller.menuVisible) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => widget.controller.hideMenu(),
                    child: Container(color: Colors.black12),
                  ),
                ),
                Positioned.fill(
                  child: ReadMenu(controller: widget.controller),
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

    if (_currentAnimType == PageAnimationType.scroll && _scrollHandler != null) {
      return _scrollHandler!.buildContent(context, pages, _buildPage);
    }

    if (_currentAnimType == PageAnimationType.simulation &&
        _pageAnimation is SimulationAnimation) {
      return _buildSimulationContent(pages, currentIndex);
    }

    return _buildStandardContent(pages, currentIndex);
  }

  Widget _buildSimulationContent(List<TextPage> pages, int currentIndex) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final viewSize = MediaQuery.of(context).size;

    return Stack(
      children: [
        Offstage(
          offstage: true,
          child: RepaintBoundary(
            key: _curPageKey,
            child: ClipRect(
              child: _buildPage(pages[currentIndex], currentIndex),
            ),
          ),
        ),
        if (currentIndex < pages.length - 1)
          Offstage(
            offstage: true,
            child: RepaintBoundary(
              key: _nextPageKey,
              child: ClipRect(
                child: _buildPage(pages[currentIndex + 1], currentIndex + 1),
              ),
            ),
          ),
        if (currentIndex > 0)
          Offstage(
            offstage: true,
            child: RepaintBoundary(
              key: _prevPageKey,
              child: ClipRect(
                child: _buildPage(pages[currentIndex - 1], currentIndex - 1),
              ),
            ),
          ),
        if (_isDragging &&
            _direction != PageDirection.none &&
            _curImage != null)
          Positioned.fill(
            child: (_pageAnimation! as SimulationAnimation).buildWithImages(
              context: context,
              curImage: _curImage,
              nextImage: _nextImage,
              prevImage: _prevImage,
              direction: _direction,
              touchPoint: _simulationAnimCurrentPoint,
              viewSize: viewSize,
              isCancel: false,
              devicePixelRatio: devicePixelRatio,
            ),
          )
        else
          _buildPage(pages[currentIndex], currentIndex),
      ],
    );
  }

  Widget _buildStandardContent(List<TextPage> pages, int currentIndex) {
    final currentPage = _buildPage(
      pages[currentIndex],
      currentIndex,
    );

    if (_isDragging && _pageAnimation != null && _pageAnimation is! NoAnimation) {
      final nextPage = currentIndex < pages.length - 1
          ? _buildPage(pages[currentIndex + 1], currentIndex + 1)
          : null;
      final prevPage = currentIndex > 0
          ? _buildPage(pages[currentIndex - 1], currentIndex - 1)
          : null;

      return _pageAnimation!.build(
        context: context,
        currentPage: currentPage,
        nextPage: nextPage,
        prevPage: prevPage,
        direction: _direction,
        dragProgress: _dragOffset / MediaQuery.of(context).size.width,
      );
    }

    if (_pageAnimation is NoAnimation) {
      return currentPage;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: currentPage,
    );
  }

  Widget _buildPage(TextPage page, int index) {
    final isScroll = _currentAnimType == PageAnimationType.scroll;
    return pv.PageView(
      key: ValueKey('page_${controller.currentChapterIndex}_$index'),
      page: page,
      settings: widget.controller.settings,
      pageIndex: index,
      totalPages: widget.controller.totalPages,
      chapterTitle: widget.controller.currentChapter?.title,
      bookName: widget.controller.book?.title,
      searchQuery: widget.controller.searchQuery.isNotEmpty ? widget.controller.searchQuery : null,
      useSafeArea: !isScroll,
      showChrome: !isScroll,
    );
  }

  ReadingController get controller => widget.controller;

  void _onTapDown(TapDownDetails details) {
    _tapDownPosition = details.localPosition;
  }

  void _onTapUp(TapUpDetails details) {
    if (_tapDownPosition == null) return;
    if (controller.menuVisible) return;

    if (_currentAnimType == PageAnimationType.simulation) {
      _tapDownPosition = null;
      return;
    }

    final size = MediaQuery.of(context).size;
    final action = controller.getClickAction(details.localPosition, size);
    controller.handleClickAction(action);
    _tapDownPosition = null;
  }

  void _onDragStart(DragStartDetails details) {
    if (_currentAnimType == PageAnimationType.scroll) return;
    if (_currentAnimType == PageAnimationType.simulation) {
      if (_simulationAnimController?.isAnimating == true) {
        _simulationAnimController!.stop();
      }
      _simulationAnimStarted = false;
      _releaseImages();
      _isDragging = true;
      _dragOffset = 0;
      _direction = PageDirection.none;
      _simulationDragCommitted = false;
      _simulationTouchPoint = details.localPosition;
      _simulationAnimCurrentPoint = details.localPosition;
    } else {
      _isDragging = true;
      _dragOffset = 0;
      _direction = PageDirection.none;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_currentAnimType == PageAnimationType.scroll) return;
    if (_currentAnimType == PageAnimationType.simulation) {
      _dragOffset += details.delta.dx;

      if (!_simulationDragCommitted) {
        final slop = 8.0;
        if (_dragOffset.abs() > slop) {
          _simulationDragCommitted = true;
          if (_dragOffset < 0) {
            _direction = PageDirection.next;
          } else {
            _direction = PageDirection.prev;
          }
          _captureSimulationImages();
        }
      }

      if (_simulationDragCommitted) {
        _simulationTouchPoint = details.localPosition;
        _simulationAnimCurrentPoint = details.localPosition;
        setState(() {});
      }
    } else {
      _dragOffset += details.delta.dx;
      if (_dragOffset < 0) {
        _direction = PageDirection.next;
      } else if (_dragOffset > 0) {
        _direction = PageDirection.prev;
      }
      setState(() {});
    }
  }

  Future<void> _captureSimulationImages() async {
    final pages = controller.pages;
    final currentIndex = controller.currentPageIndex;

    final curImg = await _capturePage(_curPageKey);
    if (curImg != null) {
      _curImage?.dispose();
      _curImage = curImg;
    }

    if (_direction == PageDirection.next &&
        currentIndex < pages.length - 1) {
      final nextImg = await _capturePage(_nextPageKey);
      if (nextImg != null) {
        _nextImage?.dispose();
        _nextImage = nextImg;
      }
    } else if (_direction == PageDirection.prev && currentIndex > 0) {
      final prevImg = await _capturePage(_prevPageKey);
      if (prevImg != null) {
        _prevImage?.dispose();
        _prevImage = prevImg;
      }
    }

    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (_currentAnimType == PageAnimationType.scroll) return;
    if (_currentAnimType == PageAnimationType.simulation) {
      if (!_simulationDragCommitted || _direction == PageDirection.none) {
        _isDragging = false;
        _dragOffset = 0;
        _direction = PageDirection.none;
        _simulationDragCommitted = false;
        _releaseImages();
        setState(() {});
        return;
      }

      final viewW = MediaQuery.of(context).size.width;
      double targetX;
      double targetY;

      targetY = _cornerY.toDouble();

      if (_direction == PageDirection.next) {
        targetX = _cornerX > 0 ? -0.1 : viewW + 0.1;
      } else {
        targetX = _cornerX > 0 ? viewW + 0.1 : -0.1;
      }

      _startSimulationAnimation(Offset(targetX, targetY));
    } else {
      _handleNonSimulationDragEnd();
    }
  }

  int get _cornerX {
    final x = _simulationTouchPoint.dx;
    return x <= MediaQuery.of(context).size.width / 2
        ? 0
        : MediaQuery.of(context).size.width.toInt();
  }

  int get _cornerY {
    final y = _simulationTouchPoint.dy;
    return y <= MediaQuery.of(context).size.height / 2
        ? 0
        : MediaQuery.of(context).size.height.toInt();
  }

  void _handleNonSimulationDragEnd() {
    final threshold = MediaQuery.of(context).size.width * 0.25;
    if (_dragOffset.abs() > threshold) {
      if (_direction == PageDirection.next && controller.canGoNext) {
        controller.nextPage();
      } else if (_direction == PageDirection.prev && controller.canGoPrevious) {
        controller.previousPage();
      }
    }
    _isDragging = false;
    _dragOffset = 0;
    _direction = PageDirection.none;
    setState(() {});
  }
}
