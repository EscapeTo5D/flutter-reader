import 'dart:async';

import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/chapter_source.dart';
import '../models/reading_settings.dart';
import '../../reader/entities/text_page.dart';
import '../models/bookmark.dart';
import '../../reader/engine/page_engine.dart';
import '../../reader/engine/paginate_isolate.dart';
import '../content_processor.dart';
import '../storage/reader_repository.dart';
import '../storage/reading_progress.dart';
import '../storage/reading_style_preset.dart';
import '../storage/search_result.dart';

/// 预取(peek)的翻页目标信息。
///
/// 翻页动画在提交前需要知道目标页(及其所属章节/页码), 以便:
/// 1. 动画期间把目标页画到 prev/next 缓存槽;
/// 2. 动画结束时按 [chapterIndex] 判断是章内翻页还是跨章翻页, 精确提交。
///
/// 对齐原生 legado ReadView 三页缓存(prev/cur/nextPage)始终持有相邻页的做法,
/// 但 Flutter 端按需预取(仅在拖拽/动画期间持有), 避免常驻三页内存。
class PeekInfo {
  final TextPage page;
  final int chapterIndex;
  final int pageIndex;

  /// 该页所属章节的总页数(章内预取 = 当前章 totalPages; 跨章预取 = 目标章页数)。
  ///
  /// 用于页脚渲染跨章预取页时显示正确的 "页码/总页数"。null 表示未知(此时
  /// 渲染端可用 pageIndex+1 近似降级, 翻页提交后 controller 重排会用准确值)。
  final int? chapterPageCount;

  const PeekInfo({
    required this.page,
    required this.chapterIndex,
    required this.pageIndex,
    this.chapterPageCount,
  });
}

class ReadingController extends ChangeNotifier {
  Book? _book;
  ReadingSettings _settings = ReadingSettings();
  int _currentChapterIndex = 0;
  int _currentPageIndex = 0;
  List<TextPage> _pages = [];
  final List<Bookmark> _bookmarks = [];
  bool _menuVisible = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  // ⚠️ 全量对齐原生搜索后, 旧的底部 SearchMenu 覆盖层 + List<int> 标题搜索已废弃,
  // 改为独立全屏 SearchContentPage + 结构化 ReaderSearchResult 列表 + 浏览态。
  // _searchVisible/_searchQuery/_searchResults(旧 int 列表)/_searchResultIndex 保留
  // 仅为向后兼容 getter; 新流程用 _browseResults/_browseIndex/_browseMode。
  List<int> _searchResults = [];
  int _searchResultIndex = -1;
  // ─── 搜索结果浏览态(对齐原生 SearchMenu + view_search_menu.xml) ───
  /// 当前浏览的全书搜索结果列表(来自 SearchContentPage 回传)。
  List<ReaderSearchResult> _browseResults = const [];
  /// 当前浏览到的结果下标(在 _browseResults 中)。
  int _browseIndex = -1;
  /// 是否处于搜索结果浏览态(阅读页显示左右导航 FAB + 底部信息条)。
  bool _browseMode = false;
  /// 搜索结果跳转的待落页偏移(按章加载异步排版完成后再消费, 见 _goToSearchResult)。
  /// **带章号**: 消费时校验 chapterIndex == _currentChapterIndex 才落页,
  /// 防跨章快速点击时异步排版乱序导致的落页污染(根因修复)。
  /// 配合 _loadAndPaginateCurrentAsync 的 stillCurrent 守卫双重保险:
  /// 连点 N 次跨章, 旧 Future 完成时 stillCurrent=false 直接丢弃, 新点击覆盖 pending,
  /// 最终只有最后一次点击的目标章排版完成时才消费 pending 落页。
  ({int chapterIndex, int charOffset})? _pendingBrowse;
  Size _pageSize = Size.zero;

  final PageEngine _pageEngine = PageEngine();

  /// 相邻章分页预计算缓存(章索引 → 分页结果)。
  ///
  /// 跨章 peek 时避免在翻页关键帧同步重排整章(实测一整章 100~140ms, 阻塞 6~8 帧
  /// → 跨章卡顿)。peekNext/peekPrev/_rePaginate 都走 [_paginateChapterCached]:
  /// 首次重排后结果入缓存, 后续 O(1) 命中。
  ///
  /// 缓存键 = 章索引; 整表失效条件见 [_invalidateAdjacentCacheIfNeeded]:
  /// 排版指纹([_layoutSignature])变或 `_pageSize` 变(两者决定分页结果)。
  final Map<int, List<TextPage>> _adjacentChapterCache = {};
  // 缓存「入缓存时的排版指纹 + pageSize」。失效判断用指纹值比较(而非 settings
  // 对象引用), 这样改 pageAnimMode/颜色等不进排版的字段时 copyWith 产生的新对象
  // 不会误清缓存 —— 与 [updateSettings] 的重排短路逻辑贯穿一致。详见
  // [_invalidateAdjacentCacheIfNeeded]。
  Object? _cacheLayoutSig;
  Size _cachePageSize = Size.zero;

  // ─────────────────────────── 按章加载 / 异步排版 ───────────────────────────
  //
  // 对齐原生 legado: 章节正文从数据源按章懒加载(不全书常驻内存), 排版跑后台
  // (isolate), 仅当前章 ± 相邻章驻留。详见 AGENTS.md「按章加载」。
  //
  // 章节加载状态机(每章独立):
  //   idle   → 未请求
  //   loading → 已发起加载/排版, 尚未就绪(此期间 [chapterLoading] 为 true)
  //   ready   → 已就绪, 分页结果在 [_adjacentChapterCache]
  // 用一个「正在加载的章节索引集合」表达 loading, 避免引入完整状态枚举的复杂度。

  /// 当前正在后台加载/排版的章节索引集合(用于驱动 [chapterLoading])。
  final Set<int> _loadingChapters = {};

  /// 正在进行中的「加载+排版」Future 去重表(章索引 → 进行中的 Future)。
  ///
  /// 防止同一章被并发排版多次: 当 prefetchAdjacent / _rePaginate / restoreProgress
  /// 几乎同时请求同一章时, 复用同一个 Future, 而不是各自 spawn 排版。实测同章被
  /// 重复排 6 次每次 ~1s, 此表把 6 次合并为 1 次。
  final Map<int, Future<List<TextPage>>> _paginateInFlight = {};

  /// 章节正文按需加载源(来自 [Book.chapterSource], null = 旧全量内存模式)。
  ChapterSource? get _chapterSource => _book?.chapterSource;

  /// 是否处于「章节加载中」状态: 当前章正在后台加载/排版, UI 应显示占位
  /// 而非闪现原文。对齐 legado 排版未完成时不显示正文。
  bool get chapterLoading =>
      _loadingChapters.contains(_currentChapterIndex) && _pages.isEmpty;

  // ─────────────────────────── 持久化 ───────────────────────────
  /// 持久化仓库(null = 纯内存模式, 退化为不落盘, 兼容旧用法)。
  ReaderRepository? _repository;

  /// 当前用户 id(null = 未绑定, 此时进度等不落盘)。
  String? _userId;

  /// 进度落盘防抖定时器: 翻页/翻章后延迟 [_progressSaveDebounce] 落盘, 期间
  /// 新动作重置定时器, 避免连续翻页每页一次 IO。
  Timer? _progressSaveTimer;

  /// 设置落盘防抖定时器。
  Timer? _settingsSaveTimer;

  /// 进度/设置防抖延迟。1.5s 覆盖典型连续翻页节奏, 又不至于太晚(用户秒退也兜得住)。
  static const Duration _progressSaveDebounce = Duration(milliseconds: 1500);

  /// 页尺寸变更防抖定时器。对齐 legado `ChapterProvider.upViewSize`: 尺寸变化不立即
  /// 重排, 延迟 [_pageSizeDebounce] 后才真正执行; 期间若尺寸反弹回原值(键盘收起过渡
  /// 帧抖动、路由 pop 瞬变)则取消重排。避免 ~170ms/次的重排连续砸主线程卡死。
  Timer? _pageSizeTimer;

  /// 页尺寸防抖延迟。对齐 legado 的 300ms。
  static const Duration _pageSizeDebounce = Duration(milliseconds: 300);

  /// 是否已 dispose。异步恢复(loadBook/restoreProgress)回调里用它防止
  /// dispose 后还 notifyListeners(ChangeNotifier 此版本无 mounted getter, 自管标志位)。
  bool _disposed = false;

  /// 标记「即将退出」, 立即阻断后续异步预取/章加载(不等 [dispose])。
  ///
  /// 宿主在页面 dispose 的**同步阶段**调用: dispose() 是同步的, 但宿主常先
  /// fire-and-forget 一个 await flushProgress() 再 dispose(), 期间若异步加载回调
  /// 完成(如章正文排版好了), 会触发 _prefetchAdjacentAsync 发起新的网络请求。
  /// 提前置 _disposed 可让这些回调里的守卫生效, 避免退出后仍加载。进度落盘不受
  /// 影响(dispose 内部仍会 best-effort 落盘, 宿主 flushProgress 也会先 await)。
  void markExiting() {
    _disposed = true;
  }

  ReadingController({ReaderRepository? repository, String? userId})
    : _repository = repository,
      _userId = userId;

  /// 绑定持久化仓库与用户。两者任一为 null 则进入纯内存模式(不落盘)。
  /// 可在 [loadBook] 前后任意时刻调用; 已加载的书会立即触发一次进度恢复。
  void attachRepository(ReaderRepository repository, {String? userId}) {
    _repository = repository;
    if (userId != null) _userId = userId;
    // 若书已加载, 尝试用新用户恢复进度
    if (_book != null && _userId != null) {
      restoreProgress();
    }
  }

  /// 绑定/切换用户 id。切换后若书已加载, 立即恢复该用户在此书的进度。
  void bindUser(String userId) {
    _userId = userId;
    if (_book != null && _repository != null) {
      restoreProgress();
    }
  }

  ReaderRepository? get repository => _repository;
  String? get userId => _userId;

  Book? get book => _book;
  ReadingSettings get settings => _settings;
  int get currentChapterIndex => _currentChapterIndex;
  int get currentPageIndex => _currentPageIndex;
  List<TextPage> get pages => _pages;
  List<Bookmark> get bookmarks => _bookmarks;
  bool get menuVisible => _menuVisible;
  bool get searchVisible => _searchVisible;
  String get searchQuery => _searchQuery;
  List<int> get searchResults => _searchResults;
  int get searchResultIndex => _searchResultIndex;
  // 搜索结果浏览态(新流程)。
  List<ReaderSearchResult> get browseResults => _browseResults;
  int get browseIndex => _browseIndex;
  bool get browseMode => _browseMode;
  int get totalPages => _pages.length;

  /// 当前排版可用尺寸(正文区, 已扣除页眉页脚)。供 scroll 模式等需要知道
  /// 单页像素高度的场景使用。所有页等高 = pageSize.height。
  Size get pageSize => _pageSize;

  /// 章节总数。按章加载模式下取自 [_chapterSource], 否则取自 [_book.chapters]。
  int get totalChapters {
    final source = _chapterSource;
    if (source != null) return source.chapterCount;
    return _book?.chapters.length ?? 0;
  }

  /// 第 [index] 章的标题。按章加载模式下取自 [_chapterSource], 否则取自
  /// [_book.chapters]。供目录页等仅需标题的场景使用(与 [totalChapters] 配套)。
  /// 越界返回空串。
  String chapterTitle(int index) {
    final source = _chapterSource;
    if (source != null) return source.chapterTitle(index);
    final chapters = _book?.chapters;
    if (chapters == null || index < 0 || index >= chapters.length) return '';
    return chapters[index].title;
  }

  bool get canGoNext =>
      _currentPageIndex < _pages.length - 1 ||
      _currentChapterIndex < totalChapters - 1;
  bool get canGoPrevious => _currentPageIndex > 0 || _currentChapterIndex > 0;

  /// 当前章对象(旧全量内存模式)。按章加载模式下正文不在 chapters, 可能返回
  /// 仅含标题的占位 Chapter 或 null——调用方渲染正文应改用 [_pages]。
  Chapter? get currentChapter => _book != null && _book!.chapters.isNotEmpty
      ? (_currentChapterIndex < _book!.chapters.length
          ? _book!.chapters[_currentChapterIndex]
          : null)
      : null;

  ///
  /// [initialChapterIndex] 用于宿主「从目录跳转到指定章」场景:
  /// - 提供(>=0): 直接定位到该章, **跳过** restoreProgress(否则异步恢复会
  ///   用持久化的上次进度覆盖刚指定的跳转目标)。书签仍正常加载。
  /// - 不提供(null): 走原行为——用 [Book.currentChapterIndex] 起步, 异步恢复进度。
  void loadBook(Book book, {int? initialChapterIndex}) {
    _book = book;
    _currentChapterIndex =
        initialChapterIndex ?? book.currentChapterIndex;
    _currentPageIndex = 0;
    _rePaginate();
    notifyListeners();
    if (_repository == null || _userId == null) return;
    if (initialChapterIndex == null) {
      // 未指定跳转: 书加载完(分页就绪)后, 异步从仓库恢复该用户的进度。
      // 不阻塞渲染: 即使恢复晚一帧也无妨, 用户先看到首页再被定位到上次位置。
      restoreProgress();
    } else {
      // 显式跳章: 不恢复进度(避免覆盖跳转), 仍加载该书签(书签独立于进度)。
      loadBookmarks();
    }
  }

  /// 从仓库恢复当前用户在当前书的进度。
  ///
  /// 流程: 取持久化的 (chapterIndex, chapterCharOffset) → 跳到该章 →
  /// 用 charOffset 二分 `_pages` 各页首行 chapterPosition 定位回页码 → 落位。
  /// 跨字号/换设备重排后仍能定位到正确页(charOffset 不随排版变), 不丢进度。
  ///
  /// 找不到记录或 charOffset 越界时保持首页(0), 不报错。
  /// 仅在 _pageSize 就绪(分页已完成)时生效; 否则等 updatePageSize 后再恢复。
  Future<void> restoreProgress() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    if (_pageSize == Size.zero) return; // 分页未就绪, 等尺寸回调

    final p = await repo.getProgress(uid, book.id);
    if (_disposed) return;

    if (p != null) {
      // 章节越界保护
      final targetChapter = p.chapterIndex.clamp(0, totalChapters - 1);
      if (targetChapter != _currentChapterIndex) {
        _currentChapterIndex = targetChapter;
        _currentPageIndex = 0;
        _rePaginate();
      }
      // charOffset → 页码
      final page = pageIndexForCharOffset(p.chapterCharOffset);
      _currentPageIndex = page;
      notifyListeners();
    }
    // 无论有无进度记录, 都恢复该书的书签(书签独立于进度存在)。
    await loadBookmarks();
  }

  /// 把当前阅读位置(章+页)转成 [ReadingProgress] 落盘。
  ///
  /// charOffset 取当前页首行的 chapterPosition(页起点偏移, 比"页内某字"更稳定)。
  ReadingProgress? _currentProgress() {
    final book = _book;
    final uid = _userId;
    if (book == null || uid == null) return null;
    return ReadingProgress(
      userId: uid,
      bookId: book.id,
      chapterIndex: _currentChapterIndex,
      chapterCharOffset: charOffsetForCurrentPage(),
      pageIndex: _currentPageIndex,
      lastReadAt: DateTime.now(),
    );
  }

  /// 当前页首行(第一个非空文字行)的 chapterPosition = 该页起始字符偏移。
  /// 找不到文字行时返回 0(降级到章首)。
  ///
  /// 朗读子系统据此定位「当前页起点在章内的偏移」, 从而从当前页首段开始朗读。
  int charOffsetForCurrentPage() {
    if (_pages.isEmpty || _currentPageIndex >= _pages.length) return 0;
    for (final line in _pages[_currentPageIndex].lines) {
      if (line.text.isNotEmpty) return line.chapterPosition;
    }
    return 0;
  }

  /// charOffset → 页码(二分各页首行 chapterPosition)。
  ///
  /// 找到「首行偏移 <= offset」的最后一页; offset 超过末页首行则落末页。
  /// 用于跨字号/换设备恢复进度——重排后页数变了, 但 charOffset 不变, 仍能定位。
  ///
  /// 朗读子系统据此做翻页联动: 引擎报告段偏移后, 判断是否已越过下一页边界。
  int pageIndexForCharOffset(int charOffset) {
    if (_pages.isEmpty) return 0;
    var result = 0;
    for (var i = _pages.length - 1; i >= 0; i--) {
      final firstOffset = firstCharOffsetOfPage(_pages[i]);
      if (firstOffset <= charOffset) {
        result = i;
        break;
      }
    }
    return result;
  }

  /// 某页首行(第一个非空文字行)的 chapterPosition。
  int firstCharOffsetOfPage(TextPage page) {
    for (final line in page.lines) {
      if (line.text.isNotEmpty) return line.chapterPosition;
    }
    return 0;
  }

  /// 防抖落盘进度。翻页/翻章/恢复后调用, 1.5s 内无新动作才真正写库。
  void _scheduleProgressSave() {
    if (_repository == null || _userId == null || _book == null) return;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(_progressSaveDebounce, () {
      final p = _currentProgress();
      if (p != null) {
        _repository!.saveProgress(p);
      }
    });
  }

  /// 公开入口: 供 scroll 模式等在静默更新章页码([setCurrentPageSilent])后
  /// 触发防抖落盘。滚动结束(ScrollEnd)时调用。
  void scheduleProgressSave() => _scheduleProgressSave();

  /// 立即落盘进度(取消防抖定时器, 同步写)。dispose 时调用确保不丢。
  Future<void> flushProgress() async {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
    final p = _currentProgress();
    if (p != null && _repository != null) {
      await _repository!.saveProgress(p);
    }
  }

  /// 立即落盘阅读设置(取消防抖定时器, 同步写)。
  ///
  /// 宿主在退出阅读页前可与 [flushProgress] 一起调用, 避免用户刚调整字号/颜色后
  /// 立刻离开页面导致防抖写入尚未执行。
  Future<void> flushSettings() async {
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = null;
    final repo = _repository;
    if (repo != null) {
      await repo.saveSettings(_settings, userId: _userId);
    }
  }

  /// 立即落盘当前进度与设置。
  Future<void> flushPersistence() async {
    await flushProgress();
    await flushSettings();
  }

  void updateSettings(ReadingSettings settings) {
    // 排版指纹: 只有影响 page_engine.paginate 结果的字段变化才需重排。
    // 颜色 / headerConfig / footerConfig / tipColor / 屏幕开关 /
    // selectable / shareLayout 等 UI 字段不进 paginate, 改它们触发重排是纯浪费
    // (单章排版 ~100-260ms, 还会清空相邻章缓存 + 显示 loading), 是切换翻页动画
    // 等操作的明显卡顿源。
    //
    // pageAnimMode 也不进 paginate(所有翻页模式正文都贴分隔线, availableHeight 一致),
    // 故切换翻页模式不触发重排 —— 这是「切换翻页动画卡顿」的核心修复。
    final oldSig = _layoutSignature(_settings);
    _settings = settings;
    final layoutChanged = _layoutSignature(_settings) != oldSig;
    if (layoutChanged) {
      _rePaginate();
      // 设置变了会重排, 重新按当前 charOffset 定位回对应页(避免因排版变而停在错误的页)
      _scheduleProgressSave();
    }
    notifyListeners();
    _scheduleSettingsSave();
  }

  /// 聚合所有「影响 page_engine.paginate 分页结果」的设置字段, 用于判断改设置后
  /// 是否需要重排。返回 record, 字段顺序与 [ReadingSettings] 声明顺序一致, 便于
  /// 对照增删。
  ///
  /// ⚠️ 不进指纹的字段(改它们不该触发重排):
  /// pageAnimMode / backgroundColor / textColor / tipColor / tipDividerColor /
  /// backgroundImage / headerConfig / footerConfig / clickConfig /
  /// showHeaderDivider / showFooterDivider / keepScreenOn / hideStatusBar /
  /// hideNavigationBar / selectable / showBrightnessView / shareLayout。
  ///
  /// header/footer 的显隐(hidden)虽会改变喂给排版的可用高度, 但那是通过
  /// reader_view 的 nonContentHeight → [updatePageSize] 独立路径触发重排的,
  /// 不依赖 updateSettings, 故不进指纹(否则会与 pageSize 路径重复重排)。
  (double, int, double, double, double, String?, int, bool, bool,
      int, bool, double, double, double,
      double, double,
      double, double, double, double, double, double, double, double,
      double)
  _layoutSignature(ReadingSettings s) {
    final p = s.padding;
    return (
      s.fontSize, s.fontWeight.value, s.lineHeight, s.paragraphSpacing,
      s.letterSpacing, s.fontFamily, s.textIndent, s.textFullJustify,
      s.textBottomJustify,
      s.titleMode, s.isMiddleTitle, s.titleSize, s.titleTopSpacing,
      s.titleBottomSpacing,
      // padding.top/bottom 已不再参与排版(正文贴分隔线), 故不进签名;
      // footer 内容行高由 measureChromeContentHeight 决定, 随 reader_view.build 实时算。
      p.left, p.right,
      p.headerHeight,
      p.headerTop, p.headerBottom, p.headerLeft, p.headerRight,
      p.footerTop, p.footerBottom, p.footerLeft, p.footerRight,
    );
  }

  /// 页尺寸更新入口(reader_view 的 LayoutBuilder PostFrame 调用)。
  ///
  /// **防抖 + 反弹取消**(对齐 legado `ChapterProvider.upViewSize`):
  /// 软键盘弹/收、目录页 pop 等会让 LayoutBuilder constraints 在多帧里连续变化, 每帧
  /// 调到这里。若每帧都立即重排(~170ms/次), 主线程被占满 → 肉眼卡顿。legado 原生靠
  /// 「目录/搜索是独立 Activity, 键盘弹在另一 window, 底层 View 不 resize」天然规避;
  /// Flutter 同 Navigator 栈无此隔离, 故在代码层复刻 legado 的兜底机制:
  ///
  ///  - 尺寸跟当前 _pageSize 相同: 不做任何事(命中频率最高, O(1) 跳过)。
  ///  - 尺寸不同: 不立即重排, 挂一个 [_pageSizeDebounce] 后执行的定时器; 其间又收到
  ///    更新会覆盖它(取最新尺寸)。
  ///  - 若在定时器到期前尺寸又变回 _pageSize(反弹, 典型键盘收起过渡), 取消定时器,
  ///    当作无事发生 —— 这正是「键盘瞬变」场景能被吸收的关键。
  ///  - 真正的尺寸稳定变化(旋转/分屏/系统栏显隐)最终都会到期执行一次重排。
  ///
  /// 首次进入(_pageSize == Size.zero)时不能延迟: 那是 loadBook 流程的关键路径, 延迟
  /// 会让首屏空内容多停 300ms。直接同步执行。
  void updatePageSize(Size size) {
    // 尺寸没变: 若有挂起的重排且尺寸恰好弹回当前值, 取消它(反弹取消); 否则 no-op。
    if (_pageSize == size) {
      if (_pageSizeTimer != null) {
        _pageSizeTimer!.cancel();
        _pageSizeTimer = null;
      }
      return;
    }
    // 首次进入(loadBook 关键路径): 同步执行, 不走防抖。
    if (_pageSize == Size.zero) {
      _applyPageSize(size);
      return;
    }
    // 尺寸变了: 防抖。记下最新目标尺寸, 300ms 内若无新变化(或反弹回原值被上面分支
    // 取消)才真正重排。覆盖新尺寸到 _pendingPageSize, 定时器到期时读它。
    _pendingPageSize = size;
    _pageSizeTimer?.cancel();
    _pageSizeTimer = Timer(_pageSizeDebounce, () {
      _pageSizeTimer = null;
      if (_pendingPageSize != null && _pageSize != _pendingPageSize) {
        _applyPageSize(_pendingPageSize!);
      }
    });
  }

  Size? _pendingPageSize;

  void _applyPageSize(Size size) {
    if (_pageSize == size) return;
    _pageSize = size;
    _rePaginate();
    notifyListeners();
    // 尺寸就绪后, 若仓库里有进度且尚未恢复(loadBook 时可能 pageSize 还是 zero), 现在恢复。
    if (_repository != null && _userId != null && _book != null) {
      restoreProgress();
    }
  }

  /// 防抖落盘设置。改字号/行距/颜色等频繁操作时, 1.5s 内最后状态写一次。
  void _scheduleSettingsSave() {
    if (_repository == null) return;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(_progressSaveDebounce, () {
      _repository!.saveSettings(_settings, userId: _userId);
    });
  }

  void goToPage(int page) {
    if (page >= 0 && page < _pages.length) {
      _currentPageIndex = page;
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void setCurrentPageIndex(int page) {
    if (page >= 0 && page < _pages.length && page != _currentPageIndex) {
      _currentPageIndex = page;
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void setCurrentChapterIndex(int index) {
    if (index >= 0 && index < totalChapters) {
      _currentChapterIndex = index;
    }
  }

  /// 静默更新当前章/页(不 notifyListeners, 不立即落盘), 供 scroll 模式滚动过程
  /// 高频同步进度用。滚动结束时应调 [scheduleProgressSave] 触发防抖落盘。
  ///
  /// 之所以需要静默 setter: scroll 模式逐像素滚动时若每帧 notify, 整个 reader
  /// 子树(手势/Stack/CustomPainter/chrome)每帧 rebuild, 持续卡顿。改为 handler
  /// 内部局部 setState 驱动偏移重绘, 章页码变化只走静默 setter 更新字段,
  /// 待 ScrollEnd 再 notify + 落盘。对齐原生 legado: `ContentTextView.scroll` 里
  /// 只改 `pageOffset` + 局部 `postInvalidate`, 不触发 `ReadBook.callback` 的
  /// 全量刷新(翻页/翻章才回调)。
  void setCurrentPageSilent(int chapterIndex, int pageInChapter) {
    if (chapterIndex >= 0 && chapterIndex < totalChapters && pageInChapter >= 0) {
      _currentChapterIndex = chapterIndex;
      _currentPageIndex = pageInChapter.clamp(0, _pages.length - 1);
    }
  }

  void nextPage() {
    if (_currentPageIndex < _pages.length - 1) {
      _currentPageIndex++;
      notifyListeners();
      _scheduleProgressSave();
    } else if (_currentChapterIndex < totalChapters - 1) {
      nextChapter();
    }
  }

  void previousPage() {
    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      notifyListeners();
      _scheduleProgressSave();
    } else if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      if (_pages.isNotEmpty) {
        _currentPageIndex = _pages.length - 1;
      }
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void nextChapter() {
    if (_book == null) return;
    if (_currentChapterIndex < totalChapters - 1) {
      _currentChapterIndex++;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void previousChapter() {
    if (_book == null) return;
    if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _rePaginate();
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  void goToChapter(int index) {
    if (_book == null || index < 0 || index >= totalChapters) return;
    _currentChapterIndex = index;
    _currentPageIndex = 0;
    _rePaginate();
    notifyListeners();
    _scheduleProgressSave();
  }

  void toggleMenu() {
    _menuVisible = !_menuVisible;
    if (_menuVisible) _searchVisible = false;
    notifyListeners();
  }

  void hideMenu() {
    _menuVisible = false;
    notifyListeners();
  }

  void toggleSearch() {
    // ⚠️ 旧的底部 SearchMenu 覆盖层入口已废弃(全量对齐原生后改走 SearchContentPage)。
    // 此方法保留仅为向后兼容: 不再切换覆盖层, 仅清状态。新流程由 read_menu 的搜索
    // FAB 直接 push SearchContentPage, 完成后调 enterSearchBrowse 进入浏览态。
    _searchVisible = !_searchVisible;
    _menuVisible = false;
    if (!_searchVisible) {
      _searchQuery = '';
      _searchResults = [];
      _searchResultIndex = -1;
    }
    notifyListeners();
  }

  // ─────────── 搜索结果浏览态(对齐原生 SearchMenu + view_search_menu.xml) ───────────
  //
  // 流程: SearchContentPage 点结果 → pop(SearchResultBrowseData) → 调用方
  // (read_menu/reader_view) 拿到数据调 enterSearchBrowse → 跳到选中结果 +
  // 置 _browseMode=true → reader_view 渲染左右导航 FAB + 底部信息条。
  // nextBrowseResult/previousBrowseResult 翻到相邻结果; exitSearchBrowse 退出。

  /// 进入搜索结果浏览态。
  ///
  /// - [results] 全部命中(来自 SearchContentPage)。
  /// - [selectedIndex] 用户点的那个, 立即跳过去。
  void enterSearchBrowse(List<ReaderSearchResult> results, int selectedIndex) {
    _browseResults = List.unmodifiable(results);
    _browseIndex =
        results.isEmpty ? -1 : selectedIndex.clamp(0, results.length - 1);
    _browseMode = true;
    // 浏览态正文高亮: 让 searchQuery getter 返回本次查询词, 驱动
    // PageView._markSearchResults 标红命中字符(对齐原生搜索结果高亮)。
    if (results.isNotEmpty) {
      _searchQuery = results.first.query;
    }
    if (_browseIndex >= 0) {
      _goToSearchResult(_browseResults[_browseIndex]);
    }
    notifyListeners();
  }

  /// 退出浏览态, 清结果(对齐原生"退出"按钮)。
  void exitSearchBrowse() {
    _browseMode = false;
    _browseResults = const [];
    _browseIndex = -1;
    // 清正文高亮 query + 残留 pending(若有进行中的跳转)。
    _searchQuery = '';
    _pendingBrowse = null;
    notifyListeners();
  }

  /// 浏览态: 跳到下一条结果(循环)。
  void nextBrowseResult() {
    if (_browseResults.isEmpty) return;
    _browseIndex = (_browseIndex + 1) % _browseResults.length;
    _goToSearchResult(_browseResults[_browseIndex]);
    notifyListeners();
  }

  /// 浏览态: 跳到上一条结果(循环)。
  void previousBrowseResult() {
    if (_browseResults.isEmpty) return;
    _browseIndex =
        (_browseIndex - 1 + _browseResults.length) % _browseResults.length;
    _goToSearchResult(_browseResults[_browseIndex]);
    notifyListeners();
  }

  /// 跳到指定搜索结果所在的章+页。
  ///
  /// 关键: [ReaderSearchResult.charOffsetInChapter] 与 `TextLine.chapterPosition`
  /// 同源(都在 ContentProcessor 预处理后的正文坐标系), 故直接喂
  /// [pageIndexForCharOffset] 即可落页, 无需换算。
  ///
  /// 按章加载模式下 [_rePaginate] 是异步的: 章切换后 _pages 暂空, 需等排版完成
  /// 才能 pageIndexForCharOffset。用 [_pendingBrowse] 暂存(章号 + 偏移),
  /// [_loadAndPaginateCurrentAsync] 的 stillCurrent 分支消费它(参照 restoreProgress
  /// 的"等 pageSize 就绪再恢复"模式)。
  ///
  /// **带章号 + 代际号双重守卫**(根因修复):
  /// - pending 带 chapterIndex, 消费时校验 == _currentChapterIndex 才落页,
  ///   防跨章快速点击时异步排版乱序把旧章的偏移落到新章。
  /// - 代际号 [_browseGen] 由 next/prev/enter/exit 入口自增, 异步排版完成回调
  ///   时若代际已变(用户又点了下一次), 本次 pending 被新调用覆盖, 不会污染。
  void _goToSearchResult(ReaderSearchResult r) {
    if (_book == null) return;
    if (r.chapterIndex < 0 || r.chapterIndex >= totalChapters) return;
    // 统一用带章号 pending: 跨章走 _rePaginate 异步, 同章若 _pages 就绪直接落页
    // 否则也走 pending 等排版完成。
    final needPaginate = r.chapterIndex != _currentChapterIndex;
    if (needPaginate) {
      _currentChapterIndex = r.chapterIndex;
      _currentPageIndex = 0;
    }
    if (!needPaginate && _pages.isNotEmpty) {
      // 同章且排版就绪: 立即落页, 清 pending。
      _pendingBrowse = null;
      _currentPageIndex = pageIndexForCharOffset(r.charOffsetInChapter);
    } else {
      // 跨章(刚改 _currentChapterIndex, _rePaginate 将异步)或同章排版未就绪:
      // 暂存带章号 pending, 等排版完成回调消费。
      _pendingBrowse =
          (chapterIndex: r.chapterIndex, charOffset: r.charOffsetInChapter);
      if (needPaginate) _rePaginate();
    }
    _scheduleProgressSave();
  }

  void addBookmark() {
    if (_book == null || currentChapter == null) return;
    final existing = _bookmarks.indexWhere(
      (b) =>
          b.bookId == _book!.id &&
          b.chapterIndex == _currentChapterIndex &&
          b.pageIndex == _currentPageIndex,
    );
    if (existing >= 0) {
      final removed = _bookmarks.removeAt(existing);
      // 同步删除持久化书签
      if (_repository != null && removed.userId == _userId) {
        _repository!.deleteBookmark(removed.id);
      }
    } else {
      final page = _pages.isNotEmpty && _currentPageIndex < _pages.length
          ? _pages[_currentPageIndex]
          : null;
      final content = page?.lines.take(2).map((l) => l.text).join() ?? '';
      final bookmark = Bookmark(
        id: '${_book!.id}_${_currentChapterIndex}_$_currentPageIndex',
        bookId: _book!.id,
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex,
        content: content,
        createdAt: DateTime.now(),
        chapterCharOffset: charOffsetForCurrentPage(),
        userId: _userId,
      );
      _bookmarks.add(bookmark);
      // 同步落库
      if (_repository != null && _userId != null) {
        _repository!.saveBookmark(bookmark);
      }
    }
    notifyListeners();
  }

  /// 从仓库恢复当前用户在当前书的所有书签到内存 [_bookmarks]。
  /// 仅在仓库/用户已绑定时生效; 失败则保持现有内存书签。
  Future<void> loadBookmarks() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    final stored = await repo.getBookmarks(uid, book.id);
    if (_disposed) return;
    // 合并: 移除该书旧的内存书签, 用持久化数据替换
    _bookmarks.removeWhere((b) => b.bookId == book.id);
    _bookmarks.addAll(stored);
    notifyListeners();
  }

  // ─────────────────────────── 用户样式预设 ───────────────────────────
  //
  // 透传 repository 的预设 CRUD。无 repository 时返回空/无操作(纯内存模式退化,
  // UI 此时只显示内置 6 预设, 「+」无效果——对齐「无 repo = 无持久化」语义)。

  /// 读取当前用户的自定义样式预设(按 sort_order 升序)。
  /// 无 repository 时返回空列表。
  Future<List<ReadingStylePreset>> loadStylePresets() async {
    final repo = _repository;
    final uid = _userId;
    if (repo == null || uid == null) return const [];
    return repo.getStylePresets(uid);
  }

  /// 保存/覆盖预设。无 repository 时无操作。
  Future<void> saveStylePreset(ReadingStylePreset preset) async {
    final repo = _repository;
    if (repo == null) return;
    await repo.saveStylePreset(preset);
  }

  /// 删除预设。无 repository 时无操作。
  Future<void> deleteStylePreset(String presetId) async {
    final repo = _repository;
    if (repo == null) return;
    await repo.deleteStylePreset(presetId);
  }

  bool isCurrentPageBookmarked() {
    if (_book == null) return false;
    return _bookmarks.any(
      (b) =>
          b.bookId == _book!.id &&
          b.chapterIndex == _currentChapterIndex &&
          b.pageIndex == _currentPageIndex,
    );
  }

  ClickAction getClickAction(Offset position, Size size) {
    final col = position.dx < size.width / 3
        ? 0
        : (position.dx < size.width * 2 / 3 ? 1 : 2);
    final row = position.dy < size.height / 3
        ? 0
        : (position.dy < size.height * 2 / 3 ? 1 : 2);
    final config = _settings.clickConfig;
    if (row == 0 && col == 0) return config.topLeft;
    if (row == 0 && col == 1) return config.topCenter;
    if (row == 0 && col == 2) return config.topRight;
    if (row == 1 && col == 0) return config.middleLeft;
    if (row == 1 && col == 1) return config.center;
    if (row == 1 && col == 2) return config.middleRight;
    if (row == 2 && col == 0) return config.bottomLeft;
    if (row == 2 && col == 1) return config.bottomCenter;
    return config.bottomRight;
  }

  void handleClickAction(ClickAction action) {
    switch (action) {
      case ClickAction.menu:
        toggleMenu();
        break;
      case ClickAction.nextPage:
        nextPage();
        break;
      case ClickAction.prevPage:
        previousPage();
        break;
      case ClickAction.nextChapter:
        nextChapter();
        break;
      case ClickAction.prevChapter:
        previousChapter();
        break;
      case ClickAction.bookmark:
        addBookmark();
        break;
      case ClickAction.search:
        toggleSearch();
        break;
      case ClickAction.none:
        debugPrint('[Controller] clickAction is none, doing nothing');
        break;
    }
  }

  List<TextPage> paginateChapter(int chapterIndex) {
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= _book!.chapters.length) return [];
    return _pageEngine.paginate(
      content: _book!.chapters[chapterIndex].content,
      pageSize: _pageSize,
      settings: _settings,
    );
  }

  /// 异步加载并分页指定章, 返回分页结果(对齐原生 `nextChapter` 预加载链)。
  ///
  /// **用途**: scroll 模式 handler 预取相邻章 / 跨章翻页时调用。
  /// 全量内存模式走 `_paginateChapterWithPipeline`(同步); 按章加载模式走
  /// [_loadAndPaginateChapter](异步, 命中缓存 O(1), 未命中后台加载+排版,
  /// in-flight 去重)。结果同时写入 [_adjacentChapterCache] 供后续命中。
  ///
  /// 对比旧的同步 [paginateChapter]:后者直接读 `_book.chapters[index].content`,
  /// 按章加载模式下 chapters 仅存标题、正文懒加载 → 返回空内容分页。本方法走
  /// 数据源 `loadContent`, 是 scroll 模式能跨章的正确入口。
  ///
  /// 返回非空 List 表示就绪; 空表示章越界或加载失败(调用方据此决定是否钳制滚动)。
  Future<List<TextPage>> paginateChapterAsync(int chapterIndex) async {
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= totalChapters) return [];
    if (_chapterSource == null) {
      // 全量内存模式: 同步管线(章节已在 chapters[].content 里), 直接返回。
      return _paginateChapterWithPipeline(chapterIndex);
    }
    // 按章加载模式: 走异步加载+排版(缓存命中 / in-flight 去重 / 后台 isolate)。
    try {
      return await _loadAndPaginateChapter(chapterIndex);
    } catch (_) {
      return [];
    }
  }

  /// 同步取章分页, **仅命中缓存, 不触发加载**(对齐原生 `curTextChapter.getPage`)。
  ///
  /// 用途: scroll 模式跨章翻页后, 原"当前章"刚被读过、分页必在缓存里, 用本方法
  /// 同步取回作为新 prev(避免异步等待)。未命中缓存返回空 List(调用方按需异步补)。
  List<TextPage> paginateChapterSyncOrCache(int chapterIndex) {
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= totalChapters) return [];
    _invalidateAdjacentCacheIfNeeded();
    final cached = _adjacentChapterCache[chapterIndex];
    return cached ?? <TextPage>[];
  }

  /// 同步分页指定章, **优先命中缓存, 未命中则全量内存模式下同步重排**。
  ///
  /// 用途: scroll 模式预取相邻章时, 先尝试同步(全量内存模式 chapters[].content
  /// 在内存, 同步排版即时就绪, 保证连续跨章翻页/fling 不被异步打断); 按章加载模式
  /// 正文懒加载, 同步取不到 → 返回空, 调用方 fallback 到异步 [paginateChapterAsync]。
  ///
  /// 与 [paginateChapter] 区别: 本方法走 ContentProcessor 管线(与 _rePaginate 一致),
  /// 保证 peek 页与提交后排版结果完全相同; 且只对全量内存模式同步排, 不对按章加载
  /// 模式做空内容同步排(避免 bug3 空内容页)。
  List<TextPage> paginateChapterPreferSync(int chapterIndex) {
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= totalChapters) return [];
    // 按章加载模式: 正文懒加载, 不能同步排(否则空内容页)。
    if (_chapterSource != null) {
      // 但缓存命中的话可以直接返回(已异步排过的)。
      _invalidateAdjacentCacheIfNeeded();
      return _adjacentChapterCache[chapterIndex] ?? <TextPage>[];
    }
    // 全量内存模式: 同步管线(章节已在 chapters[].content 里), 命中缓存 O(1)。
    return _paginateChapterWithPipeline(chapterIndex);
  }

  /// 读取指定章的预处理后正文(朗读子系统用)。
  ///
  /// 返回 `ContentProcessor.getContent(...).textList.join('\n')` —— 与排版引擎
  /// ([_paginateChapterWithPipeline] / [_loadAndPaginateCurrentAsync]) 输入**完全同源**,
  /// 故朗读切段偏移与 [TextLine.chapterPosition] 对齐。
  ///
  /// 全量内存模式: 同步从 `_book.chapters[index].content` 取。
  /// 按章加载模式: 异步从 `_chapterSource.loadContent` 取, 正文未就绪时返回 null
  /// (调用方应 fallback 到 [paginateChapterAsync] 预热后再取)。
  ///
  /// 朗读子系统据此调 `TextSlicer.slice(content)` 切段。此方法是朗读与排版的
  /// 唯一文本交汇点, 保证两者看到的章节内容完全一致。
  Future<String?> chapterProcessedContent(int chapterIndex) async {
    if (_book == null) return null;
    if (chapterIndex < 0 || chapterIndex >= totalChapters) return null;
    final source = _chapterSource;
    String title;
    String content;
    if (source == null) {
      // 全量内存模式。
      if (chapterIndex >= _book!.chapters.length) return null;
      final chapter = _book!.chapters[chapterIndex];
      title = chapter.title;
      content = chapter.content;
    } else {
      // 按章加载模式。
      title = source.chapterTitle(chapterIndex);
      final cached = await source.loadContent(chapterIndex);
      if (cached == null) return null;
      content = cached;
    }
    final bookContent = ContentProcessor.getContent(
      title: title,
      content: content,
      bookName: _book!.title,
      textIndent: _settings.textIndent,
    );
    return bookContent.textList.join('\n');
  }

  Chapter? getChapter(int index) {
    if (_book == null || index < 0 || index >= _book!.chapters.length) {
      return null;
    }
    return _book!.chapters[index];
  }

  void _rePaginate() {
    if (_book == null || _pageSize == Size.zero) return;
    final source = _chapterSource;
    if (source == null) {
      // 旧全量内存模式: chapters 已持有全部正文, 同步重排(原有行为不变)。
      final chapter = currentChapter;
      if (chapter == null) {
        _pages = [];
        return;
      }
      _pages = _paginateChapterCached(_currentChapterIndex);
      _clampCurrentPage();
      return;
    }
    // 按章加载模式。
    // 先按需失效缓存: 排版指纹(字号/行距/titleMode 等)或 pageSize 变化时, 旧分页结果
    // 作废。否则快路径会复用旧 settings 排好的缓存, 导致改 titleMode 等不生效
    // (例: 隐藏→显示标题时仍用无标题的旧分页)。_invalidateAdjacentCacheIfNeeded
    // 内部用 _layoutSignature 值比较, 无排版变化时是 O(1) no-op。
    _invalidateAdjacentCacheIfNeeded();
    // 快路径: 当前章分页缓存命中(预排过) → 同步就绪, 翻章流畅。
    final cached = _adjacentChapterCache[_currentChapterIndex];
    if (cached != null) {
      _pages = cached;
      _clampCurrentPage();
      return;
    }
    // 未命中: 正文可能未加载或未排版。启动后台加载+排版, 期间 _pages 暂空(loading 态)。
    // 异步完成后填 _pages 并 notifyListeners。
    _pages = [];
    _loadAndPaginateCurrentAsync();
  }

  void _clampCurrentPage() {
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.isEmpty ? 0 : _pages.length - 1;
    }
  }

  /// 异步加载当前章正文并排版(按章加载模式)。
  ///
  /// 流程(对齐 legado `loadContent` + 后台排版):
  /// 1. 标记当前章 loading → notifyListeners(UI 显示占位而非原文)。
  /// 2. 从 [_chapterSource] 取当前章正文。
  /// 3. ContentProcessor 预处理 + [paginateInBackground] 后台排版。
  /// 4. 结果入 [_adjacentChapterCache], 填 [_pages], 清 loading, notifyListeners。
  /// 5. 顺带预取相邻章(prefetchRange + 排版)。
  ///
  /// 幂等保护: 若在加载期间用户已翻到别的章(_currentChapterIndex 变了),
  /// 本次结果丢弃(不覆盖新当前章)。
  Future<void> _loadAndPaginateCurrentAsync() async {
    final source = _chapterSource;
    final book = _book;
    if (source == null || book == null || _pageSize == Size.zero) return;
    final chapterIndex = _currentChapterIndex;
    // 防重入: 同一章已在加载中, 不重复发起。
    if (_loadingChapters.contains(chapterIndex)) return;

    _loadingChapters.add(chapterIndex);
    if (chapterIndex == _currentChapterIndex) notifyListeners();

    try {
      final pages = await _loadAndPaginateChapter(chapterIndex);
      if (_disposed) return;
      // 加载期间用户已翻走: 丢弃本次结果(结果仍入缓存供将来用, 但不更新当前 _pages)。
      final stillCurrent = chapterIndex == _currentChapterIndex;
      if (stillCurrent) {
        _pages = pages;
        _clampCurrentPage();
        // 搜索结果跳转: 章切换后排版刚完成, 用待落偏移精确定位到命中所在页
        // (对齐 restoreProgress 的 charOffset→page 二分落位)。
        // **带章号校验**(根因修复): pending 的章号必须等于当前章才落页,
        // 防跨章快速点击时异步排版乱序把旧章 pending 落到新章。
        final pending = _pendingBrowse;
        if (pending != null && pending.chapterIndex == _currentChapterIndex) {
          _currentPageIndex = pageIndexForCharOffset(pending.charOffset);
          _pendingBrowse = null;
        }
        _loadingChapters.remove(chapterIndex);
        notifyListeners();
        // 当前章就绪后, 预取相邻章(对齐 legado prefetch, 翻章命中缓存 O(1))。
        _prefetchAdjacentAsync();
      } else {
        _loadingChapters.remove(chapterIndex);
      }
    } catch (e) {
      _loadingChapters.remove(chapterIndex);
      debugPrint('[Reader] 异步加载章 $chapterIndex 失败: $e');
      if (chapterIndex == _currentChapterIndex && !_disposed) {
        notifyListeners();
      }
    }
  }

  /// 加载并排版指定章, 返回分页结果(不入 _pages, 调用方决定如何用)。
  /// 结果同时写入 [_adjacentChapterCache]。
  ///
  /// **in-flight 去重**: 同一章在 [_paginateInFlight] 已有进行中的 Future 时,
  /// 复用它而非另起一次排版。防止 prefetchAdjacent / _rePaginate / restoreProgress
  /// 并发请求同章导致重复排版。
  Future<List<TextPage>> _loadAndPaginateChapter(int chapterIndex) async {
    final source = _chapterSource;
    final book = _book;
    if (source == null || book == null) return [];
    if (chapterIndex < 0 || chapterIndex >= source.chapterCount) return [];
    // 缓存命中直接返回(避免重复排版)。
    _invalidateAdjacentCacheIfNeeded();
    final cached = _adjacentChapterCache[chapterIndex];
    if (cached != null) return cached;

    // in-flight 去重: 同一章已在排版中, 复用 Future。
    final inflight = _paginateInFlight[chapterIndex];
    if (inflight != null) return inflight;

    final future = _doLoadAndPaginate(chapterIndex);
    _paginateInFlight[chapterIndex] = future;
    try {
      return await future;
    } finally {
      _paginateInFlight.remove(chapterIndex);
    }
  }

  Future<List<TextPage>> _doLoadAndPaginate(int chapterIndex) async {
    final source = _chapterSource;
    final book = _book;
    if (source == null || book == null) return [];
    // 1. 取正文: 按章加载模式从数据源懒加载。
    final tLoad = Stopwatch()..start();
    final content = await source.loadContent(chapterIndex) ?? '';
    if (kLogPerf) {
      debugPrint(
        '[PERF] loadContent(章 $chapterIndex, ${content.length}字符): ${tLoad.elapsedMilliseconds}ms',
      );
    }
    if (_disposed) return [];
    final title = source.chapterTitle(chapterIndex);
    // 2. 预处理(对齐 legado ContentProcessor)。
    final tProc = Stopwatch()..start();
    final bookContent = ContentProcessor.getContent(
      title: title,
      content: content,
      bookName: book.title,
      textIndent: _settings.textIndent,
    );
    final processedContent = bookContent.textList.join('\n');
    if (kLogPerf) {
      debugPrint('[PERF] ContentProcessor(章 $chapterIndex): ${tProc.elapsedMilliseconds}ms');
    }
    // 3. 后台排版(isolate, 不阻塞 UI)。对齐 legado Coroutine.async(IO)。
    final tPaginate = Stopwatch()..start();
    final pages = await paginateInBackground(
      content: processedContent,
      pageSize: _pageSize,
      settings: _settings,
      // ContentProcessor 把 title 非空时的第 0 段设为标题; 告知 paginate 以位置判定。
      firstParagraphIsTitle: title.isNotEmpty,
    );
    if (kLogPerf) {
      debugPrint(
        '[PERF] paginate(章 $chapterIndex, ${pages.length}页): ${tPaginate.elapsedMilliseconds}ms',
      );
    }
    _adjacentChapterCache[chapterIndex] = pages;
    return pages;
  }

  /// 异步预取相邻章(±1)的分页结果到缓存(按章加载模式)。
  ///
  /// 对齐 legado `prefetchAdjacentChapters`: 用户在当前章阅读时, 后台把相邻章
  /// 正文加载+排版好入缓存, 翻章时命中 O(1)。不更新 _pages, 不阻塞当前显示。
  Future<void> _prefetchAdjacentAsync() async {
    if (_disposed) return;
    final source = _chapterSource;
    if (source == null) return;
    final next = _currentChapterIndex + 1;
    final prev = _currentChapterIndex - 1;
    // 用 Future.wait 并行预取, 任一失败不影响另一个。
    await Future.wait([
      _loadAndPaginateChapter(next).catchError((_) => <TextPage>[]),
      _loadAndPaginateChapter(prev).catchError((_) => <TextPage>[]),
    ]);
  }

  /// 对指定章节跑完整的内容预处理 + 排版管线, 返回分页结果。
  ///
  /// 抽取自原 `_rePaginate` 的内容管线(ContentProcessor → join → PageEngine.paginate),
  /// 供「重新分页当前章」与「预取相邻章(peek)」共用, 保证两者产出的页面完全一致——
  /// 否则 `paginateChapter()`(跳过 ContentProcessor) 与 `_rePaginate` 产出的页不同,
  /// 翻页动画展示的页与提交后看到的页会错位。
  ///
  /// 不修改 `_pages`/`_currentPageIndex` 等状态, 纯函数。
  /// ⚠️ 仅用于旧全量内存模式(_chapterSource == null)。按章加载模式下跨章 peek
  /// 走 [_loadAndPaginateChapter](异步), 见 [peekNext]/[peekPrev]。
  List<TextPage> _paginateChapterWithPipeline(int chapterIndex) {
    return _paginateChapterCached(chapterIndex);
  }

  /// 带缓存的整章重排(供 peekNext/peekPrev/_rePaginate 共用)。
  ///
  /// 缓存键 = chapterIndex; 失效条件 = `_settings` 引用变 / `_pageSize` 变。
  /// 命中 → O(1) 返回; 未命中 → 同步重排(首次或失效后)。
  ///
  /// ⚠️ 仅用于旧全量内存模式。按章加载模式下, 章节正文不在 [_book.chapters],
  /// 不能同步排; 此时调用方应改用异步 [_loadAndPaginateChapter]。
  List<TextPage> _paginateChapterCached(int chapterIndex) {
    _invalidateAdjacentCacheIfNeeded();
    if (_book == null || _pageSize == Size.zero) return [];
    if (chapterIndex < 0 || chapterIndex >= _book!.chapters.length) return [];
    final cached = _adjacentChapterCache[chapterIndex];
    if (cached != null) return cached;

    final chapter = _book!.chapters[chapterIndex];
    final bookContent = ContentProcessor.getContent(
      title: chapter.title,
      content: chapter.content,
      bookName: _book!.title,
      textIndent: _settings.textIndent,
    );
    final processedContent = bookContent.textList.join('\n');
    final pages = _pageEngine.paginate(
      content: processedContent,
      pageSize: _pageSize,
      settings: _settings,
      // ContentProcessor 把 title 非空时的第 0 段设为标题; 告知 paginate 以位置判定,
      // 不依赖正则(覆盖"楔子"/"序章"/宿主自定义标题等非"第N章"格式)。
      firstParagraphIsTitle: chapter.title.isNotEmpty,
    );
    _adjacentChapterCache[chapterIndex] = pages;
    return pages;
  }

  /// 若影响分页结果的输入(排版指纹 / pageSize)发生变化, 清空整个相邻章缓存。
  ///
  /// 用 [_layoutSignature] 值比较而非 `_settings` 对象引用 —— 因为 `updateSettings`
  /// 每次都 `copyWith` 出新对象, 引用必变, 会让改 pageAnimMode/颜色等不进排版的
  /// 字段也误清缓存, 导致相邻章被重新分页/重新异步加载(scroll 模式预取、
  /// [prefetchAdjacentChapters] 都会立刻重做), 是切到/切出 scroll 模式的卡顿源。
  /// 与 `updateSettings` 的重排短路逻辑用同一指纹, 行为一致。
  void _invalidateAdjacentCacheIfNeeded() {
    final sig = _layoutSignature(_settings);
    if (sig != _cacheLayoutSig || _pageSize != _cachePageSize) {
      _adjacentChapterCache.clear();
      _cacheLayoutSig = sig;
      _cachePageSize = _pageSize;
    }
  }

  /// 预取下一页(无副作用: 不改变 currentPageIndex/chapterIndex/pages)。
  ///
  /// 章内有下一页 → 该页; 否则若存在下一章 → 下一章首页; 否则 null(无下一页)。
  /// 翻页动画据此把目标页画到 next 缓存槽, 动画结束按 info 提交。
  ///
  /// 按章加载模式下, 跨章只能用已预排好的缓存(异步预排在后台进行, 详见
  /// [_prefetchAdjacentAsync]); 缓存未命中时返回 null, reader_view 的去重标记
  /// 不会更新, 下次章/页就绪后会重试(对齐 _refreshPeekCaches 的 null 容错)。
  PeekInfo? peekNext() {
    if (_book == null) return null;
    if (_currentPageIndex < _pages.length - 1) {
      return PeekInfo(
        page: _pages[_currentPageIndex + 1],
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex + 1,
        chapterPageCount: _pages.length,
      );
    }
    // 当前章末页 → 下一章首页
    if (_currentChapterIndex < totalChapters - 1) {
      final nextIdx = _currentChapterIndex + 1;
      final nextChapterPages = _adjacentChapterCache[nextIdx] ??
          (_chapterSource == null ? _paginateChapterWithPipeline(nextIdx) : const []);
      if (nextChapterPages.isNotEmpty) {
        return PeekInfo(
          page: nextChapterPages.first,
          chapterIndex: nextIdx,
          pageIndex: 0,
          chapterPageCount: nextChapterPages.length,
        );
      }
    }
    return null;
  }

  /// 预取上一页(无副作用: 不改变 currentPageIndex/chapterIndex/pages)。
  ///
  /// 当前页 > 0 → 上一页; 否则若存在上一章 → 上一章末页; 否则 null(无上一页)。
  PeekInfo? peekPrev() {
    if (_book == null) return null;
    if (_currentPageIndex > 0) {
      return PeekInfo(
        page: _pages[_currentPageIndex - 1],
        chapterIndex: _currentChapterIndex,
        pageIndex: _currentPageIndex - 1,
        chapterPageCount: _pages.length,
      );
    }
    // 当前章首页 → 上一章末页
    if (_currentChapterIndex > 0) {
      final prevIdx = _currentChapterIndex - 1;
      final prevChapterPages = _adjacentChapterCache[prevIdx] ??
          (_chapterSource == null ? _paginateChapterWithPipeline(prevIdx) : const []);
      if (prevChapterPages.isNotEmpty) {
        return PeekInfo(
          page: prevChapterPages.last,
          chapterIndex: prevIdx,
          pageIndex: prevChapterPages.length - 1,
          chapterPageCount: prevChapterPages.length,
        );
      }
    }
    return null;
  }

  /// 预热当前章的相邻章(±1)到分页缓存。
  ///
  /// 由 reader_view 在章/页变化后通过 PostFrame 调用(不阻塞当前帧):
  /// 当用户还在章内逐页阅读时, 下一/上一章早已算好入缓存 → 翻到末页时
  /// peekNext 命中缓存(O(1)), 跨章不再卡顿。重排开销被摊到「用户刚进入
  /// 本章、尚未快速翻页」的时刻, 用户无感。
  ///
  /// 幂等: 命中缓存则跳过, 多次调用安全。
  /// 按章加载模式下走异步预取 [_prefetchAdjacentAsync](fire-and-forget)。
  void prefetchAdjacentChapters() {
    // 已销毁或无 UI 监听者(view 已 dispose 并 removeListener)时不再预取——
    // 否则退出页面后排队中的 PostFrame 回调仍会触发章节网络加载。
    if (_disposed || !hasListeners || _book == null || _pageSize == Size.zero) {
      return;
    }
    if (_chapterSource != null) {
      // 异步预取: 不阻塞当前帧, 完成后入缓存供下次 peek 命中。
      _prefetchAdjacentAsync();
      return;
    }
    final next = _currentChapterIndex + 1;
    final prev = _currentChapterIndex - 1;
    _paginateChapterCached(next);
    _paginateChapterCached(prev);
  }

  ///
  /// 翻页动画结束时调用: 把动画展示的目标页真正落到 controller 状态。
  /// 跨章时: 若目标章已预排命中缓存 → 同步落到目标页(流畅); 否则(快速连点未及
  /// 预排)→ 启动异步加载, 落首页, 排完后由异步路径刷新。
  /// 对齐原生 legado `fillPage` → `moveToNext/moveToPrev`。
  void commitTurn(PeekInfo target) {
    if (target.chapterIndex == _currentChapterIndex) {
      if (target.pageIndex != _currentPageIndex) {
        _currentPageIndex = target.pageIndex;
        notifyListeners();
        _scheduleProgressSave();
      }
    } else {
      // 跨章翻页: 切到目标章, 落首页后 _rePaginate(命中缓存则同步就绪)。
      _currentChapterIndex = target.chapterIndex;
      _currentPageIndex = 0;
      _rePaginate();
      // 命中缓存(同步就绪): 尝试落到 peek 展示的目标页。
      if (target.pageIndex < _pages.length) {
        _currentPageIndex = target.pageIndex;
      }
      notifyListeners();
      _scheduleProgressSave();
    }
  }

  /// 从仓库恢复阅读设置(优先当前用户, 回退全局)。
  ///
  /// 典型用法: 宿主在创建 controller 并 attachRepository 后、loadBook 前调用,
  /// 让字号/行距/颜色等恢复到上次状态。无记录时保持默认不动。
  Future<void> loadSettings() async {
    final repo = _repository;
    if (repo == null) return;
    var s =
        (await repo.getSettings(userId: _userId)) ?? await repo.getSettings();
    if (s != null && !_disposed) {
      // scroll 翻页模式已从设置入口下线(章节切换跳变问题待修), 持久化里若存了
      // scroll 则降级为默认 slide, 避免落到 scroll 渲染分支。代码保留, 修好后
      // 移除此降级即可恢复。
      if (s.pageAnimMode == PageAnimMode.scroll) {
        s = s.copyWith(pageAnimMode: PageAnimMode.slide);
      }
      _settings = s;
      _rePaginate();
      notifyListeners();
    }
  }

  /// 把当前书加入书架(保存元信息)。仅在有仓库+用户时生效。
  Future<void> saveToShelf() async {
    final repo = _repository;
    final uid = _userId;
    final book = _book;
    if (repo == null || uid == null || book == null) return;
    await repo.saveBookMeta(uid, book);
  }

  @override
  void dispose() {
    _disposed = true;
    // 取消防抖定时器。注意: 这里不 await flushProgress——dispose 不能是 async。
    // 待落盘的进度若关键, 宿主应在 dispose 前手动调 await flushProgress()。
    // 此处做 best-effort: 若定时器正在等待, 立即触发一次同步落盘(忽略返回 future)。
    final pending = _currentProgress();
    _progressSaveTimer?.cancel();
    _settingsSaveTimer?.cancel();
    _pageSizeTimer?.cancel();
    if (pending != null && _repository != null) {
      unawaited(_repository!.saveProgress(pending).catchError((_) {}));
    }
    if (_repository != null) {
      unawaited(
        _repository!
            .saveSettings(_settings, userId: _userId)
            .catchError((_) {}),
      );
    }
    super.dispose();
  }
}
