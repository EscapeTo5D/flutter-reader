import 'package:flutter/services.dart';

/// 系统栏(状态栏/导航栏)显隐控制。
///
/// 优先走原生 MethodChannel(`flutter_reader/system_ui`), 直接调用
/// `WindowInsetsController.hide/show`, 绕过 Flutter SystemChrome:
///
/// Android 15(API 35) 强制 edge-to-edge, `SystemUiMode.manual` 隐藏状态栏走系统
/// 渐隐过渡(显示即时、隐藏延迟几百 ms), 与阅读菜单显隐不同步。原生 legado 直接调
/// `window.insetsController.hide(statusBars)` 即时真隐藏(`BaseReadBookActivity.kt`)。
///
/// 宿主 App 需自行注册同名 channel 才能用原生能力; 未注册时自动回退 SystemChrome,
/// 保证纯 Dart 包(无原生代码)仍可用, 只是在 Android 15 上状态栏隐藏有系统延迟。
class SystemUiController {
  SystemUiController._();

  static const MethodChannel _channel = MethodChannel('flutter_reader/system_ui');

  /// 原生 channel 是否可用。null=未探测, true=可用, false=回退 SystemChrome。
  /// 首次 MissingPluginException 后置 false, 后续不再尝试 channel, 避免每次调用都抛异常。
  static bool? _nativeAvailable;

  /// 设置系统栏显隐。
  ///
  /// [showStatusBar]/[showNavBar] 为 true 表示显示对应系统栏, false 表示隐藏。
  /// 优先原生 channel(即时), 不可用回退 SystemChrome(有系统延迟)。
  static Future<void> setSystemBars({
    required bool showStatusBar,
    required bool showNavBar,
  }) async {
    if (_nativeAvailable ?? true) {
      try {
        await _channel.invokeMethod('setSystemBars', {
          'showStatusBar': showStatusBar,
          'showNavBar': showNavBar,
        });
        _nativeAvailable = true;
        return;
      } on MissingPluginException {
        // 宿主未注册 channel, 纯 Dart 包场景。后续直接走 SystemChrome。
        _nativeAvailable = false;
      } on PlatformException {
        // 其它平台异常也回退。
        _nativeAvailable = false;
      }
    }
    _fallbackSystemChrome(showStatusBar, showNavBar);
  }

  /// 回退实现: 用 Flutter SystemChrome。
  ///
  /// Android 15 上隐藏有系统延迟, 但能保证基本可用; iOS/桌面端行为正常。
  static void _fallbackSystemChrome(bool showStatusBar, bool showNavBar) {
    if (showStatusBar && showNavBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    } else if (!showStatusBar && !showNavBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [
            if (showStatusBar) SystemUiOverlay.top,
            if (showNavBar) SystemUiOverlay.bottom,
          ]);
    }
  }
}
