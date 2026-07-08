import 'dart:isolate' show Isolate;
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;

import '../../core/models/reading_settings.dart';
import '../entities/text_page.dart';
import 'page_engine.dart';

/// 在后台 isolate 中执行章节排版, 不阻塞 UI 线程。对齐原生 legado 的
/// `ChapterProvider` 用 `Coroutine.async(IO)` 在后台排版的设计。
///
/// legado 的 TextChapterLayout init 里 `Coroutine.async(scope, executeContext = IO)`
/// 在后台 IO 协程排版; 本实现用 Isolate.run 在 worker isolate 跑 PageEngine.paginate。
///
/// **可发送性**:
/// - 输入(content: String / pageSize: Size / settings: ReadingSettings)和
///   返回(List of TextPage)的字段全是 primitive/enum/值类型(Color/FontWeight 都是 int
///   包装), 无闭包/Stream/不可发送对象, 满足 isolate 边界约束。
/// - Isolate.run 底层用 Isolate.exit 转移结果所有权(非深拷贝), 大 List 也高效。
///
/// **TextPainter 在 worker isolate 的支持**:
/// `TextPainter.layout()` 依赖 Flutter 字体引擎(属 dart:ui), 历史上只能在 root
/// isolate 用。Flutter 3.7+ 引入 BackgroundIsolateBinaryMessenger, 传入
/// RootIsolateToken 后 worker isolate 也能访问 engine 服务。SDK ^3.11 完全支持。
///
/// **回退保护**: 若 isolate 排版抛错(token 不可用/平台限制/测试环境),
/// 退回主线程同步 PageEngine.paginate, 保证最坏情况等价于现状, 不崩。
///
/// ⚠️ 实测在 debug 模式 + 真机上, `BackgroundIsolateBinaryMessenger` 虽初始化,
/// 但 `TextPainter.layout` 仍依赖只在 root isolate 可用的 UI actions,
/// 抛 `UI actions are only available on root isolate`。失败时 spawn+回退开销
/// 巨大(每次 ~1s 浪费在注定失败的 isolate spawn 上)。故用 [_isolateDisabled]
/// 熔断: 首次失败后永久走主线程, 避免反复 spawn。release/profile 模式下
/// isolate 通常可用, 熔断标志只在当前进程生效。
/// 排版性能日志总开关。默认 `false`(release 静默); 排查卡顿/排版耗时问题时改成
/// `true` 即可恢复全部 [debugPrint]('[PERF]...') 打点。
///
/// 已知打点位置:
/// - `paginate_isolate.dart`: 4 处(短内容/主线程/isolate/熔断 各 1)
/// - `reading_controller.dart` _loadAdjacentChapter: loadContent / ContentProcessor / paginate 三件套
///
/// `reader_view.dart` 的 `updatePageSize` 打点已删除(每次重建都打, 无耗时只有尺寸,
/// 纯噪音; 尺寸传导链路的根因已固化在 controller.updatePageSize 的防抖里)。
const bool kLogPerf = false;

bool _isolateDisabled = false;

Future<List<TextPage>> paginateInBackground({
  required String content,
  required Size pageSize,
  required ReadingSettings settings,
  bool firstParagraphIsTitle = false,
  bool scrollContentMode = false,
}) async {
  // 短内容直接主线程排, 避免起 isolate 的开销(isolate spawn ~1-2ms)。
  // 阈值取经验值: 单页约几百字符, 几页内的内容主线程排也很快。
  if (content.length < 2000) {
    final t = Stopwatch()..start();
    final r = PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
      firstParagraphIsTitle: firstParagraphIsTitle,
      scrollContentMode: scrollContentMode,
    );
    if (kLogPerf) {
      debugPrint(
        '[PERF] paginateInBackground(短内容主线程, ${content.length}字符→${r.length}页): ${t.elapsedMilliseconds}ms',
      );
    }
    return r;
  }

  // 熔断过 / 测试环境(FlutterTester 无 root isolate token) / kDebugMode:
  // 直接走主线程。kDebugMode 下 JIT + UI actions 限制使 isolate 排版不可靠,
  // 与其每次 spawn 失败浪费 ~1s, 不如直接主线程排(~180ms)。
  final token = RootIsolateToken.instance;
  if (_isolateDisabled || token == null || kDebugMode) {
    final t = Stopwatch()..start();
    final r = PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
      firstParagraphIsTitle: firstParagraphIsTitle,
      scrollContentMode: scrollContentMode,
    );
    final reason = _isolateDisabled
        ? '熔断'
        : (token == null ? '无token' : 'debug模式');
    if (kLogPerf) {
      debugPrint(
        '[PERF] paginateInBackground(主线程[$reason], ${content.length}字符→${r.length}页): ${t.elapsedMilliseconds}ms',
      );
    }
    return r;
  }

  try {
    final tIso = Stopwatch()..start();
    final r = await Isolate.run(() {
      // 让 worker isolate 能访问 Flutter engine(字体/文本测量)。
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      return PageEngine().paginate(
        content: content,
        pageSize: pageSize,
        settings: settings,
        firstParagraphIsTitle: firstParagraphIsTitle,
        scrollContentMode: scrollContentMode,
      );
    });
    if (kLogPerf) {
      debugPrint(
        '[PERF] paginateInBackground(isolate, ${content.length}字符→${r.length}页): ${tIso.elapsedMilliseconds}ms',
      );
    }
    return r;
  } catch (e) {
    // 熔断: isolate 排版失败(平台限制/UI actions 不可用)后, 标记永久走主线程,
    // 避免后续每次调用都重复 spawn 一个注定失败的 isolate(spawn 本身 ~1s 开销)。
    _isolateDisabled = true;
    debugPrint('[paginateInBackground] isolate 失败, 熔断→永久主线程: $e');
    final t = Stopwatch()..start();
    final r = PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
      firstParagraphIsTitle: firstParagraphIsTitle,
      scrollContentMode: scrollContentMode,
    );
    if (kLogPerf) {
      debugPrint(
        '[PERF] paginateInBackground(熔断后主线程, ${content.length}字符→${r.length}页): ${t.elapsedMilliseconds}ms',
      );
    }
    return r;
  }
}
