import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _initAnimation(widget.controller.settings.pageAnimation);
  }

  @override
  void dispose() {
    _selectionOverlay?.remove();
    widget.controller.removeListener(_onControllerUpdate);
    _pageAnimation?.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
    if (widget.controller.settings.pageAnimation != _currentAnimType) {
      _initAnimation(widget.controller.settings.pageAnimation);
    }
  }

  PageAnimationType get _currentAnimType => widget.controller.settings.pageAnimation;

  void _initAnimation(PageAnimationType type) {
    _pageAnimation?.dispose();
    switch (type) {
      case PageAnimationType.cover:
        _pageAnimation = CoverAnimation();
        break;
      case PageAnimationType.slide:
        _pageAnimation = SlideAnimation();
        break;
      case PageAnimationType.scroll:
      case PageAnimationType.none:
        _pageAnimation = NoAnimation();
        break;
    }
    _pageAnimation!.init(this);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.updatePageSize(size);
        });

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: currentPage,
    );
  }

  Widget _buildPage(TextPage page, int index) {
    return pv.PageView(
      key: ValueKey('page_${controller.currentChapterIndex}_$index'),
      page: page,
      settings: widget.controller.settings,
      pageIndex: index,
      totalPages: widget.controller.totalPages,
      chapterTitle: widget.controller.currentChapter?.title,
      searchQuery: widget.controller.searchQuery.isNotEmpty ? widget.controller.searchQuery : null,
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
    _isDragging = true;
    _dragOffset = 0;
    _direction = PageDirection.none;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragOffset += details.delta.dx;
    if (_dragOffset < 0) {
      _direction = PageDirection.next;
    } else if (_dragOffset > 0) {
      _direction = PageDirection.prev;
    }
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
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
