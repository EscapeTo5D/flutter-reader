import 'package:flutter/material.dart';
import '../../core/controller/reading_controller.dart';
import 'legado_icons.dart';

class ChapterListPage extends StatefulWidget {
  final ReadingController controller;

  const ChapterListPage({super.key, required this.controller});

  @override
  State<ChapterListPage> createState() => _ChapterListPageState();
}

class _ChapterListPageState extends State<ChapterListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchEdit = TextEditingController();

  /// 是否处于搜索态。对齐原生 legado TocActivity: 点搜索按钮切换为 SearchView,
  /// 搜索态下隐藏 TabLayout; 关闭恢复 Tab。仅目录 tab(0) 启用搜索。
  bool _searchMode = false;
  String _chapterQuery = '';

  /// 主体(TabBar/TabBarView/搜索框)是否已挂载。
  ///
  /// 首次 push 进入时主体不挂载, 只渲染轻量 Scaffold(让转场动画不被首帧 ~217ms
  /// 的 layout 卡死); 转场动画结束(route.animation completed)后再 setState 挂载
  /// 完整主体。对齐 ReaderView._routeReady 的同类策略。
  bool _bodyMounted = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 切到书签 tab 时若还在搜索态, 退出搜索(原生书签搜索逻辑略, 这里简化为退出)。
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _searchMode) {
        _exitSearch();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 挂一次 route 转场动画监听: 动画结束后才挂载主体(首次), 避免重活卡死转场。
    if (_routeAnimation == null) {
      final route = ModalRoute.of(context);
      final anim = route?.animation;
      if (anim != null) {
        _routeAnimation = anim;
        if (anim.isCompleted) {
          // 转场已结束(如热重载/非首次): 直接挂载。
          _bodyMounted = true;
        } else {
          anim.addStatusListener(_onRouteAnimation);
        }
      } else {
        // 非 Navigator 路由场景(测试): 直接挂载。
        _bodyMounted = true;
      }
    }
  }

  void _onRouteAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_bodyMounted) {
      setState(() => _bodyMounted = true);
      _routeAnimation?.removeStatusListener(_onRouteAnimation);
      _routeAnimation = null;
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _tabController.dispose();
    _searchFocus.dispose();
    _searchEdit.dispose();
    super.dispose();
  }

  void _enterSearch() {
    setState(() => _searchMode = true);
    // TextField 用 Visibility 常驻树里(visible 切换), 不可见时无法获焦; 切到可见后
    // 需在下一帧重新请求焦点唤起键盘。这一帧的延迟换来首次唤起省掉 ~80ms 首次 layout
    // 开销(对齐 legado SearchView 预 inflate)。
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _exitSearch() {
    setState(() {
      _searchMode = false;
      _chapterQuery = '';
      _searchEdit.clear();
    });
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // 首次进入时主体未挂载: 只渲染轻量 Scaffold, 让转场动画不被首帧 layout 卡死;
    // 转场动画结束后 _onRouteAnimation 触发 setState(_bodyMounted=true) 挂载完整主体。
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: LegadoIcons.arrowBack(size: 24, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _bodyMounted ? _buildTitle() : const SizedBox.shrink(),
        actions: _bodyMounted
            ? [
                if (!_searchMode)
                  IconButton(
                    icon: LegadoIcons.search(size: 24, color: Colors.black87),
                    tooltip: '搜索',
                    onPressed: () {
                      // 仅在目录 tab 启用搜索, 不在目录则先切过去。
                      if (_tabController.index != 0) {
                        _tabController.animateTo(0);
                      }
                      _enterSearch();
                    },
                  ),
              ]
            : null,
      ),
      body: _bodyMounted
          ? TabBarView(
              controller: _tabController,
              children: [
                _ChapterListView(controller: widget.controller, query: _chapterQuery),
                _BookmarkListView(controller: widget.controller),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  /// 标题区: TabBar 与搜索框叠放, 用 Visibility 切显隐。
  ///
  /// 对齐 legado TocActivity: SearchView 作为 menu actionView 在 Activity 启动时
  // 就 inflate 好(只是 iconified 收起), 点搜索只切 isIconified, 无首次 layout。
  // Flutter 等价: TextField 与 TabBar 都常驻挂载, 用 Visibility 切显隐。
  // Visibility(maintainState/Size/Animation: true) 保留 RenderObject 与已算好
  // 的 layout, 故 EditableText 的首次 layout 在主体挂载时(转场后, 用户已见页面)
  // 完成, 点搜索时无 ~120ms 首次 layout 开销。
  Widget _buildTitle() {
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        Visibility(
          visible: !_searchMode,
          maintainState: true,
          maintainSize: true,
          maintainAnimation: true,
          child: TabBar(
            controller: _tabController,
            // 对齐原生 TabLayout: 居中, indicator 仅随 label 宽度(非整宽), 强调色下划线。
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.black54,
            indicatorColor: accent,
            indicatorSize: TabBarIndicatorSize.label,
            tabAlignment: TabAlignment.center,
            dividerHeight: 0,
            tabs: const [
              Tab(text: '目录'),
              Tab(text: '书签'),
            ],
          ),
        ),
        Visibility(
          visible: _searchMode,
          maintainState: true,
          maintainSize: true,
          maintainAnimation: true,
          child: TextField(
            controller: _searchEdit,
            focusNode: _searchFocus,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '搜索章节标题',
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 16),
              suffixIcon: _chapterQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: LegadoIcons.close(size: 20, color: Colors.black54),
                      onPressed: _exitSearch,
                    ),
            ),
            onChanged: (v) => setState(() => _chapterQuery = v.trim()),
          ),
        ),
      ],
    );
  }
}

class _ChapterListView extends StatefulWidget {
  final ReadingController controller;
  /// 标题搜索关键词(非空时仅显示标题含该子串的章, 对齐原生 BookChapterDao.search
  /// 的 `title LIKE '%key%'`)。null/空 = 全部章。
  final String query;
  const _ChapterListView({required this.controller, this.query = ''});

  @override
  State<_ChapterListView> createState() => _ChapterListViewState();
}

class _ChapterListViewState extends State<_ChapterListView> {
  late final ScrollController _scrollController;
  late int _currentIndex;

  /// 过滤后的「章索引」列表, 缓存在 State 里, 仅在 query 变化时重算。
  ///
  /// 之所以不放在 build 里内联计算: 输入框每个字符都会触发 Page 级 setState,
  /// 内联计算会让 build 路径每次都 O(N) 扫全章标题 + 重建 ListView。提到 State
  /// 后, didUpdateWidget 比对 query, 仅 query 真变时才重扫一次。
  late List<int> _filteredIndices;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentIndex = widget.controller.currentChapterIndex;
    _filteredIndices = _computeFiltered();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant _ChapterListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _filteredIndices = _computeFiltered();
    }
  }

  /// 标题子串过滤(大小写不敏感), 对齐原生 BookChapterDao.search `title LIKE '%key%'`。
  /// query 为空 = 全部章索引。
  List<int> _computeFiltered() {
    final total = widget.controller.totalChapters;
    final q = widget.query.toLowerCase();
    if (q.isEmpty) return List<int>.generate(total, (i) => i);
    return [
      for (int i = 0; i < total; i++)
        if (widget.controller.chapterTitle(i).toLowerCase().contains(q)) i,
    ];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    // 估算行高: padding(12+12) + 14sp 文本约 20px ≈ 44, 含 1px 分割线。
    const estItemHeight = 45.0;
    final offset = (_currentIndex * estItemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (estItemHeight / 2);
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) return const SizedBox();
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // 标题/总数统一走 controller(按章加载模式下取自 chapterSource, 否则 book.chapters),
    // 避免 book.chapters 在按章加载模式下为空导致目录页空白。
    final currentTitle = widget.controller.chapterTitle(_currentIndex);
    final total = widget.controller.totalChapters;
    final q = widget.query;

    return Column(
      children: [
        Expanded(
          child: _filteredIndices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      q.isEmpty ? '暂无章节' : '未搜到章节',
                      style: const TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                  ),
                )
              : ListView.builder(
                  // 用 .builder 而非 .separated: 分隔线通过 item 内 Container 画,
                  // 避免每次 query 变重建 separator widget。
                  controller: _scrollController,
                  itemCount: _filteredIndices.length,
                  itemExtent: 45, // 固定行高: padding12+12 + 14sp(~20) + 1px 分割线
                  itemBuilder: (ctx, i) {
                    final chapterIdx = _filteredIndices[i];
                    final isCurrent = chapterIdx == _currentIndex;
                    return InkWell(
                      onTap: () {
                        widget.controller.goToChapter(chapterIdx);
                        Navigator.pop(context);
                      },
                      child: DecoratedBox(
                        // 底部 1px 分隔线(最后一项不画)。
                        decoration: BoxDecoration(
                          border: i == _filteredIndices.length - 1
                              ? null
                              : const Border(
                                  bottom: BorderSide(
                                    width: 1,
                                    color: Color(0x8FE0E0E0), // bg_divider_line
                                  ),
                                ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.controller.chapterTitle(chapterIdx),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isCurrent
                                        ? Theme.of(context).colorScheme.primary
                                        : const Color(0xDE000000), // primaryText
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                LegadoIcons.check(
                                  size: 18,
                                  color: const Color(0x8A000000), // secondaryText
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        _buildBottomInfoBar(
          context,
          currentTitle: currentTitle,
          currentIndex: _currentIndex,
          total: total,
          bottomPadding: bottomPadding,
          onScrollToCurrent: _scrollToCurrent,
          onScrollToTop: _scrollToTop,
          onScrollToBottom: _scrollToBottom,
        ),
      ],
    );
  }
}

class _BookmarkListView extends StatefulWidget {
  final ReadingController controller;
  const _BookmarkListView({required this.controller});

  @override
  State<_BookmarkListView> createState() => _BookmarkListViewState();
}

class _BookmarkListViewState extends State<_BookmarkListView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) return const SizedBox();
    final bookmarks = widget.controller.bookmarks;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (bookmarks.isEmpty) {
      return const Center(
        child: Text('暂无书签', style: TextStyle(color: Colors.black54, fontSize: 14)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            itemCount: bookmarks.length,
            separatorBuilder: (context, index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              height: 1,
              color: const Color(0x8FE0E0E0), // bg_divider_line
            ),
            itemBuilder: (ctx, i) {
              final bm = bookmarks[i];
              final chapterName = bm.chapterIndex < book.chapters.length
                  ? book.chapters[bm.chapterIndex].title
                  : '未知章节';
              return InkWell(
                onTap: () {
                  widget.controller.goToChapter(bm.chapterIndex);
                  widget.controller.goToPage(bm.pageIndex);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Color(0xDE000000)),
                      ),
                      if (bm.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bm.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0x8A000000)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: bottomPadding),
      ],
    );
  }
}

Widget _buildBottomInfoBar(
  BuildContext context, {
  required String currentTitle,
  required int currentIndex,
  required int total,
  required double bottomPadding,
  required VoidCallback onScrollToCurrent,
  required VoidCallback onScrollToTop,
  required VoidCallback onScrollToBottom,
}) {
  // 对齐原生 fragment_chapter_list.xml ll_chapter_base_info:
  // bg=bottomBackground(md_grey_50 #FAFAFA) elevation=5dp 水平 padding=10dp,
  // tv_current_chapter_info 高 36dp textSize=12sp ellipsize=middle,
  // iv_chapter_top/bottom 36×36 ic_arrow_drop_up/down tint=primaryText.
  const primaryText = Color(0xDE000000);
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFAFAFA), // md_grey_50 / bottomBackground
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, -1),
        ),
      ],
    ),
    padding: EdgeInsets.only(left: 10, right: 10, bottom: bottomPadding),
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onScrollToCurrent,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$currentTitle(${currentIndex + 1}/$total)',
                  maxLines: 1,
                  // ellipsize=middle 对齐: 保留首尾显示中间省略。
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: primaryText),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: InkWell(
              onTap: onScrollToTop,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: LegadoIcons.arrowDropUp(size: 24, color: primaryText),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: InkWell(
              onTap: onScrollToBottom,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: LegadoIcons.arrowDropDown(size: 24, color: primaryText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
