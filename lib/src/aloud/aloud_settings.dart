import 'aloud_engine.dart';

/// 朗读子系统配置(对应原生 legado 全局 SharedPreferences 里的朗读相关项)。
///
/// 对齐原生(均全局, 非 per-book):
/// - `ttsSpeechRate`(progress 0..45, 默认 5) → [rate] 取显示倍率 = (progress+5)/10,
///   默认 1.0。
/// - `appTtsEngine`(系统/HTTP) → [engineType], 默认 system。
/// - `ttsFollowSys`(跟随系统语速, 默认 **true**) → [followSysRate]。
///
/// ⚠️ [followSysRate]=true 时的「读系统 TTS 默认语速」逻辑本轮未实现(留 TODO);
/// 当前 true 时仍用 [rate] 字段值(默认 1.0), 仅持久化开关态。Android 无公开 API
/// 读系统 TTS rate, iOS 可读 `AVSpeechUtteranceDefaultSpeechRate`——留待后续。
///
/// 持久化: 复用 `settings` 表(KV), `user_id = '__aloud__'` 存全局, 不加新表/不升 schema。
/// 编解码见 [toJson]/[fromJson], 缺失字段回落 [defaults](向前兼容旧数据)。
class AloudSettings {
  /// 语速倍率(1.0 = 正常, 范围 0.5~5.0)。
  final double rate;

  /// 朗读引擎类型。
  final AloudEngineType engineType;

  /// 跟随系统语速(对齐原生 `ttsFollowSys`, 默认 true)。
  final bool followSysRate;

  const AloudSettings({
    this.rate = 1.0,
    this.engineType = AloudEngineType.system,
    this.followSysRate = true,
  });

  /// 默认值(对齐原生微信读书预设 + legado `ttsFollowSys` 默认 true)。
  static const AloudSettings defaults = AloudSettings();

  AloudSettings copyWith({
    double? rate,
    AloudEngineType? engineType,
    bool? followSysRate,
  }) {
    return AloudSettings(
      rate: rate ?? this.rate,
      engineType: engineType ?? this.engineType,
      followSysRate: followSysRate ?? this.followSysRate,
    );
  }

  Map<String, dynamic> toJson() => {
        'rate': rate,
        'engineType': engineType.name,
        'followSysRate': followSysRate,
      };

  /// 从 JSON 反序列化; 缺失/null 字段回落 [defaults](向前兼容)。
  factory AloudSettings.fromJson(Map<String, dynamic> json) {
    final d = defaults;
    final rateVal = json['rate'];
    final engineName = json['engineType'];
    return AloudSettings(
      rate: rateVal is num ? rateVal.toDouble() : d.rate,
      engineType: engineName is String
          ? AloudEngineType.values.asNameMap()[engineName] ?? d.engineType
          : d.engineType,
      followSysRate:
          json['followSysRate'] is bool ? json['followSysRate'] as bool : d.followSysRate,
    );
  }

  @override
  String toString() =>
      'AloudSettings(rate: $rate, engineType: $engineType, followSysRate: $followSysRate)';
}
