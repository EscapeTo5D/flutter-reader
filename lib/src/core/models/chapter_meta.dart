/// 章节的轻量元数据: 标题 + 正文。
///
/// 用于 [ChapterSource] 的内存驱动实现([ChapterSource.fromMemory])及
/// 宿主向 [ChapterSource] 灌入数据时的中间载体。与 [Chapter] 不同,
/// 不含 `id`/`index`(index 由在列表中的位置决定), 专注于「内容」本身。
class ChapterMeta {
  final String title;
  final String content;

  const ChapterMeta({required this.title, required this.content});
}
