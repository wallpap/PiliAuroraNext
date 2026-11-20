import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/community/domain/pgc_review.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef PgcReviewPageData = ({
  List<PgcReviewItem> items,
  String? next,
  int? count,
});

abstract final class PgcReviewRepository {
  static bool _validId(Object? id) => switch (id) {
    int value => value > 0,
    String value => (int.tryParse(value) ?? 0) > 0,
    _ => false,
  };

  static Future<LoadingState<PgcReviewPageData>> list({
    required Account account,
    required PgcReviewType type,
    required Object? mediaId,
    PgcReviewSortType sort = .def,
    String? next,
  }) async {
    if (!_validId(mediaId)) return const Error('番剧标识无效，请重新打开页面');
    return Request().requestApi(
      type == .long ? Api.pgcReviewL : Api.pgcReviewS,
      kind: ApiCallKind.query,
      options: Options(extra: {'account': account}),
      queryParameters: {
        'media_id': mediaId,
        'ps': 20,
        'sort': sort == .def ? 0 : 1,
        'cursor': ?next,
        'web_location': 666.19,
      },
      decode: (body) {
        final data = body['data'] as Map<String, dynamic>;
        final rows = data['list'] as List<dynamic>? ?? const [];
        return (
          items: List<PgcReviewItem>.unmodifiable(
            rows.cast<Map<String, dynamic>>().map(_decodeItem),
          ),
          next: data['next'] as String?,
          count: (data['count'] ?? data['total']) as int?,
        );
      },
    );
  }

  static PgcReviewItem _decodeItem(Map<String, dynamic> data) {
    final author = data['author'] as Map<String, dynamic>?;
    final vip = author?['vip'] as Map<String, dynamic>?;
    final stat = data['stat'] as Map<String, dynamic>?;
    return PgcReviewItem(
      author: author == null
          ? null
          : (
              avatar: author['avatar'] as String?,
              level: author['level'] as int?,
              mid: author['mid'] as int?,
              uname: author['uname'] as String?,
              annualVip: (vip?['status'] as int? ?? 0) > 0 && vip?['type'] == 2,
            ),
      title: data['title'] as String?,
      content: data['content'] as String?,
      pushTimeStr: data['push_time_str'] as String?,
      reviewId: data['review_id'] as int?,
      articleId: data['article_id'] as int?,
      score: (data['score'] as num? ?? 0) ~/ 2,
      stat: (
        disliked: stat?['disliked'] == 1,
        liked: stat?['liked'] == 1,
        likes: stat?['likes'] as int?,
      ),
    );
  }

  static Future<LoadingState<void>> act({
    required Account account,
    required Object? mediaId,
    required Object? reviewId,
    required PgcReviewAction action,
  }) async {
    if (!_validId(mediaId)) return const Error('番剧标识无效，请重新打开页面');
    if (!_validId(reviewId)) return const Error('点评标识无效，请刷新后重试');
    return _write(
      account,
      switch (action) {
        .like => Api.pgcReviewLike,
        .dislike => Api.pgcReviewDislike,
        .delete => Api.pgcReviewDel,
      },
      {
        'media_id': mediaId,
        if (action != .delete) 'review_type': 2,
        'review_id': reviewId,
      },
    );
  }

  static Future<LoadingState<void>> submit({
    required Account account,
    required Object? mediaId,
    required int score,
    required String content,
    Object? reviewId,
    bool shareFeed = false,
  }) async {
    if (!_validId(mediaId)) return const Error('番剧标识无效，请重新打开页面');
    if (score < 1 || score > 5) return const Error('请选择有效评分');
    if (reviewId != null && !_validId(reviewId)) {
      return const Error('点评标识无效，请刷新后重试');
    }
    return _write(
      account,
      reviewId == null ? Api.pgcReviewPost : Api.pgcReviewMod,
      {
        'media_id': mediaId,
        'score': score * 2,
        'content': content,
        if (reviewId == null && shareFeed) 'share_feed': 1,
        'review_id': ?reviewId,
      },
    );
  }

  static Future<LoadingState<void>> _write(
    Account account,
    String endpoint,
    Map<String, Object?> data,
  ) => Request().requestApi<void>(
    endpoint,
    kind: ApiCallKind.mutation,
    decode: (_) {},
    data: {...data, 'csrf': account.csrf},
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      extra: {'account': account},
    ),
  );
}
