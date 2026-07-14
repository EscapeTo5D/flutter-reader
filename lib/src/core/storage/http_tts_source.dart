import '../../aloud/http_tts_config.dart';

/// HTTP TTS 配置持久化接口(对应原生 legado `httpTTSDao`)。
///
/// 独立于 [ReaderRepository]: HttpTTS 配置是全局的(不按用户/书隔离),
/// 且是朗读子系统专属数据。宿主可不引入此实现(朗读用系统 TTS 即不需要)。
///
/// 设计对齐项目现有 [ReaderRepository] 的「接口 + 默认实现」风格:
/// 接口在包内, 默认 sqflite 实现可选。宿主可注入任意实现。
abstract class HttpTtsSource {
  /// 读取全部 HttpTTS 配置(按 sortOrder 升序)。
  Future<List<HttpTtsConfig>> getAll();

  /// 按 id 读取单条。无记录返回 null。
  Future<HttpTtsConfig?> getById(String id);

  /// 保存/覆盖(upsert, 主键 id)。
  Future<void> save(HttpTtsConfig config);

  /// 删除(按 id)。
  Future<void> delete(String id);

  /// 关闭/释放资源。
  Future<void> close();
}

/// 纯内存实现(测试 / 不持久化场景用)。
class MemoryHttpTtsSource implements HttpTtsSource {
  MemoryHttpTtsSource([Map<String, HttpTtsConfig>? initial])
      : _store = Map<String, HttpTtsConfig>.from(initial ?? {});

  final Map<String, HttpTtsConfig> _store;

  @override
  Future<List<HttpTtsConfig>> getAll() async {
    final list = _store.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  @override
  Future<HttpTtsConfig?> getById(String id) async => _store[id];

  @override
  Future<void> save(HttpTtsConfig config) async {
    _store[config.id] = config;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> close() async {}
}
