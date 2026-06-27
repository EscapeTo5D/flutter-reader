package com.example.flutter_reader_example

import android.os.Build
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "flutter_reader/system_ui"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSystemBars" -> {
                        val showStatus = call.argument<Boolean>("showStatusBar") ?: true
                        val showNav = call.argument<Boolean>("showNavBar") ?: true
                        setSystemBars(showStatus, showNav)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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
     */
    private fun setSystemBars(showStatusBar: Boolean, showNavBar: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // API < 30 不处理, 让 Dart 端回退 SystemChrome。
            return
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
        }
    }
}
