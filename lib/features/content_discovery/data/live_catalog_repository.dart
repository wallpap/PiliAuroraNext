import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_area.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live/feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/http/app_sign.dart';

final liveCatalogRepositoryProvider = Provider(
  (ref) => const LiveCatalogRepository(),
);

class LiveCatalogRepository {
  const LiveCatalogRepository();

  Map<String, Object> _signedAreaParams(
    Account account, [
    Map<String, Object> extra = const {},
  ]) {
    final params = {
      'access_key': ?account.accessKey,
      'actionKey': 'appkey',
      'build': 8430300,
      'channel': 'master',
      'version': '8.43.0',
      'c_locale': 'zh_CN',
      'device': 'android',
      'disable_rcmd': 0,
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
      ...extra,
    };
    AppSign.appSign(params);
    return params;
  }

  List<AreaItem>? _decodeAreas(Object? data) => (data as List?)
      ?.map((entry) => _decodeArea(entry as Map<String, dynamic>))
      .toList();

  AreaItem _decodeArea(Map<String, dynamic> data) => AreaItem(
    id: data['id'],
    name: data['name'] as String?,
    pic: data['pic'] as String?,
    parentId: data['parent_id'],
    parentName: data['parent_name'] as String?,
  );

  Future<LoadingState<List<AreaList>?>> areas(Account account) =>
      Request().requestApi(
        Api.liveAreaList,
        kind: ApiCallKind.query,
        decode: (body) => (body['data']?['list'] as List?)
            ?.map(
              (entry) => AreaList(
                name: entry['name'] ?? '',
                areaList: _decodeAreas(entry['area_list']) ?? const [],
              ),
            )
            .toList(),
        queryParameters: _signedAreaParams(account),
        options: Options(extra: {'account': account}),
      );

  Future<LoadingState<List<AreaItem>>> favoriteTags(Account account) =>
      Request().requestApi(
        Api.getLiveFavTag,
        kind: ApiCallKind.query,
        decode: (body) => _decodeAreas(body['data']?['tags']) ?? const [],
        queryParameters: _signedAreaParams(account),
        options: Options(extra: {'account': account}),
      );

  Future<LoadingState<void>> saveFavoriteTags(
    Account account,
    Iterable<AreaItem> items,
  ) => Request().requestApi(
    Api.setLiveFavTag,
    kind: ApiCallKind.mutation,
    decode: (_) {},
    data: _signedAreaParams(account, {
      'tags': items.map((e) => e.id).join(','),
    }),
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      extra: {'account': account},
    ),
  );

  Future<LoadingState<List<AreaItem>?>> subareas(
    Account account,
    Object parentId,
  ) => Request().requestApi(
    Api.liveRoomAreaList,
    kind: ApiCallKind.query,
    decode: (body) => _decodeAreas(body['data']),
    queryParameters: _signedAreaParams(account, {
      'need_entrance': 1,
      'parent_id': parentId,
      'source_id': 2,
    }),
    options: Options(extra: {'account': account}),
  );

  Future<LoadingState<DiscoveryPage<AreaItem, void>>> directory(
    Account account,
    Object? parentId,
  ) async {
    if (parentId == null) return const Error('缺少直播分区标识');
    final result = await subareas(account, parentId);
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(response ?? [], metadata: null, hasMore: false),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }

  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> home(
    Account account,
    int page, {
    LiveCatalog? previous,
  }) async {
    final result = await LiveHttp.liveFeedIndex(pn: page, account: account);
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          (response.cardList ?? [])
              .map((card) => card.cardData?.smallCardV1)
              .whereType<CardLiveItem>()
              .toList(),
          metadata: LiveCatalog(
            followed: page == 1 ? response.followItem : previous?.followed,
            areas: page == 1 ? response.areaItem : previous?.areas,
          ),
          hasMore: response.hasMore != 0,
        ),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }

  Future<LoadingState<LiveCatalog>> homeHeader(Account account) async {
    final result = await LiveHttp.liveFeedIndex(
      pn: 1,
      moduleSelect: true,
      account: account,
    );
    return switch (result) {
      Success(:final response) => Success(
        LiveCatalog(followed: response.followItem, areas: response.areaItem),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }

  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> area(
    Account account,
    int page, {
    required Object? areaId,
    required Object? parentAreaId,
    String? sortType,
    LiveCatalog? previous,
  }) async {
    final result = await LiveHttp.liveSecondList(
      pn: page,
      areaId: areaId,
      parentAreaId: parentAreaId,
      sortType: sortType,
      account: account,
    );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.cardList ?? [],
          total: response.count,
          metadata: LiveCatalog(
            tags: response.newTags ?? previous?.tags ?? [],
          ),
        ),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }
}
