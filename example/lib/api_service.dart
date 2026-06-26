import 'dart:convert';
import 'package:http/http.dart' as http;

const _baseUrl = 'https://jiekou.hsheacg.com';
const _token = '66edf8383fc231389f2f846be353ebbf';

class NovelInfo {
  final String id;
  final String title;
  final String author;
  final String desc;
  final String thumb;

  NovelInfo({
    required this.id,
    required this.title,
    required this.author,
    required this.desc,
    required this.thumb,
  });
}

class ChapterInfo {
  final String id;
  final String title;
  final String content; // 纯文本，已去除HTML标签

  ChapterInfo({
    required this.id,
    required this.title,
    required this.content,
  });
}

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  /// 获取小说列表
  Future<List<NovelInfo>> fetchNovels({int page = 1}) async {
    final url = Uri.parse('$_baseUrl/api/novel/index');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('加载小说列表失败: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '未知错误');
    }
    final list = data['data']['novel'] as List;
    return list
        .map((e) => NovelInfo(
              id: e['id'].toString(),
              title: e['title'] as String,
              author: e['author'] as String,
              desc: (e['desc'] as String?) ?? '',
              thumb: (e['thumb'] as String?) ?? '',
            ))
        .toList();
  }

  /// 获取小说章节列表（含完整内容）
  Future<List<ChapterInfo>> fetchChapters(String novelId) async {
    final url = Uri.parse('$_baseUrl/api/novel/chapter');
    final response = await http.post(
      url,
      headers: _headers,
      body: json.encode({'id': int.parse(novelId)}),
    );
    if (response.statusCode != 200) {
      throw Exception('加载章节失败: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '未知错误');
    }
    final list = data['data']['novel'] as List;
    return list
        .map((e) => ChapterInfo(
              id: e['id'].toString(),
              title: (e['chatper'] as String).trim(),
              content: _stripHtml(e['content'] as String),
            ))
        .toList();
  }

  /// 去除HTML标签，将 <p> 转换为换行
  String _stripHtml(String html) {
    var text = html;
    // <p> 和 </p> 转换为换行
    text = text.replaceAll(RegExp(r'<\s*/?p\s*/?>'), '\n');
    // <br> 转换为换行
    text = text.replaceAll(RegExp(r'<\s*br\s*/?\s*>'), '\n');
    // 去除所有其他HTML标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    // HTML实体解码
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&quot;', '"');
    // 清理多余空行：连续多个换行合并为两个
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
