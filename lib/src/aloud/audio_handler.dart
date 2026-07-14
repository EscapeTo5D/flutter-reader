import 'aloud_engine.dart';

/// 音频会话处理器抽象(后台/锁屏/通知栏的扩展点)。
///
/// **第一版不实现后台播放**, 默认用 [NoopAudioHandler]。此抽象为第二版接入
/// `audio_service`(ryanheise)预留: 第二版实现一个 `AudioServiceHandler`
/// 把朗读状态转发到 MediaSession + 系统通知栏 + 锁屏控件, 实现锁屏续读、
/// 耳机线控、蓝牙按键。
///
/// 设计: [AloudController] 持有可选 [AudioHandler], 在引擎状态/进度变化时
/// 调 `notifyState`/`notifyProgress`。第一版 noop 无副作用; 第二版换成
/// audio_service 实现即可, 控制器主逻辑不动。
abstract class AudioHandler {
  /// 绑定引擎(注册播放控制回调: play/pause/next/prev 等, 供 MediaSession 调用)。
  Future<void> bind(AloudEngine engine);

  /// 解绑。
  Future<void> unbind();

  /// 通知状态变化(供 MediaSession 更新播放/暂停图标)。
  void notifyState(AloudState state);

  /// 通知进度变化(供 MediaSession 更新元数据)。
  void notifyProgress(AloudProgressEvent progress);

  /// 释放。
  Future<void> dispose();
}

/// 空实现(第一版默认)。
///
/// 所有方法 no-op, 无副作用。第二版接入 audio_service 时替换为真实实现。
class NoopAudioHandler implements AudioHandler {
  const NoopAudioHandler();

  @override
  Future<void> bind(AloudEngine engine) async {}

  @override
  Future<void> unbind() async {}

  @override
  void notifyState(AloudState state) {}

  @override
  void notifyProgress(AloudProgressEvent progress) {}

  @override
  Future<void> dispose() async {}
}
