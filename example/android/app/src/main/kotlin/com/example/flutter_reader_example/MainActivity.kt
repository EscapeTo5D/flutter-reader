package com.example.flutter_reader_example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SYSTEM_UI_CHANNEL = "flutter_reader/system_ui"
        private const val BATTERY_CHANNEL = "flutter_reader/battery"
    }

    /** 电量广播接收器, ACTION_BATTERY_CHANGED 时推百分比给 Flutter。null=未注册。 */
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_UI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSystemBars" -> {
                        val showStatus = call.argument<Boolean>("showStatusBar") ?: true
                        val showNav = call.argument<Boolean>("showNavBar") ?: true
                        result.success(setSystemBars(showStatus, showNav))
                    }
                    else -> result.notImplemented()
                }
            }
        // 注册电量事件流。Flutter 端订阅时 onListen 注册 receiver, 取消时 onCancel 注销,
        // 避免无订阅时仍持守广播。ACTION_BATTERY_CHANGED 是粘性广播, 注册瞬间即回调当前电量。
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    registerBatteryReceiver(events)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterBatteryReceiver()
                }
            })
    }

    /**
     * 注册 ACTION_BATTERY_CHANGED 广播接收器。
     * 注册瞬间系统会立即投递当前电量(粘性广播), 无需额外主动取一次。
     */
    private fun registerBatteryReceiver(events: EventChannel.EventSink) {
        unregisterBatteryReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                if (level >= 0 && scale > 0) {
                    val percent = level * 100 / scale
                    events.success(percent)
                }
            }
        }
        // ACTION_BATTERY_CHANGED 是系统广播, 用 ContextCompat.registerReceiver 跨版本兼容
        // (API < 33 没有 RECEIVER_NOT_EXPORTED 标志, ContextCompat 内部按版本正确分派)。
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        batteryReceiver = receiver
    }

    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // 未注册时忽略。
            }
        }
        batteryReceiver = null
    }

    override fun onDestroy() {
        unregisterBatteryReceiver()
        super.onDestroy()
    }

    /**
     * 直接用 WindowInsetsController.hide/show 控制系统栏。
     *
     * 绕过 Flutter SystemChrome: Android 15(API 35) 强制 edge-to-edge,
     * SystemUiMode.manual 隐藏状态栏走系统渐隐过渡(显示即时、隐藏延迟几百 ms)。
     * 而原生 legado 直接调 window.insetsController.hide(statusBars) 即时真隐藏。
     *
     * BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE: 从边缘滑动临时唤出后自动收回,
     * 对齐原生 IMMERSIVE_STICKY 语义。
     *
     * @return true=已由原生处理(API 30+); false=不支持(API < 30), Dart 端应回退 SystemChrome。
     */
    private fun setSystemBars(showStatusBar: Boolean, showNavBar: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // API < 30 没有 WindowInsetsController, 返回 false 让 Dart 端回退 SystemChrome。
            return false
        }
        window.decorView.windowInsetsController?.let { controller ->
            controller.systemBarsBehavior =
                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            val hideBars = ArrayList<Int>()
            if (!showStatusBar) hideBars.add(WindowInsets.Type.statusBars())
            if (!showNavBar) hideBars.add(WindowInsets.Type.navigationBars())
            if (hideBars.isNotEmpty()) {
                controller.hide(hideBars.reduce { a, b -> a or b })
            } else {
                controller.show(WindowInsets.Type.systemBars())
            }
            return true
        }
        return false
    }
}
