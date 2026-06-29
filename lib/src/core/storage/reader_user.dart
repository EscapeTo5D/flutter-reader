/// 阅读器用户(极简, 仅作为进度/书签/设置的隔离键载体)。
///
/// 本包不负责账号登录/鉴权(那是宿主 App 的职责)。这里只承载一个稳定的 [id],
/// 用于把进度/书签/设置按用户隔离。宿主自行决定 [id] 的来源(本地生成/登录态/等)。
class ReaderUser {
  /// 全局唯一且稳定的用户标识。
  final String id;

  /// 展示名(可选, 仅用于 UI 展示)。
  final String? name;

  /// 头像 URL(可选)。
  final String? avatar;

  const ReaderUser({
    required this.id,
    this.name,
    this.avatar,
  });

  ReaderUser copyWith({String? name, String? avatar}) =>
      ReaderUser(id: id, name: name ?? this.name, avatar: avatar ?? this.avatar);

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (avatar != null) 'avatar': avatar,
      };

  factory ReaderUser.fromJson(Map<String, dynamic> json) => ReaderUser(
        id: json['id'] as String,
        name: json['name'] as String?,
        avatar: json['avatar'] as String?,
      );

  @override
  String toString() => 'ReaderUser($id${name == null ? '' : ', $name'})';
}
