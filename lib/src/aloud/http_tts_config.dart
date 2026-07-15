/// HTTP TTS 引擎配置实体(精简版, 对应原生 legado `HttpTTS` data class)。
///
/// 第一版只支持 url 字面替换(`{{speakText}}` / `{{speakSpeed}}`),
/// 不跑 JS 模板(`{{java.xxx}}` / `@js:`)。这能覆盖百度类纯替换源;
/// Edge(`@js:apiurl`)、阿里云(签名)这类需 JS 的源留待第二版(集成 JS 引擎)。
///
/// [concurrentRate] 语义重定义: 原生用它做并发限流(`次数/毫秒`), 本包第一版
/// 简化为标记位 —— 当 url 模板含 `{{speakSpeed}}` 时表示「倍速由后端合成」,
/// 改倍速需重新下载; 否则倍速走播放器 `setSpeed` 实时改。具体由引擎判断,
/// 此字段保留供后续扩展。
class HttpTtsConfig {
  /// 唯一标识(时间戳或宿主自定义)。
  final String id;

  /// 显示名。
  final String name;

  /// url 模板, 含 `{{speakText}}` / `{{speakSpeed}}` 占位符。
  ///
  /// 示例(百度, 纯替换即可工作):
  /// `http://tts.baidu.com/text2audio?tex={{speakText}}&spd={{speakSpeed}}&per=3`
  final String url;

  /// 期望返回的 Content-Type(可选, 用于校验返回是否为音频)。
  final String? contentType;

  /// 自定义请求头(可选)。
  final Map<String, String>? header;

  /// 排序序号(UI 列表用)。
  final int sortOrder;

  const HttpTtsConfig({
    required this.id,
    required this.name,
    required this.url,
    this.contentType,
    this.header,
    this.sortOrder = 0,
  });

  HttpTtsConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? contentType,
    Map<String, String>? header,
    int? sortOrder,
  }) {
    return HttpTtsConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      contentType: contentType ?? this.contentType,
      header: header ?? this.header,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// 判断倍速是否由后端合成(url 含 `{{speakSpeed}}`)。
  ///
  /// true: 改倍速需重新下载(后端按 speakSpeed 合成不同语速的 mp3)。
  /// false: 倍速走播放器 `setSpeed` 实时改, 缓存可复用。
  bool get speedFromBackend => url.contains('{{speakSpeed}}');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'contentType': contentType,
        'header': header,
        'sortOrder': sortOrder,
      };

  factory HttpTtsConfig.fromJson(Map<String, dynamic> json) {
    return HttpTtsConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      contentType: json['contentType'] as String?,
      header: (json['header'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// HttpTTS url 模板字面替换器(第一版, 不跑 JS)。
///
/// 对应原生 `AnalyzeUrl` 的 `replaceKeyPageJs` 简化版:
/// - `{{speakText}}` → URL 编码后的朗读文本(对齐 `java.encodeURI`)。
/// - `{{speakSpeed}}` → 倍速数值(后端期望的整数刻度, 见 [_speakSpeedForBackend])。
class HttpTtsConfigResolver {
  HttpTtsConfigResolver._();

  /// 把 [config.url] 模板解析成真实请求 url。
  ///
  /// [speakText] 是已去缩进/纯标点的朗读文本。
  /// [speed] 是相对倍率(1.0 = 正常)。
  static String resolve(
    HttpTtsConfig config,
    String speakText,
    double speed,
  ) {
    var url = config.url;
    url = url.replaceAll('{{speakText}}', Uri.encodeComponent(speakText));
    url = url.replaceAll('{{speakSpeed}}', _speakSpeedForBackend(speed).toString());
    return url;
  }

  /// 相对倍率 → 后端整数刻度。
  ///
  /// 对齐原生 `HttpReadAloudService.kt:91`:
  ///   `speechRate = AppConfig.speechRatePlay + 5`
  /// `speechRatePlay` 等于 `seek_tts_speechRate` 的 progress(0..45); UI 倍率与
  /// progress 的关系是 `倍率 = (progress+5)/10`(progress 0→0.5, 45→5.0)。
  /// 代入: `speechRate = progress + 5 = (倍率×10 - 5) + 5 = 倍率 × 10`。
  /// 故直接 `倍率 × 10` 即等于原生后端整数刻度, 范围 5..50(默认 1.0→10)。
  ///
  /// 后端(百度 `spd` 等)通常期望 1~15 的刻度, 模板里可写 `{{(speakSpeed-5)/3}}`
  /// 之类换算, 但第一版不支持 JS, 宿主应直接配好刻度。
  static int _speakSpeedForBackend(double speed) =>
      (speed * 10).round().clamp(5, 50);
}
