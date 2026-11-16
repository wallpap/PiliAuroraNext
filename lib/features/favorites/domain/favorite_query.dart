import 'package:pili_aurora_next/models/common/fav_order_type.dart';

enum FavoriteKind { folders, detail, pgc, article, note, topic, cheese }

enum FolderAction { clean, delete, follow, unfollow }

/// 页面身份与已提交筛选共同构成查询；输入草稿和选择不进入共享数据。
class FavoriteQuery {
  const FavoriteQuery({
    required this.owner,
    required this.kind,
    this.mediaId = 0,
    this.keyword = '',
    this.order = FavOrderType.mtime,
    this.reverse = false,
    this.type = 0,
    this.status = 0,
    this.published = false,
  });
  final Object owner;
  final FavoriteKind kind;
  final int mediaId;
  final String keyword;
  final FavOrderType order;
  final bool reverse;
  final int type;
  final int status;
  final bool published;
  Object get _key =>
      (owner, kind, mediaId, keyword, order, reverse, type, status, published);
  @override
  bool operator ==(Object other) =>
      other is FavoriteQuery && _key == other._key;
  @override
  int get hashCode => _key.hashCode;
}
