import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_reader/src/aloud/aloud_engine.dart';
import 'package:flutter_reader/src/aloud/aloud_settings.dart';

/// AloudSettings 模型编解码测试。
///
/// 锁定: 默认值对齐原生 legado(`ttsFollowSys` 默认 true, `ttsSpeechRate` progress
/// 默认 5 → 倍率 1.0, 默认引擎 system); toJson/fromJson 往返一致; 缺失/null/类型
/// 不符字段回落默认(向前兼容旧数据)。
void main() {
  group('AloudSettings 默认值', () {
    test('defaults 对齐原生 legado', () {
      const s = AloudSettings.defaults;
      expect(s.rate, 1.0); // progress 5 → (5+5)/10 = 1.0
      expect(s.engineType, AloudEngineType.system);
      expect(s.followSysRate, isTrue); // 原生 ttsFollowSys 默认 true
    });

    test('无参构造等价于 defaults', () {
      const s = AloudSettings();
      expect(s.rate, AloudSettings.defaults.rate);
      expect(s.engineType, AloudSettings.defaults.engineType);
      expect(s.followSysRate, AloudSettings.defaults.followSysRate);
    });
  });

  group('AloudSettings toJson/fromJson 往返', () {
    test('完整字段往返一致', () {
      const original = AloudSettings(
        rate: 2.5,
        engineType: AloudEngineType.http,
        followSysRate: false,
      );
      final restored = AloudSettings.fromJson(original.toJson());
      expect(restored.rate, 2.5);
      expect(restored.engineType, AloudEngineType.http);
      expect(restored.followSysRate, isFalse);
    });

    test('默认值往返一致', () {
      final restored = AloudSettings.fromJson(AloudSettings.defaults.toJson());
      expect(restored.rate, 1.0);
      expect(restored.engineType, AloudEngineType.system);
      expect(restored.followSysRate, isTrue);
    });
  });

  group('AloudSettings 向前兼容(缺失/异常字段回落默认)', () {
    test('空 JSON 全回落默认', () {
      final s = AloudSettings.fromJson(const {});
      expect(s.rate, AloudSettings.defaults.rate);
      expect(s.engineType, AloudSettings.defaults.engineType);
      expect(s.followSysRate, AloudSettings.defaults.followSysRate);
    });

    test('rate 为 null 回落默认 1.0', () {
      final s = AloudSettings.fromJson(const {'rate': null});
      expect(s.rate, 1.0);
    });

    test('rate 为字符串(类型不符)回落默认', () {
      final s = AloudSettings.fromJson(const {'rate': 'fast'});
      expect(s.rate, 1.0);
    });

    test('engineType 为未知字符串回落 system', () {
      final s = AloudSettings.fromJson(const {'engineType': 'unknown'});
      expect(s.engineType, AloudEngineType.system);
    });

    test('engineType 为 null 回落 system', () {
      final s = AloudSettings.fromJson(const {'engineType': null});
      expect(s.engineType, AloudEngineType.system);
    });

    test('followSysRate 缺失回落 true(对齐原生 ttsFollowSys)', () {
      final s = AloudSettings.fromJson(const {'rate': 1.5});
      expect(s.followSysRate, isTrue);
    });

    test('followSysRate 为非 bool 回落 true', () {
      final s = AloudSettings.fromJson(const {'followSysRate': 'yes'});
      expect(s.followSysRate, isTrue);
    });

    test('部分字段保留, 其余回落', () {
      final s = AloudSettings.fromJson(const {'rate': 3.0});
      expect(s.rate, 3.0); // 提供
      expect(s.engineType, AloudEngineType.system); // 回落
      expect(s.followSysRate, isTrue); // 回落
    });
  });

  group('AloudSettings copyWith', () {
    test('只改 rate', () {
      const s = AloudSettings();
      final s2 = s.copyWith(rate: 4.0);
      expect(s2.rate, 4.0);
      expect(s2.engineType, s.engineType); // 不变
      expect(s2.followSysRate, s.followSysRate); // 不变
    });

    test('只改 engineType', () {
      const s = AloudSettings();
      final s2 = s.copyWith(engineType: AloudEngineType.http);
      expect(s2.engineType, AloudEngineType.http);
      expect(s2.rate, s.rate); // 不变
    });

    test('只改 followSysRate', () {
      const s = AloudSettings();
      final s2 = s.copyWith(followSysRate: false);
      expect(s2.followSysRate, isFalse);
      expect(s2.rate, s.rate); // 不变
    });

    test('copyWith 不传参等价于原对象值', () {
      const s = AloudSettings(rate: 2.0, followSysRate: false);
      final s2 = s.copyWith();
      expect(s2.rate, s.rate);
      expect(s2.engineType, s.engineType);
      expect(s2.followSysRate, s.followSysRate);
    });
  });
}
