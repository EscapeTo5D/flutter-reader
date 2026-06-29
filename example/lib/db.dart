import 'dart:io';

import 'package:flutter_reader/flutter_reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 持久化仓库单例初始化。
///
/// - Android/iOS: 直接用 sqflite 默认工厂 + 应用文档目录。
/// - 桌面(Windows/Linux/macOS): 需 sqflite_common_ffi, 在此初始化。
///
/// 桌面端若要运行 example, 需先 `flutter create . --platforms=windows`。
class AppDatabase {
  AppDatabase._();
  static ReaderRepository? _repo;

  /// 当前演示用的固定用户 id。真实 App 应替换为登录态的用户 id。
  static const demoUserId = 'demo-user';

  /// 初始化并返回仓库单例。
  static Future<ReaderRepository> init() async {
    if (_repo != null) return _repo!;

    // 桌面端启用 ffi(sqflite 原生只支持 Android/iOS)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // open() 内部默认用 getApplicationDocumentsDirectory() 拼 db 路径。
    // 真实项目可传自定义路径: SqfliteReaderRepository.open(dbPath: yourPath)
    _repo = await SqfliteReaderRepository.open();
    return _repo!;
  }

  static ReaderRepository get repo => _repo!;
}
