import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/controller/reading_controller.dart';
import '../core/storage/reader_repository.dart';
import '../core/storage/reading_progress.dart';
import 'aloud_cursor.dart';
import 'aloud_engine.dart';
import 'aloud_settings.dart';
import 'audio_handler.dart';
import 'engines/system_tts_engine.dart';
import 'engines/http_tts_engine.dart';
import 'http_tts_config.dart';
import 'text_slicer.dart';

export 'aloud_engine.dart' show AloudEngineType, AloudState, AloudProgressEvent;
export 'aloud_cursor.dart' show AloudCursor;

/// 朗读控制器(对外主入口, 对应原生 legado `model/ReadAloud.kt`)。
///
/// 职责:
/// - 管理 [AloudEngine] 实例(系统 TTS / HTTP TTS), 引擎切换。
/// - 文本切段([TextSlicer]), 从当前页首段定位朗读起点。
/// - 进度状态机([AloudCursor]), 引擎进度事件 → 更新光标 → 翻页/翻章联动。
/// - 进度持久化([AloudCursor.chapterCharOffset] → [ReadingProgress], 复用现有进度表)。
/// - 朗读高亮版本号([aloudVersion]), 触发 [ReaderView] 重绘当前段高亮。
///
/// **与 [ReadingController] 的关系**: 本控制器通过构造注入 [ReadingController]
/// 引用, 调它的 public 方法做翻页/取页/取预处理文本, **不修改它的字段**。
/// [ReadingController] 对朗读子系统完全无感知。
class AloudController extends ChangeNotifier {
  AloudController({
    required this.reader,
    this.repository,
    AloudSettings? initialSettings,
    AudioHandler? audioHandler,
  })  : _audioHandler = audioHandler ?? const NoopAudioHandler(),
        _rate = initialSettings?.rate ?? AloudSettings.defaults.rate,
        _engineType =
            initialSettings?.engineType ?? AloudSettings.defaults.engineType,
        _followSysRate = initialSettings?.followSysRate ??
            AloudSettings.defaults.followSysRate {
    // 监听 reader 的页/章变化: 朗读运行中用户手动翻页/翻章 → 跟随到新页重读。
    // 对齐原生 legado `ReadBook.curPageChanged()` 统一收口。防环见 [_onReaderUpdate]。
    reader.addListener(_onReaderUpdate);
  }

  /// 关联的阅读控制器(翻页/取页/取预处理文本都通过它)。
  final ReadingController reader;

  /// 可选的持久化仓库(null = 纯内存, 不持久化进度)。
  final ReaderRepository? repository;

  final AudioHandler _audioHandler;

  // ─────────── 引擎 ───────────
  AloudEngine? _engine;
  AloudEngineType _engineType;
  HttpTtsConfig? _httpConfig;

  // ─────────── 朗读状态 ───────────
  AloudState _state = AloudState.idle;
  AloudCursor? _cursor;
  double _rate;
  bool _followSysRate;

  /// 当前章的切段结果([AloudParagraph.text] 列表)。
  List<AloudParagraph> _paragraphs = const [];

  /// 朗读高亮版本号(每次进度推进自增, 驱动 [ReaderView] 重绘)。
  int _aloudVersion = 0;

  StreamSubscription<AloudState>? _stateSub;
  StreamSubscription<AloudProgressEvent>? _progressSub;
  Timer? _saveDebounce;
  Timer? _settingsSaveDebounce;
  bool _disposed = false;

  /// 章末续读重入守卫: 防止引擎 idle 事件多次触发导致并发翻章。
  bool _advancing = false;

  /// 防环标志: 朗读自己改 reader 页码(_maybeFlipPage/_advanceToNextChapter)时
  /// 置 true, 让 [_onReaderUpdate] 跳过(避免朗读自动翻页又触发重读成环)。
  /// ChangeNotifier.notifyListeners 是同步的, 故标志在同步调用窗口内有效。
  bool _suspendReaderListener = false;

  // ─────────── 对外 getters ───────────

  AloudState get state => _state;
  AloudCursor? get cursor => _cursor;

  /// 当前朗读段落在章内的**绝对范围 [start, end)**(字符偏移)。
  ///
  /// 用于朗读高亮: 对齐原生 `upPageAloudSpan` 高亮**整段**(非仅已读部分)。
  /// start = 段首(cursor.chapterCharOffset - charOffsetInParagraph),
  /// end = 下一段首或末段尾(取下一段 charOffsetInChapter, 末段取一个超大值兜底)。
  /// 无 cursor 或段落越界时返回 null。
  ({int start, int end})? get currentParagraphRange {
    final c = _cursor;
    if (c == null) return null;
    final start = c.chapterCharOffset - c.charOffsetInParagraph;
    var end = start;
    if (c.paragraphIndex + 1 < _paragraphs.length) {
      end = _paragraphs[c.paragraphIndex + 1].charOffsetInChapter;
    } else {
      // 末段: 段首 + 段文本长度(段尾, 含不到下一章)。
      end = start + _paragraphs[c.paragraphIndex].text.length;
    }
    return (start: start, end: end);
  }

  bool get isPlaying => _state == AloudState.playing;
  bool get isPaused => _state == AloudState.paused;
  double get rate => _rate;
  /// 跟随系统语速(对齐原生 `ttsFollowSys`, 默认 true)。
  ///
  /// ⚠️ 本轮仅持久化开关态, true 时的「读系统 TTS 默认语速」逻辑未实现
  /// (留 TODO): 当前 true 时仍用 [rate] 字段值(默认 1.0)。Android 无公开 API
  /// 读系统 TTS rate, iOS 可读 `AVSpeechUtteranceDefaultSpeechRate`——待后续。
  bool get followSysRate => _followSysRate;
  int get aloudVersion => _aloudVersion;
  AloudEngineType get engineType => _engineType;

  @override
  void dispose() {
    _disposed = true;
    reader.removeListener(_onReaderUpdate);
    _saveDebounce?.cancel();
    _settingsSaveDebounce?.cancel();
    _stateSub?.cancel();
    _progressSub?.cancel();
    _engine?.dispose();
    _audioHandler.dispose();
    super.dispose();
  }

  void _setState(AloudState s) {
    if (_disposed) return;
    _state = s;
    _audioHandler.notifyState(s);
    notifyListeners();
  }

  // ─────────── 配置加载 ────────────────────────────────────────────

  /// 从仓库异步加载朗读配置(语速/引擎类型/跟随系统)并应用到内存。
  ///
  /// 供宿主在构造(同步注入 [initialSettings] 不可行时, 如需先 await repo)后调用,
  /// 典型用法: `initState` 同步构造 controller, 紧接着 `await loadSettings()`。
  /// - 未配置(repo 返回 null)→ 保持构造时的初值([AloudSettings.defaults] 或注入值)。
  /// - 已配置 → 覆盖内存字段(**不触发持久化**, 因是读回已存数据), 通知监听器一次。
  /// - 正在朗读时不改语速/引擎(避免中断), 仅 followSysRate 同步。
  Future<void> loadSettings() async {
    final repo = repository;
    if (repo == null || _disposed) return;
    final s = await repo.getAloudSettings();
    if (_disposed) return; // await 期间可能已 dispose。
    if (s == null) return; // 未配置, 保持初值。
    // 引擎实例若已创建且 type 变了, 丢弃旧实例(懒重建); 未创建则无需动。
    // ⚠️ 必须先比对再赋值: 若先 _engineType = s.engineType 再比, 条件恒 false。
    if (_engine != null && _engineType != s.engineType) {
      _engine?.dispose();
      _engine = null;
    }
    _engineType = s.engineType;
    _followSysRate = s.followSysRate;
    // 语速: 若正在朗读, 不实时改(避免中断); 否则静默设字段。
    if (_state != AloudState.playing) {
      _rate = s.rate;
    }
    // 读回的语速同步到已创建的引擎实例, 修复「loadSettings 在首次 start 之后
    // 才返回」的竞态: 该窗口内引擎已用初值 1.0 开始播, 此处让它追上持久化值。
    // 用 _rate(已按上方规则更新, playing 时保持原值), 非引擎初值。
    final engine = _engine;
    if (engine != null && _state != AloudState.playing) {
      await engine.setRate(_rate);
    }
    notifyListeners();
  }

  // ─────────── 引擎选择 ───────────

  /// 选择引擎类型。切到 HTTP TTS 需提供 [httpConfig]。
  ///
  /// 若当前正在朗读, 会先停止(对齐原生 `upReadAloudClass` 的 stop-restart 时序)。
  Future<void> selectEngine(
    AloudEngineType type, {
    HttpTtsConfig? httpConfig,
  }) async {
    if (_state != AloudState.idle && _state != AloudState.stopped) {
      await stop();
    }
    _engineType = type;
    if (type == AloudEngineType.http) {
      _httpConfig = httpConfig;
    }
    _engine = null; // 懒创建, 下次 play 时按 type 新建
    _scheduleSettingsSave();
    notifyListeners();
  }

  Future<AloudEngine> _ensureEngine() async {
    if (_engine != null) return _engine!;
    switch (_engineType) {
      case AloudEngineType.system:
        _engine = SystemTtsEngine();
        break;
      case AloudEngineType.http:
        if (_httpConfig == null) {
          throw StateError('HTTP TTS 引擎需要先配置 HttpTtsConfig');
        }
        _engine = HttpTtsEngine(config: _httpConfig!);
    }
    await _audioHandler.bind(_engine!);
    _wireEngine(_engine!);
    return _engine!;
  }

  void _wireEngine(AloudEngine engine) {
    _stateSub?.cancel();
    _progressSub?.cancel();
    _stateSub = engine.stateStream.listen(_onEngineState);
    _progressSub = engine.progressStream.listen(_onEngineProgress);
  }

  // ─────────── 播放控制 ───────────

  /// 开始朗读。默认从当前页首段; 传 [chapterIndex]/[charOffset] 可指定起点。
  Future<void> start({int? chapterIndex, int? charOffset}) async {
    if (_disposed) return;
    await _ensureEngine();
    _setState(AloudState.preparing);
    // 快照章索引(避免 await 期间 reader.currentChapterIndex 被并发改动)。
    final chIdx = chapterIndex ?? reader.currentChapterIndex;
    final startOffset = charOffset ?? reader.charOffsetForCurrentPage();
    await _loadChapterAndPlay(chIdx, charOffset: startOffset);
  }

  /// 加载指定章的切段并播放(供 [start] 与 [_advanceToNextChapter] 共用)。
  ///
  /// [chapterIndex] 是调用方快照的章索引, 内部全程用此值, **不再读
  /// `reader.currentChapterIndex`** —— 避免 await 期间被并发改动(TOCTOU)。
  /// [charOffset] 指定起始段定位(段首偏移 >= charOffset); null 时从段 0 起。
  Future<void> _loadChapterAndPlay(int chapterIndex, {int? charOffset}) async {
    final content = await reader.chapterProcessedContent(chapterIndex);
    if (content == null || content.isEmpty) {
      _setState(AloudState.error);
      return;
    }
    _paragraphs = TextSlicer.slice(content);
    if (_paragraphs.isEmpty) {
      _setState(AloudState.error);
      return;
    }

    // 定位起始段: 用 charOffset 找第一个 charOffsetInChapter >= charOffset 的段。
    var startIdx = 0;
    if (charOffset != null) {
      for (var i = 0; i < _paragraphs.length; i++) {
        if (_paragraphs[i].charOffsetInChapter >= charOffset) {
          startIdx = i;
          break;
        }
        startIdx = i; // 越往后越接近, 兜底取最后一个
      }
    }

    _cursor = AloudCursor(
      chapterIndex: chapterIndex,
      chapterCharOffset: _paragraphs[startIdx].charOffsetInChapter,
      paragraphIndex: startIdx,
      charOffsetInParagraph: 0,
    );
    _bumpVersion();

    final engine = _engine;
    if (engine != null) {
      final texts = _paragraphs.map((p) => p.text).toList();
      await engine.play(paragraphs: texts, startIndex: startIdx, speed: _rate);
    }
  }

  Future<void> pause() async => _engine?.pause();
  Future<void> resume() async => _engine?.resume();

  Future<void> stop() async {
    await _engine?.stop();
    _cursor = null;
    _setState(AloudState.idle);
  }

  Future<void> nextParagraph() async {
    final c = _cursor;
    if (c == null) return;
    await _engine?.skipToParagraph(c.paragraphIndex + 1);
  }

  Future<void> previousParagraph() async {
    final c = _cursor;
    if (c == null) return;
    if (c.paragraphIndex > 0) {
      await _engine?.skipToParagraph(c.paragraphIndex - 1);
    }
  }

  /// 切到上一章(对齐原生 ReadAloudDialog 的 tv_pre → moveToPrevChapter)。
  ///
  /// 朗读弹窗底栏的「上一章」文字按钮调用。透传给 ReadingController 做章级
  /// 翻页, 朗读引擎随后按新章内容续读(若正在朗读)。
  void previousChapter() => reader.previousChapter();

  /// 切到下一章(对齐原生 tv_next → moveToNextChapter)。
  void nextChapter() => reader.nextChapter();

  /// 设置语速倍率(1.0=正常)并实时应用到引擎, 同时防抖落盘。
  Future<void> setRate(double r) async {
    _rate = r;
    await _engine?.setRate(r);
    _scheduleSettingsSave();
    notifyListeners();
  }

  /// 设置「跟随系统语速」开关, 防抖落盘。
  ///
  /// ⚠️ 本轮仅持久化开关态; true 时实际仍用 [rate] 字段(读系统 rate 逻辑留 TODO)。
  Future<void> setFollowSysRate(bool value) async {
    _followSysRate = value;
    _scheduleSettingsSave();
    notifyListeners();
  }

  // ─────────── 引擎事件处理 ───────────

  void _onEngineState(AloudState s) {
    if (_disposed) return;
    // 引擎播完最后一段(章末) → 尝试翻下一章续读。
    if (s == AloudState.idle && _state == AloudState.playing) {
      _advanceToNextChapter();
      return;
    }
    _setState(s);
  }

  void _onEngineProgress(AloudProgressEvent e) {
    if (_disposed) return;
    if (e.paragraphIndex >= _paragraphs.length) return;
    final para = _paragraphs[e.paragraphIndex];
    _cursor = AloudCursor(
      chapterIndex: reader.currentChapterIndex,
      chapterCharOffset: para.charOffsetInChapter + e.charEndInParagraph,
      paragraphIndex: e.paragraphIndex,
      charOffsetInParagraph: e.charEndInParagraph,
    );
    _audioHandler.notifyProgress(e);
    _maybeFlipPage();
    _bumpVersion();
    // notifyListeners 驱动 ReaderView._onAloudUpdate → setState → _TextLinePainter
    // 重建 → _markAloud 按新 cursor 重标高亮。⚠️ 必须 notify: 段落推进时若未翻页
    // (同页内换段), 无任何其他途径触发重绘 → 高亮静止不跟随段。
    // 对齐原生 legado: TTS_PROGRESS 事件每次段落变化都 upContent() 全量重绘。
    // 频率低(每几秒一段), notify 整树开销可接受。
    notifyListeners();
    _scheduleProgressSave();
  }

  // ─────────── 翻页跟随朗读(反向联动: 翻页 → 重读) ──────────────────
  //
  // 对齐原生 legado `ReadBook.curPageChanged()`(`ReadBook.kt:473-487`): 用户翻页/
  // 翻章后, 若 TTS 运行中, 朗读跟随到新页起始段重新朗读, 保持原播放/暂停态。
  // 原生 ReadView 的触摸/点击完全不感知朗读状态, 所有响应集中在 curPageChanged。
  // Flutter 端等价: reader 的 notify 是所有翻页/翻章的统一下游出口, 监听它即可。

  /// reader 页/章变化回调(挂在 reader.addListener)。
  ///
  /// 仅在朗读运行中(playing/paused)响应; 检测 reader 当前页/章是否偏离了 cursor
  /// 所在位置 → 偏离则用户主动翻走了, 从新页起始段重读。
  ///
  /// **防环**: 朗读自己的 [_maybeFlipPage](自动翻页)/[_advanceToNextChapter](章末
  /// 续读)也会改 reader 页码并 notify, 此时 [_suspendReaderListener]=true, 直接
  /// return 不重读。区分依据: 朗读自动翻页后 cursor 所在页 == reader 当前页
  /// (因为是按 cursor 翻的); 用户手动翻页则 reader 页 ≠ cursor 页。
  void _onReaderUpdate() {
    if (_disposed || _suspendReaderListener) return;
    // 只在朗读运行中(playing/paused)才响应; idle/stopped 不干预用户翻页。
    if (!isPlaying && !isPaused) return;
    final c = _cursor;
    if (c == null) return;
    final readerCh = reader.currentChapterIndex;
    if (readerCh != c.chapterIndex) {
      // 章变了 → 用户翻章, 重读到新章当前页起始段。
      _restartAloudFromCurrentPage();
    } else {
      // 章没变 → 章内翻页。cursor 落在哪一页?
      final cursorPage = reader.pageIndexForCharOffset(c.chapterCharOffset);
      if (cursorPage != reader.currentPageIndex) {
        // reader 页 ≠ cursor 页 → 用户翻走了, 重读。
        _restartAloudFromCurrentPage();
      }
      // cursorPage == currentPageIndex → 是 _maybeFlipPage 朗读自己触发的翻页
      // (按 cursor 翻的, 翻完页码一致), 忽略。防环的第二道保险。
    }
  }

  /// 从 reader 当前页起始段重新朗读, 保持原播放/暂停态。
  ///
  /// 对齐原生 `curPageChanged → readAloud(!pause)`: start() 无参版本从
  /// `reader.charOffsetForCurrentPage()`(当前页首段)起读。暂停态时 start 后再 pause,
  /// 对齐原生「保持 pause 字段」语义。
  Future<void> _restartAloudFromCurrentPage() async {
    if (_disposed) return;
    final wasPaused = isPaused;
    await start(); // 无参 = 从 reader 当前页起始段(章/页已是用户翻到的新位置)
    if (!_disposed && wasPaused) {
      await pause(); // 恢复暂停态(对齐原生保持 pause)
    }
  }

  /// 翻页联动: 当前朗读位置越过下一页边界 → 自动翻到朗读所在页。
  ///
  /// 对齐原生 legado `readAloudNumber + charOffset > getReadLength(pageIndex+1)`
  /// → 翻页(无动画, 直接换页内容)。用 [ReadingController.setCurrentPageIndex]
  /// **带 notify**(非 silent), 因为分页模式(slide/cover/sim/none)的页面内容
  /// 切换靠 controller notify 触发 reader_view rebuild; silent 只给 scroll 模式
  /// 逐像素滚动用(它有自己的 handler 局部重绘), 朗读走分页内容路径必须 notify,
  /// 否则页面内容不变 → 看不到自动翻页(曾用 silent 导致不翻的 bug)。
  void _maybeFlipPage() {
    final c = _cursor;
    if (c == null) return;
    final pages = reader.pages;
    if (pages.isEmpty) return;
    final curPage = reader.currentPageIndex;
    // 当前朗读偏移落在哪一页。
    final targetPage = reader.pageIndexForCharOffset(c.chapterCharOffset);
    if (targetPage != curPage && targetPage >= 0 && targetPage < pages.length) {
      // 章/页同源(_onEngineProgress 设 cursor.chapterIndex = reader.currentChapterIndex),
      // 故只翻页不翻章。setCurrentPageIndex 内部带 notify + 防抖落盘。
      // ⚠️ 防环: 这是朗读自己触发的翻页, 挂 suspend 标志让 _onReaderUpdate 跳过,
      // 否则会误判为「用户翻页」→ 触发 _restartAloudFromCurrentPage → 朗读从头重读。
      // notifyListeners 同步触发 listener, 故标志在调用窗口内有效, 调完即复位。
      _suspendReaderListener = true;
      reader.setCurrentPageIndex(targetPage);
      _suspendReaderListener = false;
    }
  }

  /// 章末续读下一章。
  ///
  /// 对齐原生 `nextChapter → ReadBook.moveToNextChapter → curPageChanged → readAloud`。
  /// 1. reader.nextChapter()(同步翻章 + 重排)。
  /// 2. 取新章预处理文本, 重新切段。
  /// 3. 引擎 play 新章(从段 0 开始)。
  Future<void> _advanceToNextChapter() async {
    // 重入守卫: 引擎 idle 事件可能多次触发, 防止并发翻章。
    if (_advancing) return;
    if (reader.currentChapterIndex >= reader.totalChapters - 1) {
      // 已是末章, 停止朗读。
      _cursor = null;
      _setState(AloudState.idle);
      return;
    }
    _advancing = true;
    try {
      // 快照目标章索引(C2 修复): 全程用 targetChapter, 不再读 reader.currentChapterIndex。
      final targetChapter = reader.currentChapterIndex + 1;
      // ⚠️ 防环: 章末续读是朗读自己触发的翻章, 挂 suspend 标志让 _onReaderUpdate
      // 跳过(nextChapter 的 notify 否则会触发 _restartAloudFromCurrentPage)。
      // 紧接的 _loadChapterAndPlay 会重新设 cursor 到新章, 故此处只需挡住 notify 回调。
      _suspendReaderListener = true;
      reader.nextChapter();
      _suspendReaderListener = false;
      await _loadChapterAndPlay(targetChapter);
    } finally {
      _advancing = false;
    }
  }

  void _bumpVersion() {
    _aloudVersion++;
  }

  // ─────────── 进度持久化 ───────────

  /// 防抖落盘(对齐 ReadingController 的 1.5s 防抖策略)。
  void _scheduleProgressSave() {
    if (repository == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 1500), _persistProgress);
  }

  Future<void> _persistProgress() async {
    final c = _cursor;
    final repo = repository;
    if (c == null || repo == null || _disposed) return;
    final book = reader.book;
    final uid = reader.userId;
    if (book == null || uid == null) return;
    await repo.saveProgress(ReadingProgress(
      userId: uid,
      bookId: book.id,
      chapterIndex: c.chapterIndex,
      chapterCharOffset: c.chapterCharOffset,
      pageIndex: reader.currentPageIndex,
      lastReadAt: DateTime.now(),
    ));
  }

  /// 立即落盘(dispose 前调)。
  Future<void> flushProgress() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await _persistProgress();
  }

  // ─────────── 配置持久化 ──────────────────────────────────────────
  //
  // 朗读配置(语速/引擎类型/跟随系统)是全局的, 对齐原生 legado 的 SharedPreferences。
  // 与进度(按 userId+bookId 隔离)不同: 配置全局存, 复用 settings 表的 KV 行
  // (key='__aloud__')。改 setRate/selectEngine/setFollowSysRate 后防抖落盘。

  /// 防抖落盘(1.5s, 与进度同节奏; 改语速/引擎/跟随系统后调)。
  void _scheduleSettingsSave() {
    if (repository == null) return;
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce =
        Timer(const Duration(milliseconds: 1500), _persistAloudSettings);
  }

  Future<void> _persistAloudSettings() async {
    final repo = repository;
    if (repo == null || _disposed) return;
    await repo.saveAloudSettings(AloudSettings(
      rate: _rate,
      engineType: _engineType,
      followSysRate: _followSysRate,
    ));
  }

  /// 立即落盘配置(dispose 前调)。
  Future<void> flushSettings() async {
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = null;
    await _persistAloudSettings();
  }
}
