import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/live_catalog.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final liveCatalogRepositoryProvider = Provider(
  (ref) => const LiveCatalogRepository(),
);

class LiveCatalogRepository {
  const LiveCatalogRepository();
  Future<LoadingState<DiscoveryPage<CardLiveItem, LiveCatalog>>> home(
    Account account,
    int page, {
    int? areaId,
    int? parentAreaId,
    String? sortType,
    LiveCatalog? previous,
    required bool Function() isCurrent,
  }) async {
    if (areaId == null) {
      final result = await LiveHttp.liveFeedIndex(pn: page, account: account);
      return switch (result) {
        Success(:final response) => Success(
          DiscoveryPage(
            (response.cardList ?? [])
                .map((card) => card.cardData?.smallCardV1)
                .whereType<CardLiveItem>()
                .toList(),
            metadata: LiveCatalog(
              followed: response.followItem ?? previous?.followed,
              areas: response.areaItem ?? previous?.areas,
            ),
            hasMore: response.hasMore != 0,
          ),
        ),
        Error error => error,
        Loading() => LoadingState.loading(),
      };
    }
    final result = await area(
      account,
      page,
      areaId: areaId,
      parentAreaId: parentAreaId,
      sortType: sortType,
      previous: previous,
    );
    if (!isCurrent() ||
        page != 1 ||
        result is! Success<DiscoveryPage<CardLiveItem, LiveCatalog>>) {
      return result;
    }
    final top = await LiveHttp.liveFeedIndex(
      pn: 1,
      moduleSelect: true,
      account: account,
    );
    final data = result.response;
    return Success(
      DiscoveryPage(
        data.items,
        total: data.total,
        hasMore: data.hasMore,
        metadata: LiveCatalog(
          followed: top.dataOrNull?.followItem,
          areas: top.dataOrNull?.areaItem,
          tags: data.metadata.tags,
          headerError: top is Error ? top.toString() : null,
        ),
      ),
    );
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
            followed: previous?.followed,
            areas: previous?.areas,
            tags: response.newTags ?? previous?.tags ?? [],
            headerError: previous?.headerError,
          ),
        ),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }
}
