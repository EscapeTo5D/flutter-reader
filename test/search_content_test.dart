// 搜索功能单测: 验证 ReaderSearchResult 数据模型与 SearchContentPage._findAllHits
// 算法核心不变量(命中偏移与 chapterPosition 同源 / snippet 截取 / 多命中 / 边界)。
//
// _findAllHits 是 SearchContentPage 的私有 static 方法, 通过反射不可达, 故这里
// 复刻其算法做等价测试(算法逻辑见 search_content_page.dart)。若算法变更, 同步改这里。
// 这是纯算法测试, 不依赖 Flutter binding, 不测 UI。
import 'package:flutter_reader/src/core/storage/search_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻 SearchContentPage._findAllHits 算法(保持同步)。
List<ReaderSearchResult> findAllHits(
  String processed,
  String query,
  int chapterIndex,
  String chapterTitle,
) {
  const contextRadius = 20;
  final results = <ReaderSearchResult>[];
  if (query.isEmpty || processed.isEmpty) return results;
  var from = 0;
  while (true) {
    final idx = processed.indexOf(query, from);
    if (idx < 0) break;
    final snippetStart = (idx - contextRadius).clamp(0, processed.length);
    final snippetEnd =
        (idx + query.length + contextRadius).clamp(0, processed.length);
    final snippet = processed.substring(snippetStart, snippetEnd);
    results.add(ReaderSearchResult(
      query: query,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      snippet: snippet.replaceAll('\n', ' '),
      queryIndexInSnippet: idx - snippetStart,
      charOffsetInChapter: idx,
    ));
    from = idx + query.length;
  }
  return results;
}

void main() {
  group('ReaderSearchResult 数据模型', () {
    test('字段完整往返', () {
      const r = ReaderSearchResult(
        query: '关键词',
        chapterIndex: 3,
        chapterTitle: '第三章',
        snippet: '前文关键词后文',
        queryIndexInSnippet: 2,
        charOffsetInChapter: 42,
      );
      expect(r.query, '关键词');
      expect(r.chapterIndex, 3);
      expect(r.chapterTitle, '第三章');
      expect(r.snippet, '前文关键词后文');
      expect(r.queryIndexInSnippet, 2);
      expect(r.charOffsetInChapter, 42);
    });

    test('SearchResultBrowseData 携带列表 + 索引', () {
      const r1 = ReaderSearchResult(
          query: 'q', chapterIndex: 0, chapterTitle: 't',
          snippet: 's', queryIndexInSnippet: 0, charOffsetInChapter: 0);
      const r2 = ReaderSearchResult(
          query: 'q', chapterIndex: 1, chapterTitle: 't2',
          snippet: 's', queryIndexInSnippet: 0, charOffsetInChapter: 5);
      const data = SearchResultBrowseData([r1, r2], 1);
      expect(data.results.length, 2);
      expect(data.selectedIndex, 1);
      expect(data.results[1].chapterIndex, 1);
    });
  });

  group('findAllHits 算法', () {
    test('单命中: charOffsetInChapter = 预处理后正文里的 indexOf', () {
      // 预处理后正文(模拟 ContentProcessor 输出的 join('\n'))。
      const processed = '这是第一章的正文内容包含关键词的部分。';
      final hits = findAllHits(processed, '关键词', 0, '第一章');
      expect(hits.length, 1);
      expect(hits[0].charOffsetInChapter, processed.indexOf('关键词'));
      expect(hits[0].chapterTitle, '第一章');
      expect(hits[0].query, '关键词');
    });

    test('charOffsetInChapter 与 chapterPosition 同源(关键不变量)', () {
      // 关键: 偏移必须等于该命中字符在预处理后字符串中的位置, 这样跳转时
      // 喂 pageIndexForCharOffset 才能落对页(与 TextLine.chapterPosition 同源)。
      const processed = 'AAAA关键词BBBB';
      final hits = findAllHits(processed, '关键词', 5, 't');
      expect(hits[0].charOffsetInChapter, 4);
      // snippet 内关键词起始 = 命中偏移 - snippetStart。
      expect(hits[0].queryIndexInSnippet,
          hits[0].charOffsetInChapter - (4 - 20).clamp(0, processed.length));
    });

    test('多命中: 同一章内多处匹配全部返回', () {
      const processed = '关键词开头...中间也有关键词...结尾关键词';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits.length, 3);
      // 三个命中偏移递增, 且不重叠(每次从 idx + query.length 继续)。
      expect(hits[0].charOffsetInChapter, 0);
      expect(hits[1].charOffsetInChapter, processed.indexOf('关键词', 3));
      expect(hits[2].charOffsetInChapter, processed.lastIndexOf('关键词'));
      expect(hits[1].charOffsetInChapter, greaterThan(hits[0].charOffsetInChapter));
      expect(hits[2].charOffsetInChapter, greaterThan(hits[1].charOffsetInChapter));
    });

    test('snippet 截取: 前后各约 20 字', () {
      // 关键词在中间, 前后各 20 字被截入 snippet。
      final prefix = '一' * 30;
      final suffix = '二' * 30;
      final processed = '$prefix关键词$suffix';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits.length, 1);
      final h = hits[0];
      // snippet 长度 = 20(prefix 内) + 3(query) + 20(suffix 内) = 43。
      expect(h.snippet.length, 43);
      // snippet 内关键词起始 = 20(prefix 截了 20)。
      expect(h.queryIndexInSnippet, 20);
      expect(h.snippet.substring(h.queryIndexInSnippet, h.queryIndexInSnippet + 3),
          '关键词');
    });

    test('snippet 边界: 命中靠近正文开头, snippetStart 钳到 0', () {
      const processed = '关键词后面跟很多字后面跟很多字后面跟很多字';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits[0].charOffsetInChapter, 0);
      // 命中在 0, snippetStart = max(0-20,0) = 0, queryIndexInSnippet = 0。
      expect(hits[0].queryIndexInSnippet, 0);
      expect(hits[0].snippet.startsWith('关键词'), isTrue);
    });

    test('snippet 边界: 命中靠近正文末尾, snippetEnd 钳到 length', () {
      const prefix = '前文前文前文前文';
      const processed = '$prefix关键词';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits.length, 1);
      // snippetEnd 钳到 processed.length, snippet 到末尾。
      expect(hits[0].snippet.endsWith('关键词'), isTrue);
    });

    test('snippet 换行替换为空格(单行展示)', () {
      const processed = '第一段\n第二段关键词\n第三段';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits.length, 1);
      // snippet 里的 \n 被替换成空格, 不会显示成多行。
      expect(hits[0].snippet.contains('\n'), isFalse);
    });

    test('无命中返回空列表', () {
      const processed = '这是一段不含目标词的正文';
      expect(findAllHits(processed, '不存在', 0, 't'), isEmpty);
    });

    test('空查询或空正文返回空列表', () {
      expect(findAllHits('正文', '', 0, 't'), isEmpty);
      expect(findAllHits('', '关键词', 0, 't'), isEmpty);
    });

    test('重叠查询词不重复匹配(从 idx+query.length 继续)', () {
      // 'aaa' 在 'aaaa' 中: idx=0, 下一个从 3 开始, 只匹配 1 次。
      const processed = 'aaaa';
      final hits = findAllHits(processed, 'aaa', 0, 't');
      expect(hits.length, 1);
      expect(hits[0].charOffsetInChapter, 0);
    });

    test('多章独立: chapterIndex/chapterTitle 正确透传', () {
      final ch0 = findAllHits('关键词一', '关键词', 0, '第一章');
      final ch1 = findAllHits('也有关键词', '关键词', 1, '第二章');
      expect(ch0[0].chapterIndex, 0);
      expect(ch0[0].chapterTitle, '第一章');
      expect(ch1[0].chapterIndex, 1);
      expect(ch1[0].chapterTitle, '第二章');
    });

    test('queryIndexInSnippet 越界防御: snippet 短于 query 时 queryIndex 仍有效', () {
      // 极端: processed 刚好等于 query, snippet = query, queryIndexInSnippet=0。
      const processed = '关键词';
      final hits = findAllHits(processed, '关键词', 0, 't');
      expect(hits.length, 1);
      expect(hits[0].snippet, '关键词');
      expect(hits[0].queryIndexInSnippet, 0);
      // 渲染层 _buildSnippet 的越界保护: qEnd = 0+3 = 3 = text.length, 不越界。
      expect(hits[0].queryIndexInSnippet + hits[0].query.length,
          lessThanOrEqualTo(hits[0].snippet.length));
    });
  });

  group('偏移同源性验证(与排版 chapterPosition 一致)', () {
    test('模拟 ContentProcessor 预处理后的偏移 = indexOf 结果', () {
      // 模拟: 原始正文 '正文关键词尾', ContentProcessor 加标题 + 缩进后:
      // textList = ['标题', '　　正文关键词尾'], join('\n') = '标题\n　　正文关键词尾'
      const processed = '标题\n　　正文关键词尾';
      final hits = findAllHits(processed, '关键词', 0, '标题');
      // charOffsetInChapter = processed.indexOf('关键词') = 7 (标题2 + \n1 + 缩进2 + 正文2)
      expect(hits[0].charOffsetInChapter, processed.indexOf('关键词'));
      // 这个偏移直接喂 pageIndexForCharOffset 即可落页(同源)。
      expect(hits[0].charOffsetInChapter, 7);
    });
  });
}
