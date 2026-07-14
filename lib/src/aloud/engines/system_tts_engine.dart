import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../aloud_engine.dart';

/// 系统 TTS 引擎(对应原生 legado `TTSReadAloudService`)。
///
/// 底层用 `flutter_tts`(Android `TextToSpeech` / iOS `AVSpeechSynthesizer`)。
///
/// 核心设计(对齐原生):
/// - **QUEUE 模式**: 利用 `flutter_tts.setQueueMode`(Android 原生 QUEUE_FLUSH /
///   QUEUE_ADD, 与原生 legado 一致)。第一段 play 时用 FLUSH 清队列, 后续段用 ADD
///   排队连续播。iOS 无此概念, 退化为串行(由 completionHandler 驱动下一段)。
/// - **字符级进度**: `setProgressHandler` 回调提供 `(text, start, end, word)`,
///   start/end 是当前段内字符偏移, 对应原生 `UtteranceProgressListener.onRangeStart`。
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

  /// 初始化 flutter_tts(挂回调、设语言)。幂等。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(_toSpeechRate(_speed));
    _tts.setStartHandler(_onSpeakStart);
    _tts.setCompletionHandler(_onSpeakComplete);
    _tts.setProgressHandler(_onSpeakProgress);
    _tts.setErrorHandler(_onSpeakError);
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
    // QUEUE_FLUSH: 清掉之前可能残留的队列(pause/seek 后重启场景)。
    await _tts.setQueueMode(0);
    _setState(AloudState.playing);
    await _speakCurrent();
  }

  /// 播放当前段。纯 completion 驱动: 一段播完(completion)再喂下一段,
  /// 不用 QUEUE_ADD(避免 onError/onComplete 双触发导致跳段)。
  Future<void> _speakCurrent() async {
    if (_disposed) return;
    if (_currentIndex >= _paragraphs.length) {
      _setState(AloudState.idle); // 章末, 由 Controller 决定翻章
      return;
    }
    _speaking = true;
    await _tts.speak(_paragraphs[_currentIndex]);
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

  Future<void> _onSpeakComplete() async {
    if (!_speaking) return; // 手动 stop 触发的 complete, 忽略
    _speaking = false;
    _currentIndex++;
    if (_currentIndex < _paragraphs.length) {
      // 纯 completion 驱动: FLUSH + 喂下一段。不用 QUEUE_ADD。
      await _tts.setQueueMode(0);
      await _speakCurrent();
    } else {
      _setState(AloudState.idle); // 章末
    }
  }

  void _onSpeakError(dynamic message) {
    if (!_speaking) return;
    _speaking = false;
    // 对齐原生: onError 跳段, 不重试、不中断。
    _currentIndex++;
    if (_currentIndex < _paragraphs.length) {
      _speakCurrent();
    } else {
      _setState(AloudState.idle);
    }
  }

  // ─────────── 播放控制 ───────────

  @override
  Future<void> pause() async {
    // 对齐原生系统 TTS: 无真 pause, stop + 标记。resume 时从当前段段首重读。
    _speaking = false;
    await _tts.stop();
    _setState(AloudState.paused);
  }

  @override
  Future<void> resume() async {
    // 从当前段段首重 play(对齐原生: paragraphStartPos 清零, nowSpeak 不变)。
    _setState(AloudState.playing);
    await _tts.setQueueMode(0);
    await _speakCurrent();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
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
      await _tts.setQueueMode(0);
      await _speakCurrent();
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

  /// UI 倍率(1.0=正常, 0.5~5.0) → flutter_tts speechRate([0.0, 1.0])。
  ///
  /// flutter_tts 的 speechRate 语义: 0.0 最慢, 1.0 最快, 平台默认约 0.5。
  /// 这里把 UI 倍率线性映射: 1.0 → 0.5(默认), 0.5 → 0.25(慢), 2.0 → 1.0(快)。
  double _toSpeechRate(double rate) => (rate * 0.5).clamp(0.0, 1.0);
}
