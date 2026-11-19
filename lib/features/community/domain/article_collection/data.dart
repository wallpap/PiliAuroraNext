import 'package:pili_aurora_next/features/community/domain/article_collection/article.dart';
import 'package:pili_aurora_next/features/community/domain/article_collection/list.dart';
import 'package:pili_aurora_next/models/model_owner.dart';

class ArticleCollection {
  final ArticleListInfo? list;
  final List<ArticleListItemModel> articles;
  final Owner? author;

  ArticleCollection({
    this.list,
    Iterable<ArticleListItemModel> articles = const [],
    this.author,
  }) : articles = List.unmodifiable(articles);

  factory ArticleCollection.fromJson(Map<String, dynamic> json) =>
      ArticleCollection(
        list: json['list'] == null
            ? null
            : ArticleListInfo.fromJson(json['list'] as Map<String, dynamic>),
        articles: (json['articles'] as List<dynamic>? ?? []).map(
          (e) => ArticleListItemModel.fromJson(e as Map<String, dynamic>),
        ),
        author: json['author'] == null
            ? null
            : Owner.fromJson(json['author'] as Map<String, dynamic>),
      );
}
