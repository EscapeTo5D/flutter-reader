import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'api_service.dart';

void main() => runApp(const MyApp());

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
  final ReadingController _controller = ReadingController();
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
      final chapters = await _api.fetchChapters(widget.novelId);
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

  @override
  void dispose() {
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
