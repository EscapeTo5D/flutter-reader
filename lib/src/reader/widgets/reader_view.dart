import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/controller/reading_controller.dart';
import '../entities/text_page.dart';
import 'page_view.dart' as pv;
import 'read_menu.dart';
import 'search_menu.dart';

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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _applySystemUI();
  }

  @override
  void dispose() {
    _selectionOverlay?.remove();
    widget.controller.removeListener(_onControllerUpdate);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onControllerUpdate() {
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = widget.controller.settings;
        final systemPadding = MediaQuery.of(context).padding;
        // 页眉/页脚显隐条件必须与 page_view.build() 完全一致, 否则预算高度
        // (喂给排版引擎的可用高度) 与实际渲染占用会错位, 导致正文与页脚重叠/留白。
        final showHeader =
            settings.hideStatusBar && !settings.headerConfig.hidden;
        final showFooter = !settings.footerConfig.hidden;
        final topInset = showHeader ? 0.0 : systemPadding.top;
        final bottomInset =
            settings.hideNavigationBar ? 0.0 : systemPadding.bottom;
        // footer 外层 Padding(top:2 + bottom:4) 来自 page_view._buildFooter
        final footerPadding = showFooter ? 6.0 : 0.0;
        final nonContentHeight = topInset +
            bottomInset +
            (showHeader ? settings.padding.headerHeight : 0) +
            (showHeader && settings.showHeaderDivider ? 0.5 : 0) +
            (showFooter && settings.showFooterDivider ? 0.5 : 0) +
            (showFooter ? settings.padding.footerHeight + footerPadding : 0);
        final size = Size(
          constraints.maxWidth - systemPadding.left - systemPadding.right,
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
