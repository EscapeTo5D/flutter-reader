import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'api_service.dart';
import 'db.dart';

Future<void> main() async {
  // 持久化仓库初始化(需在 runApp 前, 因用到 path_provider 平台通道)
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Reader Demo',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const NovelListPage(),
    );
  }
}

// ─────────────────────────── 小说列表页 ───────────────────────────

class NovelListPage extends StatefulWidget {
  const NovelListPage({super.key});

  @override
  State<NovelListPage> createState() => _NovelListPageState();
}

class _NovelListPageState extends State<NovelListPage> {
  final _api = ApiService();
  List<NovelInfo> _novels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final novels = await _api.fetchNovels();
      if (mounted) setState(() => _novels = novels);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openNovel(NovelInfo novel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(novelId: novel.id, novelTitle: novel.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小说列表')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_novels.isEmpty) {
      return const Center(child: Text('暂无小说'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _novels.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final novel = _novels[i];
          return ListTile(
            leading: novel.thumb.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(novel.thumb,
                        width: 48, height: 64, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.book, size: 48)),
                  )
                : const Icon(Icons.book, size: 48),
            title: Text(novel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${novel.author}  ·  ${novel.desc}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openNovel(novel),
          );
        },
      ),
    );
  }
}

// ─────────────────────────── 阅读器页 ───────────────────────────

class ReaderPage extends StatefulWidget {
  final String novelId;
  final String novelTitle;

  const ReaderPage({
    super.key,
    required this.novelId,
    required this.novelTitle,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  // 注入持久化仓库 + 演示用户。controller 在 loadBook 时会自动恢复该用户在此书的进度。
  final ReadingController _controller =
      ReadingController(repository: AppDatabase.repo, userId: AppDatabase.demoUserId);
  final _api = ApiService();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 先恢复阅读设置(字号/行距/颜色等), 让 reader_view 首帧就用上次的设置
      await _controller.loadSettings();

      final chapters = await _fetchChaptersLocalFirst(widget.novelId);
      if (!mounted) return;

      final book = Book(
        id: widget.novelId,
        title: widget.novelTitle,
        author: '',
        chapters: chapters
            .asMap()
            .entries
            .map((e) => Chapter(
                  id: e.value.id,
                  title: e.value.title,
                  content: e.value.content,
                  index: e.key,
                ))
            .toList(),
      );
      _controller.loadBook(book);
      // 加入书架(保存元信息, 供"上次阅读"列表用)
      _controller.saveToShelf();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// 章节正文「本地优先」加载。
  ///
  /// 1. 先查本地缓存([ReaderRepository.getBookChapters]): 命中且非空 → 直接返回,
  ///    跳过全网请求(二次打开秒开的关键路径)。
  /// 2. 未命中(首次打开/缓存被清) → 走网络 [ApiService.fetchChapters] 一次拉全书,
  ///    下完后逐章回填缓存(saveChapterContent), 下次即本地命中。
  ///
  /// 后端目前只有「一次拉全书」接口, 无目录/单章接口, 故无法只拉目录先显骨架;
  /// 本地缓存是当前能做到的最大优化(二次起秒开)。
  Future<List<ChapterInfo>> _fetchChaptersLocalFirst(String novelId) async {
    final repo = AppDatabase.repo;
    final cached = await repo.getBookChapters(novelId);
    if (cached.isNotEmpty) {
      // 命中本地: 直接用缓存正文渲染
      return cached
          .map((c) => ChapterInfo(
                id: '${novelId}_${c.chapterIndex}',
                title: c.title,
                content: c.content,
              ))
          .toList();
    }

    // 未命中: 走网络拉取
    final chapters = await _api.fetchChapters(novelId);
    // 回填缓存(逐章 upsert)。网络失败不致命——本次渲染照常用 chapters。
    try {
      for (var i = 0; i < chapters.length; i++) {
        await repo.saveChapterContent(
          novelId,
          i,
          chapters[i].title,
          chapters[i].content,
        );
      }
    } catch (_) {
      // 缓存写入失败不影响本次阅读, 静默
    }
    return chapters;
  }

  @override
  void dispose() {
    // 退出前强制落盘进度(防抖定时器可能还没触发)
    _controller.flushProgress();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.novelTitle)),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载章节...'),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.novelTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadChapters, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: ReaderView(controller: _controller),
    );
  }
}
