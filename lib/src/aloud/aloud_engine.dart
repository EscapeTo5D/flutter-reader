import 'dart:async';

/// 朗读引擎类型。
enum AloudEngineType {
  /// 系统 TTS(Android `TextToSpeech` / iOS `AVSpeechSynthesizer`)。
  system,

  /// HTTP TTS(在线语音合成服务, 拉回 mp3 播放)。
  http,
}

/// 朗读状态机。
///
/// 状态流转:
/// - `start()` → [preparing] → [playing]
/// - 用户暂停 → [paused] → `resume()` → [playing]
/// - 用户停止 / 章末无后续 → [idle]
/// - 引擎错误 → [error]
enum AloudState { idle, preparing, playing, paused, stopped, error }

/// 引擎向上报告的逐字进度事件。
///
/// 控制器据此更新 [AloudCursor] 并触发翻页联动与高亮。
/// - 系统 TTS: 由 `flutter_tts` 的字符级进度回调(`onRangeStart` 等价)生成, 精度高。
/// - HTTP TTS: 由音频时长估算生成(`position / duration * charCount`), 精度近似。
class AloudProgressEvent {
  /// 当前段在切段数组中的下标(= `nowSpeak`)。
  final int paragraphIndex;

  /// 段内已读字符起始偏移(含)。
  final int charStartInParagraph;

  /// 段内已读字符结束偏移(不含)。高亮区间 = [charStartInParagraph, charEndInParagraph)。
  final int charEndInParagraph;

  const AloudProgressEvent({
    required this.paragraphIndex,
    required this.charStartInParagraph,
    required this.charEndInParagraph,
  });

  @override
  String toString() =>
      'AloudProgressEvent(para=$paragraphIndex, [$charStartInParagraph,$charEndInParagraph))';
}

/// 朗读引擎抽象(对应原生 legado `BaseReadAloudService`)。
///
/// 职责: 接收「段落列表 + 起始段下标」, 按引擎自身方式播完, 向上报告
/// [AloudProgressEvent], 响应 play/pause/resume/stop/setRate/skipToParagraph。
///
/// **不持有**章节坐标 / 翻页逻辑 —— 那是 [AloudController] 的职责。引擎只管
/// 「一段话怎么发声、何时播完、当前读到段内哪个字符」。
///
/// 暂停语义(对齐原生):
/// - 系统 TTS: Android 原生 `TextToSpeech` 无真 pause, 用「stop + 回段首重读」模拟。
/// - HTTP TTS: `just_audio` 原生 pause/resume, 保留音频位置。
abstract class AloudEngine {
  /// 引擎类型。
  AloudEngineType get type;

  // ─────────── 状态(读取当前值 + 监听变化) ───────────

  AloudState get state;
  Stream<AloudState> get stateStream;
  Stream<AloudProgressEvent> get progressStream;

  // ─────────── 播放控制 ───────────

  /// 播放。[paragraphs] 已切段并过滤纯标点段; 从 [startIndex] 段开始。
  /// [speed] 是相对倍率(1.0 = 正常速度)。
  Future<void> play({
    required List<String> paragraphs,
    required int startIndex,
    required double speed,
  });

  /// 暂停。系统 TTS = stop + 标记段首; HTTP TTS = 原生 pause。
  Future<void> pause();

  /// 恢复。系统 TTS = 从当前段首重 play; HTTP TTS = 原生 resume。
  Future<void> resume();

  /// 停止(引擎级, 不清控制器坐标)。
  Future<void> stop();

  /// 调倍速。
  ///
  /// 语义(对齐原生 legado `upTtsSpeechRate`):
  /// - **playing 态**: 必须打断当前朗读并从当前段段首用新速率重新开始(系统 TTS
  ///   stop+重新入队, HTTP 后端合成重下载, HTTP 播放器变速)。否则已排队的 utterance
  ///   沿用旧速率, 改速无效。
  /// - **paused/idle 态**: 只更新内部字段, 下次 play/resume 自然用新速率。
  Future<void> setRate(double rate);

  /// 跳到指定段(上下段按钮用)。会中断当前段。
  Future<void> skipToParagraph(int index);

  /// 释放资源。
  Future<void> dispose();
}
