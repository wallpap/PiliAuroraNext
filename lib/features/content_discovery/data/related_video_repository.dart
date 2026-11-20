import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/content_discovery/data/video_filter_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/ranked_video.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

abstract final class RelatedVideoRepository {
  static Future<LoadingState<DiscoveryPage<HotVideoItemModel, void>>> load(
    Account account,
    String bvid,
  ) => Request().requestApi(
    Api.relatedList,
    queryParameters: {'bvid': bvid},
    options: Options(extra: {'account': account}),
    kind: ApiCallKind.query,
    decode: (body) {
      final filter = VideoFilterPreferences.read();
      final items = (body['data'] as List?)?.map(
        (entry) => HotVideoItemModel.fromJson(entry),
      );
      return DiscoveryPage(
        [
          if (items != null)
            for (final item in items)
              if (!filter.includeRelated || !filter.blocksVideo(item)) item,
        ],
        metadata: null,
        hasMore: false,
      );
    },
  );
}
