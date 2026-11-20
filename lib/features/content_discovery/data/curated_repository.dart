import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/weekly_catalog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final curatedRepositoryProvider = Provider((ref) => const CuratedRepository());

class CuratedRepository {
  const CuratedRepository();
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, WeeklyCatalog>>> weekly(
    Account account,
    int? number, {
    required bool Function() isCurrent,
  }) async {
    final catalog = await VideoHttp.popularSeriesList(account: account);
    if (!isCurrent()) return LoadingState.loading();
    if (catalog case Error error) return error;
    if (catalog is! Success) return LoadingState.loading();
    final series = catalog.data ?? [];
    if (series.isEmpty) {
      return Success(
        DiscoveryPage([], metadata: WeeklyCatalog(series: []), hasMore: false),
      );
    }
    number ??= series.first.number;
    final result = await VideoHttp.popularSeriesOne(
      number: number,
      account: account,
    );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.list ?? [],
          metadata: WeeklyCatalog(
            series: series,
            number: number,
            config: response.config,
            reminder: response.reminder,
          ),
          hasMore: false,
        ),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }

  Future<LoadingState<DiscoveryPage<HotVideoItemModel, ({int? mediaId})>>>
  precious(Account account, int page) async {
    final result = await VideoHttp.popularPrecious(
      page: page,
      account: account,
    );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.list ?? [],
          metadata: (mediaId: response.mediaId),
        ),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }
}
