import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_fav/list.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef MemberFavoritePage = ({List<SpaceFavItemModel> items, bool hasMore});

abstract final class MemberFavoritesHttp {
  static Future<LoadingState<MemberFavoritePage>> folders({
    required Account account,
    required int mid,
    required int page,
    required bool subscribed,
  }) => Request().requestApi(
    subscribed ? Api.userSubFolder : Api.userFavFolder,
    kind: ApiCallKind.query,
    options: Options(extra: {'account': account}),
    queryParameters: {
      'up_mid': mid,
      'pn': page,
      'ps': 20,
      if (subscribed) 'platform': 'web',
    },
    decode: (body) {
      final data = body['data'] as Map<String, dynamic>;
      final hasMore = data['has_more'] as bool;
      final list = data['list'] as List?;
      if (list == null && hasMore) {
        throw const FormatException('收藏分页缺少列表');
      }
      return (
        items: [
          for (final item in list ?? const [])
            SpaceFavItemModel.fromJson(item as Map<String, dynamic>),
        ],
        hasMore: hasMore,
      );
    },
  );
}
