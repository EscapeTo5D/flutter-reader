import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/content_processor.dart';
import '../../core/controller/reading_controller.dart';
import '../../core/models/reading_settings.dart';
import '../../core/storage/search_result.dart';
import 'legado_icons.dart';

/// 书内全文搜索页(对齐原生 legado `SearchContentActivity`)。
///
/// 流程:
/// 1. 从 [ReadingController.readMenu] 的搜索 FAB push 本页。
/// 2. 顶部 SearchView 输入关键词 → 异步全书正文搜索(流式增量追加, 可取消)。
/// 3. 结果项: 第一行章节名(textAccentColor) + 第二行上下文片段(关键词高亮)。
/// 4. 点结果 → `Navigator.pop(SearchResultBrowseData)` 回带整份结果 + 选中索引
///    → 调用方调 `ReadingController.enterSearchBrowse` 进入浏览态。
///
/// 数据源(对齐原生 `SearchContentActivity.startContentSearch` 的
/// `isLocalBook/cacheChapterNames` 判断): **只搜本地缓存章节**。
/// - 按章加载模式: `repository.getBookChapters(bookId)` 一次拿全书缓存。
/// - 全量内存模式(无 repository): 遍历 `controller.book.chapters`。
/// 未缓存章节跳过(对齐原生行为)。
///
/// 搜索偏移关键: 在 `ContentProcessor.getContent` 预处理后的 `textList.join('\n')`
/// 字符串里做 `indexOf`, 得到的偏移直接同源于 `TextLine.chapterPosition`,
/// 跳转时喂 `pageIndexForCharOffset` 即可落页(与朗读 TextSlicer 同源策略一致)。
class SearchContentPage extends StatefulWidget {
  final ReadingController controller;

  /// 预填搜索词(对齐原生 Intent extra `searchWord`)。来自文本选择菜单等场景。
  final String? initialQuery;

  const SearchContentPage({
    super.key,
    required this.controller,
    this.initialQuery,
  });

  @override
  State<SearchContentPage> createState() => _SearchContentPageState();
}

class _SearchContentPageState extends State<SearchContentPage> {
  final TextEditingController _editController = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// 流式结果列表(每搜完一章增量追加)。
  List<ReaderSearchResult> _results = const [];

  /// 搜索代际: 每次新搜索自增, 后台循环检查, 不等则中止(取消旧搜索)。
  int _searchGen = 0;

  /// 是否正在搜索(控制进度条 + 停止 FAB)。
  bool _searching = false;

  /// 搜索完成(无论有无结果), 控制空态提示。
  bool _searchDone = false;

  /// 本次查询关键词(空态文案 + 结果回带用)。
  String _query = '';

  /// 已搜章数 / 总章数(进度提示, 对齐原生 RefreshProgressBar)。
  int _searchedChapters = 0;
  int _totalChapters = 0;

  /// 主体是否已挂载(转场动画结束后才挂, 避免首帧 layout 卡死转场,
  /// 参照 ChapterListPage._bodyMounted 同款策略)。
  bool _bodyMounted = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _editController.text = widget.initialQuery!;
      // 预填词时自动发起搜索(对齐原生 openSearchActivity 带 searchWord 即搜)。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startSearch(_editController.text);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeAnimation == null) {
      final route = ModalRoute.of(context);
      final anim = route?.animation;
      if (anim != null) {
        _routeAnimation = anim;
        if (anim.isCompleted) {
          _bodyMounted = true;
        } else {
          anim.addStatusListener(_onRouteAnimation);
        }
      } else {
        _bodyMounted = true;
      }
    }
  }

  void _onRouteAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_bodyMounted) {
      setState(() => _bodyMounted = true);
      // 主体挂载后, 若有预填词且未自动聚焦过, 聚焦搜索框。
      if (widget.initialQuery == null) {
        _focus.requestFocus();
      }
      _routeAnimation?.removeStatusListener(_onRouteAnimation);
      _routeAnimation = null;
    }
  }

  @override
  void dispose() {
    _searchGen++; // 中止任何进行中的搜索。
    _editController.dispose();
    _focus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 发起全书正文搜索(异步 + 流式 + 可取消)。
  ///
  /// 对齐原生 `SearchContentViewModel.startContentSearch`:
  /// - 异步遍历每章, 每搜完一章增量追加结果到列表(UI 实时增长)。
  /// - 代际标志 [_searchGen] 实现取消: 新搜索/退出页面时自增, 旧循环检测到不等即停。
  /// - 每章跑 `ContentProcessor.getContent` 预处理, 在预处理后的字符串里 indexOf,
  ///   偏移直接同源于 chapterPosition。
  Future<void> _startSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final gen = ++_searchGen;
    setState(() {
      _query = q;
      _results = const [];
      _searching = true;
      _searchDone = false;
      _searchedChapters = 0;
    });

    final controller = widget.controller;
    final book = controller.book;
    if (book == null) {
      _finishSearch(gen);
      return;
    }

    // 取全书章节正文。优先本地缓存(repository.getBookChapters),
    // 退化到内存(book.chapters)。对齐原生只搜已缓存章节。
    final List<({int index, String title, String content})> chapters =
        await _loadAllChapters(book.id);
    if (gen != _searchGen || !mounted) return; // 取消/退出

    _totalChapters = chapters.length;
    final allResults = <ReaderSearchResult>[];
    final textIndent = controller.settings.textIndent;

    for (var i = 0; i < chapters.length; i++) {
      // 取消检查: 代际变了(新搜索/dispose)立即中止。
      if (gen != _searchGen || !mounted) return;
      final ch = chapters[i];
      // 预处理(与排版引擎/朗读同源管线)。
      final processed = ContentProcessor.getContent(
        title: ch.title,
        content: ch.content,
        bookName: book.title,
        textIndent: textIndent,
      ).textList.join('\n');

      // 循环 indexOf 找出本章所有命中(对齐原生 searchPosition 普通字符串分支)。
      final hits = _findAllHits(processed, q, ch.index, ch.title);
      if (hits.isNotEmpty) {
        allResults.addAll(hits);
        // 流式增量: 每章有命中就刷新 UI(对齐原生 adapter.addItems)。
        if (gen == _searchGen && mounted) {
          setState(() {
            _results = List.unmodifiable(allResults);
          });
        }
      }
      if (gen == _searchGen && mounted) {
        setState(() => _searchedChapters = i + 1);
      }
      // 让出微任务, 避免 CPU 密集循环长时间占用 event loop 卡 UI。
      await Future<void>.delayed(Duration.zero);
    }

    _finishSearch(gen);
  }

  void _finishSearch(int gen) {
    if (gen != _searchGen || !mounted) return;
    setState(() {
      _searching = false;
      _searchDone = true;
    });
  }

  /// 取全书章节正文(本地缓存优先, 对齐原生 isLocalBook/cacheChapterNames)。
  ///
  /// - repository 非 null: `getBookChapters` 一次拿全书缓存(二次打开命中)。
  /// - repository null(纯内存): 遍历 `book.chapters`。
  /// 返回的 content 是**原始**正文(未经 ContentProcessor), 搜索时再预处理。
  Future<List<({int index, String title, String content})>> _loadAllChapters(
    String bookId,
  ) async {
    final controller = widget.controller;
    final repo = controller.repository;
    if (repo != null) {
      final cached = await repo.getBookChapters(bookId);
      return [
        for (final c in cached)
          (index: c.chapterIndex, title: c.title, content: c.content),
      ];
    }
    // 纯内存退化: book.chapters。
    final book = controller.book;
    if (book == null) return const [];
    return [
      for (var i = 0; i < book.chapters.length; i++)
        (
          index: i,
          title: book.chapters[i].title,
          content: book.chapters[i].content,
        ),
    ];
  }

  /// 在预处理后的章节正文里找出所有命中(对齐原生 searchPosition)。
  ///
  /// [processed] 是 ContentProcessor 输出的 `textList.join('\n')`。
  /// [chapterIndex]/[chapterTitle] 用于结果项展示与跳转。
  /// 返回的 [ReaderSearchResult.charOffsetInChapter] 直接同源于 chapterPosition。
  static List<ReaderSearchResult> _findAllHits(
    String processed,
    String query,
    int chapterIndex,
    String chapterTitle,
  ) {
    final results = <ReaderSearchResult>[];
    if (query.isEmpty || processed.isEmpty) return results;
    var from = 0;
    while (true) {
      final idx = processed.indexOf(query, from);
      if (idx < 0) break;
      // 上下文片段: 关键词前后各取约 20 字(对齐原生 getResultAndQueryIndex)。
      const contextRadius = 20;
      final snippetStart = (idx - contextRadius).clamp(0, processed.length);
      final snippetEnd =
          (idx + query.length + contextRadius).clamp(0, processed.length);
      final snippet = processed.substring(snippetStart, snippetEnd);
      results.add(ReaderSearchResult(
        query: query,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        snippet: snippet.replaceAll('\n', ' '),
        queryIndexInSnippet: idx - snippetStart,
        charOffsetInChapter: idx,
      ));
      from = idx + query.length;
    }
    return results;
  }

  /// 点结果: 回带数据 pop(对齐原生 openSearchResult → setResult + finish)。
  void _onTapResult(int index) {
    if (_results.isEmpty) return;
    Navigator.of(context).pop(SearchResultBrowseData(_results, index));
  }

  @override
  Widget build(BuildContext context) {
    final palette = _SearchPagePalette.of(widget.controller.settings);
    // 转场动画期间只渲染轻量 Scaffold, 避免首帧 layout 卡死转场。
    if (!_bodyMounted) {
      return Scaffold(
        backgroundColor: palette.surface,
        appBar: AppBar(
          backgroundColor: palette.surface,
          foregroundColor: palette.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: LegadoIcons.arrowBack(color: palette.onSurface),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text('搜索', style: TextStyle(color: palette.onSurface)),
        ),
        body: const SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: _buildSearchAppBar(palette),
      body: _buildBody(palette),
      // 右下角"停止搜索"mini FAB(对齐原生 fb_stop, 搜索中显示)。
      floatingActionButton: _searching
          ? FloatingActionButton.small(
              heroTag: 'search_stop',
              onPressed: () {
                // 中止: 自增代际, 旧循环检测到即停。
                setState(() {
                  _searchGen++;
                  _searching = false;
                  _searchDone = true;
                });
              },
              backgroundColor: palette.fabBackground,
              foregroundColor: palette.onSurfaceMedium,
              elevation: 2,
              child: LegadoIcons.stop(size: 20, color: palette.onSurfaceMedium),
            )
          : null,
    );
  }

  /// 顶部搜索栏(对齐原生 `view_search.xml` + `bg_searchview.xml`)。
  ///
  /// 原生 SearchView: 30dp 高、`bg_searchview`(35dp 胶囊圆角 + #10000000 6% 灰背景
  /// + 0.5dp 同色描边)、14sp 字号、hint="搜索"、submit 按钮(magnifier)在右侧。
  /// `contentInsetRight=24dp` 是 Toolbar 的右侧内缩, 这里用 title 的 right padding 等价。
  PreferredSizeWidget _buildSearchAppBar(_SearchPagePalette palette) {
    return AppBar(
      backgroundColor: palette.surface,
      foregroundColor: palette.onSurface,
      elevation: 0,
      leading: IconButton(
        icon: LegadoIcons.arrowBack(color: palette.onSurface),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Padding(
        // 对齐原生 Toolbar contentInsetRight=24dp。
        padding: const EdgeInsets.only(right: 24),
        child: TextField(
          controller: _editController,
          focusNode: _focus,
          // 对齐原生 SearchView textView.setTextSize(14f)。
          style: TextStyle(color: palette.onSurface, fontSize: 14),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            // 对齐原生 SearchView defaultQueryHint = "搜索"。
            hintText: '搜索',
            hintStyle: TextStyle(color: palette.onSurfaceDisabled, fontSize: 14),
            filled: true,
            // 搜索框背景: 白天用 6% 黑(#10000000), 夜晚态反相 6% 白。
            fillColor: palette.searchFieldFill,
            isDense: true,
            // 对齐原生 SearchView 30dp 高: 14sp 文字垂直居中 + 紧凑 padding。
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            // 对齐原生 bg_searchview.xml corners radius=35dp(胶囊形)。
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(35),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(35),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(35),
              borderSide: BorderSide.none,
            ),
            // 对齐原生 SearchView isSubmitButtonEnabled = true: 右侧 submit 按钮。
            suffixIcon: IconButton(
              icon: LegadoIcons.search(size: 20, color: palette.onSurfaceMedium),
              onPressed: () => _startSearch(_editController.text),
            ),
          ),
          onSubmitted: (q) => _startSearch(q),
        ),
      ),
    );
  }

  Widget _buildBody(_SearchPagePalette palette) {
    return Column(
      children: [
        // 进度条(搜索中显示, 对齐原生 RefreshProgressBar)。
        if (_searching)
          LinearProgressIndicator(
            value: _totalChapters > 0
                ? (_searchedChapters / _totalChapters).clamp(0.0, 1.0)
                : null,
            minHeight: 2,
            backgroundColor: palette.progressTrack,
          ),
        Expanded(child: _buildResultList(palette)),
        // 底部信息栏(对齐原生 ll_search_base_info: 36dp + 结果数 + 回顶/回底箭头)。
        _buildBottomInfoBar(palette),
      ],
    );
  }

  /// 底部信息栏(对齐原生 `activity_search_content.xml` 的 `ll_search_base_info`)。
  ///
  /// 原生: 高 36dp, 左侧 `tv_current_search_info`(结果数, 12sp), 右侧两个箭头
  /// ImageView(回顶 `ic_arrow_drop_up` / 回底 `ic_arrow_drop_down`)。
  Widget _buildBottomInfoBar(_SearchPagePalette palette) {
    return Container(
      height: 36,
      color: palette.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // 对齐原生文案 "搜索结果: N"(搜索中显示进度)。
              _results.isEmpty && !_searching
                  ? ''
                  : _searching
                      ? '搜索中... ${_results.length} ($_searchedChapters/$_totalChapters)'
                      : '搜索结果: ${_results.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.onSurface, fontSize: 12),
            ),
          ),
          // 回顶箭头(对齐原生 iv_search_content_top)。
          if (_results.isNotEmpty)
            _buildArrowButton(
              LegadoIcons.arrowDropUp(size: 24, color: palette.onSurface),
              () => _scrollController.jumpTo(0),
            ),
          // 回底箭头(对齐原生 iv_search_content_bottom)。
          if (_results.isNotEmpty)
            _buildArrowButton(
              LegadoIcons.arrowDropDown(size: 24, color: palette.onSurface),
              () => _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent),
            ),
        ],
      ),
    );
  }

  Widget _buildArrowButton(Widget icon, VoidCallback onTap) {
    return SizedBox(
      width: 36,
      height: double.infinity,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildResultList(_SearchPagePalette palette) {
    if (_results.isEmpty) {
      // 空态。
      if (_searching) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '搜索中...',
              style: TextStyle(color: palette.onSurfaceDisabled),
            ),
          ),
        );
      }
      if (_searchDone && _query.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '未找到 "$_query"\n(仅搜索已缓存章节)',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.onSurfaceDisabled),
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '输入关键词搜索全书内容',
            style: TextStyle(color: palette.onSurfaceDisabled),
          ),
        ),
      );
    }
    // accent 色用 effective*: 夜晚态切到 night accent(#FE4D55), 白天用 day accent。
    final accentColor = widget.controller.settings.effectiveTextAccentColor;
    final currentChapter = widget.controller.currentChapterIndex;
    // 对齐原生 item: padding 12dp, 高度 wrap_content(无 itemExtent)。
    // 当前章加粗规则: 对齐原生 isFakeBoldText —— 整个 item(章节名 + 片段)加粗,
    // 非当前章正常。原生是对整个 TextView 设 isFakeBoldText, 这里通过 weight 传递。
    return ListView.builder(
      controller: _scrollController,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final isCurrentChapter = r.chapterIndex == currentChapter;
        final baseWeight = isCurrentChapter ? FontWeight.w500 : FontWeight.w400;
        return InkWell(
          onTap: () => _onTapResult(index),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行: 章节名(accent 色)。
                Text(
                  r.chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: accentColor,
                    fontWeight: baseWeight,
                  ),
                ),
                const SizedBox(height: 4),
                // 第二行: 上下文片段(关键词高亮 accent 色, 其余深灰)。
                _buildSnippet(r, accentColor, baseWeight, palette),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 上下文片段渲染: 关键词用 accent 色, 其余用 textColor(对齐原生 getHtmlCompat)。
  /// [baseWeight] 透传当前章加粗规则(对齐原生 isFakeBoldText 整 item 加粗)。
  Widget _buildSnippet(
    ReaderSearchResult r,
    Color accentColor,
    FontWeight baseWeight,
    _SearchPagePalette palette,
  ) {
    final text = r.snippet;
    final qStart = r.queryIndexInSnippet;
    final qEnd = qStart + r.query.length;
    // 越界保护(理论上不会, 但 snippet 截断/换行替换后需防御)。
    if (qStart < 0 ||
        qEnd > text.length ||
        qStart >= text.length ||
        qEnd <= qStart) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: palette.snippetText,
          fontWeight: baseWeight,
        ),
      );
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: palette.snippetText,
          fontWeight: baseWeight,
        ),
        children: [
          TextSpan(text: text.substring(0, qStart)),
          TextSpan(
            text: text.substring(qStart, qEnd),
            // 关键词始终用 accent 色高亮(原生 hit word colorTextForHtml(accentColor))。
            style: TextStyle(color: accentColor, fontWeight: baseWeight),
          ),
          TextSpan(text: text.substring(qEnd)),
        ],
      ),
    );
  }
}

/// 搜索结果页色板(对齐 legado 夜间 Activity 主题)。
///
/// 独立路由(Scaffold 自带背景), 与阅读正文的 settings.bg/text 色组解耦:
/// 白天走 Material 浅色(白底深灰字); 夜晚态走深色。
/// 仅 [ReadingSettings.isNightTheme] 驱动切换, 在 build 入口一次性算出。
class _SearchPagePalette {
  final Color surface;          // Scaffold/AppBar/底部栏背景
  final Color fabBackground;    // 停止搜索 FAB 背景
  final Color onSurface;        // 主文字(返回箭头/标题/搜索框文字/底部信息)
  final Color onSurfaceMedium;  // 次文字(搜索按钮图标/FAB 图标)
  final Color onSurfaceDisabled;// 弱文字(hint/空态)
  final Color snippetText;      // 结果片段上下文文字(深灰, 比主文字略弱)
  final Color searchFieldFill;  // 搜索框填充(白天 6% 黑, 夜晚 6% 白)
  final Color progressTrack;    // 进度条底色

  const _SearchPagePalette._({
    required this.surface,
    required this.fabBackground,
    required this.onSurface,
    required this.onSurfaceMedium,
    required this.onSurfaceDisabled,
    required this.snippetText,
    required this.searchFieldFill,
    required this.progressTrack,
  });

  static const _SearchPagePalette _light = _SearchPagePalette._(
    surface: Colors.white,
    fabBackground: Color(0xFFE0E0E0),
    onSurface: Colors.black87,
    onSurfaceMedium: Colors.black54,
    onSurfaceDisabled: Colors.black38,
    snippetText: Color(0xFF666666),
    searchFieldFill: Color(0x10000000), // bg_searchview.xml transparent10
    progressTrack: Color(0xFFE0E0E0),
  );

  static const _SearchPagePalette _dark = _SearchPagePalette._(
    surface: Color(0xFF1F1F1F),
    fabBackground: Color(0xFF3A3A3A),
    onSurface: Color(0xFFE0E0E0),
    onSurfaceMedium: Color(0xFFAAAAAA),
    onSurfaceDisabled: Color(0xFF666666),
    snippetText: Color(0xFF999999),
    searchFieldFill: Color(0x10FFFFFF), // 反相: 夜晚态用 6% 白
    progressTrack: Color(0xFF3A3A3A),
  );

  static _SearchPagePalette of(ReadingSettings settings) =>
      settings.isNightTheme ? _dark : _light;
}
