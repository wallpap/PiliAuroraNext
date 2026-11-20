import 'package:pili_aurora_next/features/favorites/domain/fav_article/item.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_detail/media.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_folder/list.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_note/list.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_pgc/list.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_topic/topic_item.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_cheese/item.dart';

export 'package:pili_aurora_next/features/favorites/domain/fav_article/item.dart';
export 'package:pili_aurora_next/features/favorites/domain/fav_detail/media.dart';
export 'package:pili_aurora_next/features/favorites/domain/fav_folder/list.dart';
export 'package:pili_aurora_next/features/favorites/domain/fav_note/list.dart';
export 'package:pili_aurora_next/features/favorites/domain/fav_pgc/list.dart';
export 'package:pili_aurora_next/features/favorites/domain/fav_topic/topic_item.dart';
export 'package:pili_aurora_next/features/member_space/domain/profiles/space_cheese/item.dart';

Object favoriteKey(Object item) => switch (item) {
  FavFolderInfo(:final id) => id,
  FavDetailItemModel(:final id, :final type) => (type, id),
  FavPgcItemModel(:final seasonId) => seasonId ?? item,
  FavArticleItemModel(:final opusId) => opusId ?? item,
  FavNoteItemModel(:final noteId, :final cvid) => (noteId, cvid),
  FavTopicItem(:final id) => id ?? item,
  SpaceCheeseItem(:final seasonId) => seasonId ?? item,
  _ => throw ArgumentError.value(item, 'item'),
};

class FavoriteMetadata {
  const FavoriteMetadata({this.folder, this.total});
  final FavFolderInfo? folder;
  final int? total;
}
