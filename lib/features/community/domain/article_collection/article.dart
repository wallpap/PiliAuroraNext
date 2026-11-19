import 'package:pili_aurora_next/features/community/domain/article_collection/stats.dart';
import 'package:pili_aurora_next/utils/extension/iterable_ext.dart';

class ArticleListItemModel {
  final int? id;
  final String? title;
  final List<String>? imageUrls;
  final String? summary;
  final String? dynIdStr;
  final Stats? stats;

  ArticleListItemModel({
    this.id,
    this.title,
    List<String>? imageUrls,
    this.summary,
    this.dynIdStr,
    this.stats,
  }) : imageUrls = imageUrls == null ? null : List.unmodifiable(imageUrls);

  factory ArticleListItemModel.fromJson(Map<String, dynamic> json) =>
      ArticleListItemModel(
        id: json['id'] as int?,
        title: json['title'] as String?,
        imageUrls: (json['image_urls'] as List?)?.fromCast(),
        summary: json['summary'] as String?,
        dynIdStr: json['dyn_id_str'] as String?,
        stats: json['stats'] == null
            ? null
            : Stats.fromJson(json['stats'] as Map<String, dynamic>),
      );
}
