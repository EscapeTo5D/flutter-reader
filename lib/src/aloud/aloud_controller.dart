import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/controller/reading_controller.dart';
import '../core/storage/reader_repository.dart';
import '../core/storage/reading_progress.dart';
import 'aloud_cursor.dart';
import 'aloud_engine.dart';
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
    AudioHandler? audioHandler,
  }) : _audioHandler = audioHandler ?? const NoopAudioHandler();

  /// 关联的阅读控制器(翻页/取页/取预处理文本都通过它)。
  final ReadingController reader;

  /// 可选的持久化仓库(null = 纯内存, 不持久化进度)。
  final ReaderRepository? repository;

  final AudioHandler _audioHandler;

  // ─────────── 引擎 ───────────
  AloudEngine? _engine;
  AloudEngineType _engineType = AloudEngineType.system;
  HttpTtsConfig? _httpConfig;

  // ─────────── 朗读状态 ───────────
  AloudState _state = AloudState.idle;
  AloudCursor? _cursor;
  double _rate = 1.0;

  /// 当前章的切段结果([AloudParagraph.text] 列表)。
  List<AloudParagraph> _paragraphs = const [];

  /// 朗读高亮版本号(每次进度推进自增, 驱动 [ReaderView] 重绘)。
  int _aloudVersion = 0;

  StreamSubscription<AloudState>? _stateSub;
  StreamSubscription<AloudProgressEvent>? _progressSub;
  Timer? _saveDebounce;
  bool _disposed = false;

  /// 章末续读重入守卫: 防止引擎 idle 事件多次触发导致并发翻章。
  bool _advancing = false;

  // ─────────── 对外 getters ───────────

  AloudState get state => _state;
  AloudCursor? get cursor => _cursor;
  bool get isPlaying => _state == AloudState.playing;
  bool get isPaused => _state == AloudState.paused;
  double get rate => _rate;
  int get aloudVersion => _aloudVersion;
  AloudEngineType get engineType => _engineType;

  @override
  void dispose() {
    _disposed = true;
    _saveDebounce?.cancel();
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

  Future<void> setRate(double r) async {
    _rate = r;
    await _engine?.setRate(r);
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
    _scheduleProgressSave();
  }

  /// 翻页联动: 当前朗读位置越过下一页边界 → 静默翻页。
  ///
  /// 对齐原生 legado `readAloudNumber + charOffset > getReadLength(pageIndex+1)`。
  /// 用 [ReadingController.setCurrentPageSilent] 静默翻(无动画, 不 notify 整树)。
  void _maybeFlipPage() {
    final c = _cursor;
    if (c == null) return;
    final pages = reader.pages;
    if (pages.isEmpty) return;
    final curPage = reader.currentPageIndex;
    // 当前朗读偏移落在哪一页。
    final targetPage = reader.pageIndexForCharOffset(c.chapterCharOffset);
    if (targetPage != curPage && targetPage >= 0 && targetPage < pages.length) {
      reader.setCurrentPageSilent(c.chapterIndex, targetPage);
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
      reader.nextChapter();
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
}
