import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/space/space_archive/item.dart';
import 'package:pili_aurora_next/models/remote/space/space_opus/item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef SpaceListQuery = ({Object owner, int mid});
typedef SpaceOpusQuery = ({Object owner, int mid, String filter});

final spaceBangumiProvider = NotifierProvider.autoDispose
    .family<
      SpaceBangumi,
      DiscoveryListingState<SpaceArchiveItem, int>,
      SpaceListQuery
    >(
      SpaceBangumi.new,
    );

final spaceOpusProvider = NotifierProvider.autoDispose
    .family<
      SpaceOpus,
      DiscoveryListingState<SpaceOpusItemModel, String>,
      SpaceOpusQuery
    >(
      SpaceOpus.new,
    );

abstract class SpaceListing<T, M> extends DiscoveryListing<T, M> {
  @override
  bool get usesMainAccount => true;
  @override
  bool get filterAuthors => false;
}

class SpaceBangumi extends SpaceListing<SpaceArchiveItem, int> {
  SpaceBangumi(this.query);
  final SpaceListQuery query;
  @override
  Object itemKey(SpaceArchiveItem item) => item.param ?? item.uri ?? item;
  @override
  Future<LoadingState<DiscoveryPage<SpaceArchiveItem, int>>> fetch(
    Account account,
    int page,
  ) async {
    final result = await ref
        .read(spaceRepositoryProvider)
        .bangumi(account, query.mid, page);
    return switch (result) {
      Success(:final response)
          when response.item == null &&
              ((response.count ?? 0) > 0 || response.hasNext == true) =>
        const Error('番剧列表响应不完整，请重试'),
      Success(:final response) => Success(
        DiscoveryPage(
          response.item ?? const [],
          metadata: response.count ?? queryMetadata ?? 0,
          hasMore: response.hasNext ?? (response.item?.isNotEmpty ?? false),
          total: response.count ?? queryMetadata,
        ),
      ),
      Error error => error,
      Loading() => LoadingState<DiscoveryPage<SpaceArchiveItem, int>>.loading(),
    };
  }
}

class SpaceOpus extends SpaceListing<SpaceOpusItemModel, String> {
  SpaceOpus(this.query);
  final SpaceOpusQuery query;
  @override
  Object itemKey(SpaceOpusItemModel item) => item.opusId ?? item;
  @override
  Future<LoadingState<DiscoveryPage<SpaceOpusItemModel, String>>> fetch(
    Account account,
    int page,
  ) async {
    final offset = queryMetadata ?? '';
    final result = await ref
        .read(spaceRepositoryProvider)
        .opus(account, query.mid, page, offset, query.filter);
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.items ?? const [],
          metadata: response.offset ?? '',
          hasMore:
              response.hasMore != false &&
              (response.offset?.isNotEmpty ?? false) &&
              response.offset != offset,
        ),
      ),
      Error error => error,
      Loading() =>
        LoadingState<DiscoveryPage<SpaceOpusItemModel, String>>.loading(),
    };
  }
}
