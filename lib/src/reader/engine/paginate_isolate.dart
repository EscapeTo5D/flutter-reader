import 'dart:isolate' show Isolate;
import 'dart:ui' show RootIsolateToken;

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
Future<List<TextPage>> paginateInBackground({
  required String content,
  required Size pageSize,
  required ReadingSettings settings,
}) async {
  // 短内容直接主线程排, 避免起 isolate 的开销(isolate spawn ~1-2ms)。
  // 阈值取经验值: 单页约几百字符, 几页内的内容主线程排也很快。
  if (content.length < 2000) {
    return PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
  }

  // 测试环境(FlutterTester)无 root isolate token, 直接走主线程。
  // kDebugMode 下不强求 isolate, 保证测试可重复。
  final token = RootIsolateToken.instance;
  if (token == null) {
    return PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
  }

  try {
    return await Isolate.run(() {
      // 让 worker isolate 能访问 Flutter engine(字体/文本测量)。
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      return PageEngine().paginate(
        content: content,
        pageSize: pageSize,
        settings: settings,
      );
    });
  } catch (e) {
    // 回退: 后台排版失败(平台限制/引擎异常)时, 退回主线程同步排。
    // 最坏情况等价于无 isolate 的旧行为, 不会比现状更差。
    debugPrint('[paginateInBackground] isolate 失败, 回退主线程: $e');
    return PageEngine().paginate(
      content: content,
      pageSize: pageSize,
      settings: settings,
    );
  }
}
