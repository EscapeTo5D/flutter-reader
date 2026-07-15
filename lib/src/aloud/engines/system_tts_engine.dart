import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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
  /// (实测「第一次翻页有效、第二次无效」)。段切换完全由 completionHandler
  /// ([_onSpeakComplete]) 驱动, 不依赖 speak 的 future resolve, 故保持默认
  /// `awaitSpeakCompletion=false`, [play] 排入 TTS 队列即返回, 与 [HttpTtsEngine]
  /// 的非阻塞语义一致。
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
    // QUEUE_FLUSH: 清掉之前可能残留的队列(pause/seek 后重启场景)。
    await _tts.setQueueMode(0);
    _setState(AloudState.playing);
    _speakCurrent();
  }

  /// 播放当前段。纯 completion 驱动: 一段播完(completion)再喂下一段,
  /// 不用 QUEUE_ADD(避免 onError/onComplete 双触发导致跳段)。
  ///
  /// **不要加 timeout/重试**。段切换由 [_onSpeakComplete](completionHandler)驱动,
  /// 不依赖 `_tts.speak` 的 future。加 timeout 会把"正在播长段"误判为失败,
  /// 重试 speak 会因 QUEUE_FLUSH 把正在播的段打断 → 段衔接混乱。
  ///
  /// **`_tts.speak` 不 await 阻塞**(保持默认 `awaitSpeakCompletion=false`):
  /// speak 排入 TTS 引擎队列即返回, 整段播完后由 completionHandler 回调推进下一段。
  /// 若 await 阻塞, [play] 会卡住数秒, 上游 `AloudController.start`/翻页跟随的
  /// suspend 窗口随之拉长, 屏蔽用户在阻塞期内的二次翻页。
  ///
  /// 引擎绑定 race(极罕见)已由宿主 `AndroidManifest.xml` 的 `TTS_SERVICE` queries
  /// 声明根治(见 AGENTS.md「朗读功能宿主配置」)。无需 Dart 侧兜底。
  void _speakCurrent() {
    if (_disposed) return;
    if (_currentIndex >= _paragraphs.length) {
      _setState(AloudState.idle); // 章末, 由 Controller 决定翻章
      return;
    }
    _speaking = true;
    final text = _paragraphs[_currentIndex];
    // speak 排队即返回(fire-and-forget)。失败由 errorHandler 回来,
    // 由 _onSpeakError 处理(跳段), 这里无需判返回值。
    _tts.speak(text).catchError((e) {
      debugPrint('[SystemTts] speak 异常: $e');
      if (_speaking) _onSpeakError('speak 异常: $e');
    });
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
      _speakCurrent();
    } else {
      _setState(AloudState.idle); // 章末
    }
  }

  void _onSpeakError(dynamic message) {
    debugPrint('[SystemTts] onError idx=$_currentIndex msg=$message');
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
    _speakCurrent();
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
      _speakCurrent();
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
