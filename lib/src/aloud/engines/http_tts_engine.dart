import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../aloud_engine.dart';
import '../http_tts_config.dart';

/// HTTP TTS 引擎(对应原生 legado `HttpReadAloudService`)。
///
/// 底层用 `just_audio`(对应原生 ExoPlayer)+ `dio`(对应 OkHttp)。
///
/// 核心设计(对齐原生):
/// - **段落 → mp3**: 每段文本经 [HttpTtsConfigResolver] 解析成 url, dio 下载 mp3,
///   落盘(md5 文件名, 含 url+speed+text), 命中缓存复用。
/// - **播放队列**: 用 `ConcatenatingAudioSource` 滚动追加(窗口大小 [_windowSize]),
///   避免一章几十段一次性塞队列卡顿(对齐原生 ExoPlayer playlist)。
/// - **段推进**: `onPlayerComplete`(整队列播完)/`currentIndex` 变化 → 推进段下标。
/// - **逐字进度(估算)**: ExoPlayer 无字符级回调, 用音频时长 ÷ 段字符数估算当前字符
///   位置(对应原生 `upPlayPos = delay(duration/charCount)`)。
/// - **暂停**: `just_audio` 原生 pause/resume(保留音频位置, 优于系统 TTS)。
/// - **倍速**: url 含 `{{speakSpeed}}` = 后端合成, 改倍速重下载; 否则 `setSpeed` 实时改。
class HttpTtsEngine implements AloudEngine {
  HttpTtsEngine({required HttpTtsConfig config, Dio? dio, AudioPlayer? player})
      : _config = config,
        _dio = dio ?? Dio(),
        _player = player ?? AudioPlayer();

  final HttpTtsConfig _config;
  final Dio _dio;
  final AudioPlayer _player;

  @override
  AloudEngineType get type => AloudEngineType.http;

  AloudState _state = AloudState.idle;
  @override
  AloudState get state => _state;

  final _stateController = StreamController<AloudState>.broadcast();
  final _progressController = StreamController<AloudProgressEvent>.broadcast();
  @override
  Stream<AloudState> get stateStream => _stateController.stream;
  @override
  Stream<AloudProgressEvent> get progressStream => _progressController.stream;

  List<String> _paragraphs = const [];
  int _currentIndex = 0;
  double _speed = 1.0;
  bool _disposed = false;

  /// 滚动窗口大小: 队列里最多保持这么多段, 播完一段追加下一段、回收已播段。
  /// 对齐原生 ExoPlayer playlist, 避免大队列卡顿(参见 just_audio issue #294)。
  static const int _windowSize = 3;

  ConcatenatingAudioSource? _playlist;
  Directory? _cacheDir;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _progressTimer;

  /// 初始化缓存目录(懒加载, 首次 play 时调)。
  Future<Directory> _ensureCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    _cacheDir = Directory('${tmp.path}/flutter_reader_http_tts');
    if (!_cacheDir!.existsSync()) _cacheDir!.createSync(recursive: true);
    return _cacheDir!;
  }

  @override
  Future<void> play({
    required List<String> paragraphs,
    required int startIndex,
    required double speed,
    bool followSysRate = false,
  }) async {
    _paragraphs = paragraphs;
    // 跟随系统时用默认档位 1.0(对齐原生 speechRatePlay = defaultSpeechRate,
    // progress=5 → 倍率 1.0)。HTTP 合成是后端控制, 无"系统设置"概念。
    _speed = followSysRate ? 1.0 : speed;
    _currentIndex = startIndex.clamp(0, paragraphs.length);
    if (_currentIndex >= paragraphs.length) {
      _setState(AloudState.idle);
      return;
    }

    _setState(AloudState.preparing);
    final cacheDir = await _ensureCacheDir();

    // 构建初始窗口 [currentIndex, currentIndex + _windowSize)。
    final end = (_currentIndex + _windowSize).clamp(0, paragraphs.length);
    final sources = <AudioSource>[];
    for (var i = _currentIndex; i < end; i++) {
      final file = await _ensureSegmentCached(i, cacheDir);
      sources.add(AudioSource.file(file.path));
    }

    _playlist = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );
    await _player.setAudioSource(_playlist!, initialIndex: 0);
    await _player.setSpeed(speed);

    // 订阅播放器事件。
    _indexSub ??= _player.currentIndexStream.listen(_onIndexChange);
    _playerStateSub ??= _player.playerStateStream.listen(_onPlayerState);

    _setState(AloudState.playing);
    await _player.play();
    _startProgressTimer();
  }

  /// 确保第 [index] 段的 mp3 已缓存, 返回文件。未命中则下载。
  Future<File> _ensureSegmentCached(int index, Directory cacheDir) async {
    final text = _paragraphs[index];
    final speakText = text.trim(); // 去缩进/首尾空白
    final key = _md5Key(speakText, _speed);
    final file = File('${cacheDir.path}/$key.mp3');
    if (file.existsSync() && file.lengthSync() > 0) return file;

    // 下载。空段(纯标点已被 TextSlicer 过滤, 这里兜底)用空请求降级。
    if (speakText.isEmpty) {
      // 写一个最小有效 mp3 占位(避免空文件让播放器报错)。
      await file.writeAsBytes(_minimalSilentMp3);
      return file;
    }

    final url = HttpTtsConfigResolver.resolve(_config, speakText, _speed);
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: _config.header,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('HTTP TTS 返回空响应: $url');
    }
    // 可选: 校验 Content-Type(若 config.contentType 配了, 检查是否音频)。
    await file.writeAsBytes(bytes);
    return file;
  }

  /// 文件名 md5 = md5(url + speed + text)。对齐原生文件名含 url+speechRate+content。
  String _md5Key(String speakText, double speed) {
    final raw = '${_config.url}|$speed|$speakText';
    return md5.convert(utf8.encode(raw)).toString();
  }

  void _onIndexChange(int? idx) {
    if (_disposed || idx == null || _playlist == null) return;
    // absoluteIndex = 队列起点偏移 + 当前播放项下标。
    // ⚠️ 不做头部回收(曾用 removeRange 但会破坏 _currentIndex/player.currentIndex
    //    不变式, 导致段推进错位)。just_audio ConcatenatingAudioSource 处理
    //    几十段播放列表无性能问题(官方 issue #294 确认), 故保持队列单调追加。
    final absoluteIndex = _currentIndex + idx;
    if (absoluteIndex >= _paragraphs.length) return;
    // 报段首进度(charEndInParagraph=1 让段切换瞬间即有高亮反馈, 避免闪烁)。
    _progressController.add(AloudProgressEvent(
      paragraphIndex: absoluteIndex,
      charStartInParagraph: 0,
      charEndInParagraph: 1,
    ));
    // 滚动预取: 接近窗口尾部 → 后台追加下一段(只追加不回收)。
    _slideWindow(idx);
  }

  /// 滚动预取: 当播放到队列倒数第 2 项时, 后台追加下一段。
  ///
  /// **不做头部回收** —— 曾用 removeRange 回收已播段, 但 removeRange 会异步
  /// 触发 currentIndex 变化事件, 与 `_currentIndex` 累加不在同一原子操作,
  /// 破坏「`_currentIndex + player.currentIndex == 真实段下标`」不变式, 导致
  /// 段推进/高亮全面错位。just_audio 处理几十段播放列表无压力(对齐原生
  /// ExoPlayer playlist), 故保持单调追加。
  Future<void> _slideWindow(int currentQueueIdx) async {
    final playlist = _playlist;
    if (playlist == null || _disposed) return;
    final queueLen = playlist.length;
    // 接近窗口尾部 → 追加下一段(若还有)。
    if (currentQueueIdx < queueLen - 1) return;
    final nextAbsolute = _currentIndex + queueLen;
    if (nextAbsolute >= _paragraphs.length) return;
    final cacheDir = await _ensureCacheDir();
    try {
      final file = await _ensureSegmentCached(nextAbsolute, cacheDir);
      await playlist.add(AudioSource.file(file.path));
    } catch (_) {
      // 预取失败静默, 到时播到了再报错。
    }
  }

  void _onPlayerState(PlayerState s) {
    if (_disposed) return;
    if (s.processingState == ProcessingState.completed) {
      // 整队列播完(含滚动追加后的所有段) → 章末。
      _stopProgressTimer();
      _setState(AloudState.idle);
    }
  }

  /// 启动逐字进度定时器(估算, 对应原生 upPlayPos 的 delay 循环)。
  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _emitEstimatedProgress();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// 估算当前段内字符进度: position / duration × 段字符数。
  void _emitEstimatedProgress() {
    if (_disposed || _paragraphs.isEmpty) return;
    final queueIdx = _player.currentIndex ?? 0;
    final absoluteIndex = _currentIndex + queueIdx;
    if (absoluteIndex >= _paragraphs.length) return;
    final text = _paragraphs[absoluteIndex].trim();
    if (text.isEmpty) return;
    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds == 0) return;
    final position = _player.position;
    final charCount = text.length;
    final charNow = (position.inMilliseconds /
            duration.inMilliseconds *
            charCount)
        .round()
        .clamp(0, charCount);
    _progressController.add(AloudProgressEvent(
      paragraphIndex: absoluteIndex,
      charStartInParagraph: 0,
      charEndInParagraph: charNow,
    ));
  }

  // ─────────── 播放控制 ───────────

  @override
  Future<void> pause() async {
    _stopProgressTimer();
    await _player.pause();
    _setState(AloudState.paused);
  }

  @override
  Future<void> resume() async {
    _setState(AloudState.playing);
    await _player.play();
    _startProgressTimer();
  }

  @override
  Future<void> stop() async {
    _stopProgressTimer();
    await _player.stop();
    _setState(AloudState.stopped);
  }

  @override
  Future<void> setRate(double rate, {bool followSysRate = false}) async {
    // 跟随系统时用默认档位 1.0(对齐原生 speechRatePlay = defaultSpeechRate)。
    final effective = followSysRate ? 1.0 : rate;
    _speed = effective;
    // 暂停态只改字段, 不重 play(否则 play 会把状态从 paused 推回 playing,
    // 破坏暂停语义; 后端合成模式 resume 时自然用新速率重新下载)。
    if (_state == AloudState.paused) return;
    if (_config.speedFromBackend) {
      // 后端合成倍速: 改倍速 = 重 play 当前段(缓存 key 含 speed, 会重下载)。
      final cur = _currentIndex + (_player.currentIndex ?? 0);
      _currentIndex = cur.clamp(0, _paragraphs.length);
      await play(
        paragraphs: _paragraphs,
        startIndex: _currentIndex,
        speed: effective,
        followSysRate: followSysRate,
      );
    } else {
      // 播放器实时变速(just_audio 原生支持, 队列内音频也立即变速)。
      await _player.setSpeed(effective);
    }
  }

  @override
  Future<void> skipToParagraph(int index) async {
    final target = index.clamp(0, _paragraphs.length);
    if (target >= _paragraphs.length) {
      _setState(AloudState.idle);
      return;
    }
    // 重 play 从目标段(丢弃当前队列, 重建窗口)。
    await play(paragraphs: _paragraphs, startIndex: target, speed: _speed);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopProgressTimer();
    await _indexSub?.cancel();
    await _playerStateSub?.cancel();
    await _player.dispose();
    await _stateController.close();
    await _progressController.close();
  }

  void _setState(AloudState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// 最小有效静音 mp3(用于空段占位, 避免播放器对空文件报错)。
  /// 这是一个 0 长度的 MPEG 帧 header, 实际生产应换成资源文件。
  static final List<int> _minimalSilentMp3 = Uint8List.fromList([
    0xFF, 0xFB, 0x90, 0x00, // MPEG-1 Layer 3 header
    for (var i = 0; i < 417; i++) 0, // 一个帧的填充
  ]);
}
