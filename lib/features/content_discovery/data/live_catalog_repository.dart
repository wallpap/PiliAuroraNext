import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/models/remote/live/live_area_list/area_item.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final liveCatalogRepositoryProvider = Provider(
  (ref) => const LiveCatalogRepository(),
);

class LiveCatalogRepository {
  const LiveCatalogRepository();
  Future<LoadingState<DiscoveryPage<AreaItem, void>>> directory(
    Account account,
    Object? parentId,
  ) async {
    if (parentId == null) return const Error('缺少直播分区标识');
    final result = await LiveHttp.liveRoomAreaList(
      parentid: parentId,
      account: account,
    );
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
