import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../aloud_engine.dart';

/// 系统 TTS 引擎(对应原生 legado `TTSReadAloudService`)。
///
/// 底层用 `flutter_tts`(Android `TextToSpeech` / iOS `AVSpeechSynthesizer`)。
///
/// 核心设计(对齐原生 `TTSReadAloudService.play`, **一次塞完整章让引擎无缝衔接**):
/// - **QUEUE_ADD 预排队**: [play]/[resume]/[skipToParagraph] 把当前章剩余所有段
///   一次 `speak` 进引擎队列(`flutter_tts.setQueueMode(QUEUE_ADD)`), 首段用
///   QUEUE_FLUSH 清掉上一章残留。引擎内部负责段间无缝衔接, **不经过 Dart 介入**。
///   这是段衔接流畅的关键 —— 旧的「completion 驱动逐段 speak」会让引擎在每段之间
///   空转(等 Dart 回调再喂下一段), 产生明显停顿。
/// - **completionHandler 只推进游标**: `onComplete` 只 `_currentIndex++` 上报进度,
///   **不再 speak 下一段**(下段早已在引擎队列里)。章末 onComplete → state=idle,
///   由 [AloudController] 决定翻章。
/// - **字符级进度**: `setProgressHandler` 回调提供 `(text, start, end, word)`,
///   start/end 是当前段内字符偏移, 对应原生 `onRangeStart`。
/// - **暂停(无真 pause)**: Android `TextToSpeech` 无 pause API(SDK≥26 才有 workaround
///   且不稳), 用「stop + 记录段首偏移 + resume 从当前段重读」模拟(对齐原生)。
///   iOS `pause` 可调但 resume 不可靠, 故也走 stop-重读。
/// - **错误恢复**: 单段 onError 不中断, 跳到下一段(对齐原生 `onError → nextParagraph`)。
class SystemTtsEngine implements AloudEngine {
  SystemTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  // ─────────── 引擎状态 ───────────
  @override
  AloudEngineType get type => AloudEngineType.system;

  AloudState _state = AloudState.idle;
  @override
  AloudState get state => _state;

  final _stateController = StreamController<AloudState>.broadcast();
  final _progressController = StreamController<AloudProgressEvent>.broadcast();
  @override
  Stream<AloudState> get stateStream => _stateController.stream;
  @override
  Stream<AloudProgressEvent> get progressStream => _progressController.stream;

  // ─────────── 朗读数据 ───────────
  List<String> _paragraphs = const [];
  int _currentIndex = 0;
  double _speed = 1.0;
  bool _disposed = false;
  bool _initialized = false;

  /// 标记当前段是否正在播(避免 completion 与手动 stop 混淆)。
  bool _speaking = false;

  /// `_enqueueAll` 的代际号: 每次 [_enqueueAll]/[stop]/[pause] 自增, 异步 then 链
  /// 在每段执行前校验代际号是否仍匹配, 不匹配则中断(防止快速 play→seek→play 等
  /// 操作导致旧排队的段污染新队列)。
  int _queueGen = 0;

  /// 初始化 flutter_tts(挂回调、设语速)。幂等。
  ///
  /// **不要调 setLanguage**(对齐原生 legado `TTSReadAloudService`: 整个 service 里
  /// 完全没有 setLanguage/isLanguageAvailable 调用)。Android TTS 引擎的默认 locale
  /// 跟随系统语言——手机系统是中文,引擎默认就播中文。强行 `setLanguage('zh-CN')`
  /// 在某些设备上 `Locale.forLanguageTag("zh-CN")` 不被引擎接受(引擎可能只认
  /// `zh-Hans-CN`/`zh_CN_#Hans`),返回 false → locale 设置失败 → speak 用 fallback
  /// locale,可能不出声或播别的语言。
  ///
  /// **不要轮询/等待引擎绑定**: flutter_tts Android 插件内部自带 pending 机制——
  /// `onMethodCall` 在 `ttsStatus == null`(引擎未绑定时)会把方法调用暂存到
  /// `pendingMethodCalls` 队列,待 `onInitListenerWithoutCallback` 回调后自动重放。
  ///
  /// `setSpeechRate` 也走 pending(引擎绑定前调会被排队,不会丢)。
  ///
  /// ⚠️ **不要开 `awaitSpeakCompletion(true)`**: 它会让 `await _tts.speak()` 阻塞
  /// 到整段播完(数秒),导致 [play] 长期不返回 → 上游 `AloudController.start`/
  /// `_restartAloudFromCurrentPage` 跟着阻塞 → 用户翻页跟随功能在阻塞窗口内失效
  /// (实测「第一次翻页有效、第二次无效」)。段切换由引擎队列自动完成,
  /// completionHandler 只推进游标, 故保持默认 `awaitSpeakCompletion=false`。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    _tts.setStartHandler(_onSpeakStart);
    _tts.setCompletionHandler(_onSpeakComplete);
    _tts.setProgressHandler(_onSpeakProgress);
    _tts.setErrorHandler(_onSpeakError);
    // 不设 locale(对齐 legado, 用引擎默认 = 系统语言)。只设语速。
    try {
      await _tts.setSpeechRate(_toSpeechRate(_speed));
    } catch (e) {
      debugPrint('[SystemTts] setSpeechRate 异常(忽略): $e');
    }
  }

  @override
  Future<void> play({
    required List<String> paragraphs,
    required int startIndex,
    required double speed,
  }) async {
    await _ensureInit();
    _paragraphs = paragraphs;
    _currentIndex = startIndex.clamp(0, paragraphs.length);
    _speed = speed;
    await _tts.setSpeechRate(_toSpeechRate(speed));
    _setState(AloudState.playing);
    _enqueueAll(); // 一次塞完整章(首段 FLUSH, 后续 ADD)
  }

  /// 一次把当前章剩余所有段(`_currentIndex..end`)塞进引擎队列。
  ///
  /// 对齐原生 `TTSReadAloudService.play` 的 `for` 循环(首段 QUEUE_FLUSH 清旧队列,
  /// 其余 QUEUE_ADD 追加)。引擎内部负责段间无缝衔接, **不经过 Dart 介入**, 这是
  /// 段衔接流畅的关键(旧实现「播完一段回调到 Dart 再喂下一段」会让引擎在段间
  /// 空转, 产生明显停顿)。
  ///
  /// ⚠️ **所有 `speak` 均 fire-and-forget**(保持默认 `awaitSpeakCompletion=false`)。
  /// 不 await 阻塞, 否则 [play] 会卡住数秒, 上游 `AloudController.start`/翻页跟随的
  /// suspend 窗口随之拉长, 屏蔽用户在阻塞期内的二次翻页。
  ///
  /// 引擎绑定 race(极罕见)已由宿主 `AndroidManifest.xml` 的 `TTS_SERVICE` queries
  /// 声明根治(见 AGENTS.md「朗读功能宿主配置」)。无需 Dart 侧兜底。
  Future<void> _enqueueAll() async {
    if (_disposed) return;
    if (_currentIndex >= _paragraphs.length) {
      _setState(AloudState.idle); // 章末, 由 Controller 决定翻章
      return;
    }
    _speaking = true;
    final gen = ++_queueGen; // 本轮排队代际, 每步校验是否仍最新
    final startIdx = _currentIndex;
    try {
      // 首段 QUEUE_FLUSH(清掉上一章/pause 残留), 其余 QUEUE_ADD 追加。
      // flutter_tts Dart 侧 API 只暴露全局 setQueueMode, 无单次参数; 故先 set 0 再 set 1。
      // iOS 无队列概念, 连续 speak 退化为串行(引擎自动播完再接), 行为可接受。
      await _tts.setQueueMode(0);
      if (_disposed || gen != _queueGen) return;
      await _tts.speak(_paragraphs[startIdx]);
      if (_disposed || gen != _queueGen) return;
      await _tts.setQueueMode(1);
      if (_disposed || gen != _queueGen) return;
      // 追加剩余段(从 startIdx+1 起, 首段已 FLUSH 进队列)。
      for (var i = startIdx + 1; i < _paragraphs.length; i++) {
        _tts.speak(_paragraphs[i]);
      }
    } catch (e) {
      debugPrint('[SystemTts] enqueue 异常: $e');
      if (_speaking && gen == _queueGen) _onSpeakError('enqueue 异常: $e');
    }
  }

  void _onSpeakStart() {
    // 当前段开始播。报一次段首进度(高亮定位到段首)。
    if (_currentIndex < _paragraphs.length) {
      _progressController.add(AloudProgressEvent(
        paragraphIndex: _currentIndex,
        charStartInParagraph: 0,
        charEndInParagraph: 1,
      ));
    }
  }

  void _onSpeakProgress(String text, int start, int end, String word) {
    // 字符级进度(对应原生 onRangeStart)。start/end 是段内字符偏移。
    _progressController.add(AloudProgressEvent(
      paragraphIndex: _currentIndex,
      charStartInParagraph: start,
      charEndInParagraph: end,
    ));
  }

  /// 段播完回调: **只推进游标, 不 speak 下一段**(下段早已在引擎队列里)。
  ///
  /// 对齐原生 `UtteranceProgressListener.onDone → nextParagraph`(只移动 nowSpeak,
  /// 不发起新 speak)。引擎队列自动衔接下一段, 故这里无需介入。
  ///
  /// ⚠️ **`_currentIndex` 的推进必须与引擎播放顺序严格同步**: 引擎按入队顺序播,
  /// onComplete 也按入队顺序回调, 故 `_currentIndex++` 能正确跟踪当前在播段。
  /// 手动 [stop] 触发的是 onCancel(插件 onStop → speak.onCancel), 不会进这里
  /// (`_speaking=false` 后 _onSpeakComplete 早退)。
  void _onSpeakComplete() {
    if (!_speaking) return; // 手动 stop 触发的 complete, 忽略
    _currentIndex++;
    if (_currentIndex >= _paragraphs.length) {
      _speaking = false;
      _setState(AloudState.idle); // 章末, 由 Controller 决定翻章
    }
    // 否则: 下一段已在引擎队列里, 引擎自动播, 这里不做任何事。
    // (进度回调由下一段的 _onSpeakStart/onProgress 上报, _currentIndex 已就位)
  }

  void _onSpeakError(dynamic message) {
    debugPrint('[SystemTts] onError idx=$_currentIndex msg=$message');
    if (!_speaking) return;
    // 对齐原生: onError 只推进游标跳段, 不中断(后续段已在队列里, 引擎自动播)。
    // ⚠️ 不清队列、不重 speak —— 清队列会打断已无缝排好的后续段。
    _currentIndex++;
    if (_currentIndex >= _paragraphs.length) {
      _speaking = false;
      _setState(AloudState.idle);
    }
  }

  // ─────────── 播放控制 ───────────

  @override
  Future<void> pause() async {
    // 对齐原生系统 TTS: 无真 pause, stop + 标记。resume 时从当前段段首重读。
    _speaking = false;
    _queueGen++; // 作废进行中的 _enqueueAll 排队链
    await _tts.stop();
    _setState(AloudState.paused);
  }

  @override
  Future<void> resume() async {
    // 从当前段段首重 play(对齐原生: paragraphStartPos 清零, nowSpeak 不变)。
    // stop 已清空引擎队列, 故 resume 走 _enqueueAll(首段 FLUSH + 后续 ADD)重新排队。
    _setState(AloudState.playing);
    _enqueueAll();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    _queueGen++; // 作废进行中的 _enqueueAll 排队链
    await _tts.stop();
    _setState(AloudState.stopped);
  }

  @override
  Future<void> setRate(double rate) async {
    _speed = rate;
    // 系统 TTS 倍速实时改(对齐原生 setSpeechRate), 无需重下载。
    await _tts.setSpeechRate(_toSpeechRate(rate));
  }

  @override
  Future<void> skipToParagraph(int index) async {
    _speaking = false;
    await _tts.stop();
    _currentIndex = index.clamp(0, _paragraphs.length);
    if (_currentIndex < _paragraphs.length) {
      _setState(AloudState.playing);
      _enqueueAll();
    } else {
      _setState(AloudState.idle);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _speaking = false;
    await _tts.stop();
    await _stateController.close();
    await _progressController.close();
  }

  void _setState(AloudState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// UI 倍率(1.0=正常, 0.5~5.0) → flutter_tts speechRate 参数。
  ///
  /// flutter_tts 的 speechRate 不是 0~1 统一语义, 而是各平台透传值, 需分平台换算
  /// 才能对齐原生 legado(Android 直接 `TextToSpeech.setSpeechRate((p+5)/10)`, 即
  /// UI 倍率 0.5..5.0):
  ///
  /// - **Android**: `flutter_tts` Android 插件内部执行
  ///   `tts.setSpeechRate(rate * 2.0f)`(见 `FlutterTtsPlugin.kt:394`), 即它收到的
  ///   参数 = Android `TextToSpeech` 值 ÷ 2。原生 legado 透传 UI 倍率(0.5..5.0),
  ///   故这里给 flutter_tts 的值 = UI 倍率 ÷ 2(0.25..2.5), 插件 ×2 后还原成
  ///   0.5..5.0, 与 legado 完全一致。
  /// - **iOS**: `flutter_tts` 直接把参数赋给 `AVSpeechUtterance.rate`(0..1,
  ///   `AVSpeechUtteranceDefaultSpeechRate ≈ 0.5`)。UI 倍率 1.0 → 0.5 正常,
  ///   上限 clamp 1.0(`AVSpeechUtteranceMaxSpeechRate`)。
  ///
  /// 旧实现误用 `(rate × 0.5).clamp(0,1)` 统一映射, Android 端倍率永远 ≤ 1.0
  /// (即拉满滑块也只 1 倍速), 与原生 5 倍速上限严重不符。
  double _toSpeechRate(double rate) {
    if (!kIsWeb && Platform.isIOS) {
      return (rate * 0.5).clamp(0.0, 1.0);
    }
    // Android(及 Web 兜底): UI 倍率 ÷ 2 透传给 flutter_tts, 插件内部 ×2 还原。
    return (rate / 2).clamp(0.0, 2.5);
  }
}
