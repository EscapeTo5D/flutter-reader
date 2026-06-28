import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 电量数据提供者。
///
/// 对齐原生 legado 的 `ReadBook` 注册 `ACTION_BATTERY_CHANGED` 广播实时刷新电量
/// (`ReadBook.kt` + `BaseReadBookActivity`)。原生 legado 把电量传给 `PageView.upBattery`,
/// 页眉/页脚的 `TipPosition.battery` 槽据此绘制电量图标或百分比。
///
/// 本包用 `EventChannel('flutter_reader/battery')` 接收原生电量变化流:
/// - **Android**: 宿主 `MainActivity` 注册 `BroadcastReceiver` 监听
///   `ACTION_BATTERY_CHANGED`(粘性广播, 注册即回调当前电量), 把 level 百分比推给 Flutter。
/// - 宿主未注册 channel 时(纯 Dart 包场景), 流报错, `level` 保持 null,
///   页眉电量槽回退到不显示——与 `system_ui_controller.dart` 同一套「宿主可选」契约。
///
/// 用单例 `BatteryProvider.instance` + `start()`, 在阅读页 `initState` 启动。
/// `ValueNotifier` 内置相等判断, 相同 level 不会重复 notify。
class BatteryProvider extends ValueNotifier<int?> {
  BatteryProvider._() : super(null);

  static final BatteryProvider instance = BatteryProvider._();

  bool _started = false;

  /// 启动电量监听。幂等: 重复调用安全。
  ///
  /// 首次调用时订阅 EventChannel。Android 粘性广播会在订阅瞬间回调当前电量,
  /// 无需额外「取一次」的初始请求。订阅由 EventChannel 内部监听链保活(单例随 App 生命周期),
  /// 故不持有 StreamSubscription 引用。
  void start() {
    if (_started) return;
    _started = true;
    const channel = EventChannel('flutter_reader/battery');
    channel.receiveBroadcastStream().listen(
      _onData,
      onError: (Object error) {
        // 宿主未注册 channel(MissingPluginException) 或原生异常: 标记未启动,
        // 保持 level=null(页眉电量槽不显示)。与 SystemUiController 同样的降级语义。
        _started = false;
      },
    );
  }

  void _onData(dynamic level) {
    if (level is int) {
      value = level;
    }
  }
}
